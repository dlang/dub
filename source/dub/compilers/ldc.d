/**
	LDC compiler support.

	Copyright: © 2013-2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.ldc;

import dub.compilers.compiler;
import dub.compilers.utils;
import dub.internal.utils;
import dub.internal.vibecompat.inet.path;
import dub.logging;

import std.algorithm;
import std.array;
import std.exception;
import std.file;
import std.typecons;


class LDCCompiler : Compiler {
	private static immutable s_options = [
		tuple(BuildOption.debugMode, ["-d-debug"]),
		tuple(BuildOption.releaseMode, ["-release"]),
		tuple(BuildOption.coverage, ["-cov"]),
		tuple(BuildOption.coverageCTFE, ["-cov=ctfe"]),
		tuple(BuildOption.debugInfo, ["-g"]),
		tuple(BuildOption.debugInfoC, ["-gc"]),
		tuple(BuildOption.alwaysStackFrame, ["-disable-fp-elim"]),
		//tuple(BuildOption.stackStomping, ["-?"]),
		tuple(BuildOption.inline, ["-enable-inlining", "-Hkeep-all-bodies"]),
		tuple(BuildOption.noBoundsCheck, ["-boundscheck=off"]),
		tuple(BuildOption.optimize, ["-O3"]),
		tuple(BuildOption.profile, ["-fdmd-trace-functions"]),
		tuple(BuildOption.unittests, ["-unittest"]),
		tuple(BuildOption.verbose, ["-v"]),
		tuple(BuildOption.ignoreUnknownPragmas, ["-ignore"]),
		tuple(BuildOption.syntaxOnly, ["-o-"]),
		tuple(BuildOption.warnings, ["-wi"]),
		tuple(BuildOption.warningsAsErrors, ["-w"]),
		tuple(BuildOption.ignoreDeprecations, ["-d"]),
		tuple(BuildOption.deprecationWarnings, ["-dw"]),
		tuple(BuildOption.deprecationErrors, ["-de"]),
		tuple(BuildOption.property, ["-property"]),
		//tuple(BuildOption.profileGC, ["-?"]),
		tuple(BuildOption.betterC, ["-betterC"]),
		tuple(BuildOption.lowmem, ["-lowmem"]),

		tuple(BuildOption._docs, ["-Dd=docs"]),
		tuple(BuildOption._ddox, ["-Xf=docs.json", "-Dd=__dummy_docs"]),
	];

	@property string name() const { return "ldc"; }

	enum ldcVersionRe = `^version\s+v?(\d+\.\d+\.\d+[A-Za-z0-9.+-]*)`;

	unittest {
		import std.regex : matchFirst, regex;
		auto probe = `
binary    /usr/bin/ldc2
version   1.11.0 (DMD v2.081.2, LLVM 6.0.1)
config    /etc/ldc2.conf (x86_64-pc-linux-gnu)
`;
		auto re = regex(ldcVersionRe, "m");
		auto c = matchFirst(probe, re);
		assert(c && c.length > 1 && c[1] == "1.11.0");
	}

	string determineVersion(string compiler_binary, string verboseOutput)
	{
		import std.regex : matchFirst, regex;
		auto ver = matchFirst(verboseOutput, regex(ldcVersionRe, "m"));
		return ver && ver.length > 1 ? ver[1] : null;
	}

	BuildPlatform determinePlatform(ref BuildSettings settings, string compiler_binary, string arch_override)
	{
		string[] arch_flags;
		switch (arch_override) {
			case "": break;
			case "x86": arch_flags = ["-march=x86"]; break;
			case "x86_mscoff": arch_flags = ["-march=x86"]; break;
			case "x86_64": arch_flags = ["-march=x86-64"]; break;
			case "aarch64": arch_flags = ["-march=aarch64"]; break;
			case "powerpc64": arch_flags = ["-march=powerpc64"]; break;
			default:
				if (arch_override.canFind('-'))
					arch_flags = ["-mtriple="~arch_override];
				else
					throw new UnsupportedArchitectureException(arch_override);
				break;
		}
		settings.addDFlags(arch_flags);

		return probePlatform(
			compiler_binary,
			arch_flags ~ ["-c", "-o-", "-v"],
			arch_override
		);
	}

	void prepareBuildSettings(ref BuildSettings settings, const scope ref BuildPlatform platform, BuildSetting fields = BuildSetting.all) const
	{
		import std.format : format;
		enforceBuildRequirements(settings);

		if (!(fields & BuildSetting.options)) {
			foreach (t; s_options)
				if (settings.options & t[0])
					settings.addDFlags(t[1]);
		}

		// since LDC always outputs multiple object files, avoid conflicts by default
		settings.addDFlags("--oq", format("-od=%s/obj", settings.targetPath));

		if (!(fields & BuildSetting.versions)) {
			settings.addDFlags(settings.versions.map!(s => "-d-version="~s)().array());
			settings.versions = null;
		}

		if (!(fields & BuildSetting.debugVersions)) {
			settings.addDFlags(settings.debugVersions.map!(s => "-d-debug="~s)().array());
			settings.debugVersions = null;
		}

		if (!(fields & BuildSetting.importPaths)) {
			settings.addDFlags(settings.importPaths.map!(s => "-I"~s)().array());
			settings.importPaths = null;
		}

		if (!(fields & BuildSetting.stringImportPaths)) {
			settings.addDFlags(settings.stringImportPaths.map!(s => "-J"~s)().array());
			settings.stringImportPaths = null;
		}

		if (!(fields & BuildSetting.sourceFiles)) {
			settings.addDFlags(settings.sourceFiles);
			settings.sourceFiles = null;
		}

		if (!(fields & BuildSetting.libs)) {
			resolveLibs(settings, platform);
			settings.addLFlags(settings.libs.map!(l => "-l"~l)().array());
		}

		if (!(fields & BuildSetting.lflags)) {
			settings.addDFlags(lflagsToDFlags(settings.lflags));
			settings.lflags = null;
		}

		if (settings.options & BuildOption.pic)
			settings.addDFlags("-relocation-model=pic");

		assert(fields & BuildSetting.dflags);
		assert(fields & BuildSetting.copyFiles);
	}

	void extractBuildOptions(ref BuildSettings settings) const
	{
		Appender!(string[]) newflags;
		next_flag: foreach (f; settings.dflags) {
			foreach (t; s_options)
				if (t[1].canFind(f)) {
					settings.options |= t[0];
					continue next_flag;
				}
			if (f.startsWith("-d-version=")) settings.addVersions(f[11 .. $]);
			else if (f.startsWith("-d-debug=")) settings.addDebugVersions(f[9 .. $]);
			else newflags ~= f;
		}
		settings.dflags = newflags.data;
	}

	string getTargetFileName(in BuildSettings settings, in BuildPlatform platform)
	const {
		assert(settings.targetName.length > 0, "No target name set.");

		const p = platform.platform;
		final switch (settings.targetType) {
			case TargetType.autodetect: assert(false, "Configurations must have a concrete target type.");
			case TargetType.none: return null;
			case TargetType.sourceLibrary: return null;
			case TargetType.executable:
				if (p.canFind("windows"))
					return settings.targetName ~ ".exe";
				else if (p.canFind("wasm"))
					return settings.targetName ~ ".wasm";
				else return settings.targetName.idup;
			case TargetType.library:
			case TargetType.staticLibrary:
				if (p.canFind("windows") && !p.canFind("mingw"))
					return settings.targetName ~ ".lib";
				else return "lib" ~ settings.targetName ~ ".a";
			case TargetType.dynamicLibrary:
				if (p.canFind("windows"))
					return settings.targetName ~ ".dll";
				else if (p.canFind("darwin"))
					return "lib" ~ settings.targetName ~ ".dylib";
				else return "lib" ~ settings.targetName ~ ".so";
			case TargetType.object:
				if (p.canFind("windows"))
					return settings.targetName ~ ".obj";
				else return settings.targetName ~ ".o";
		}
	}

	void setTarget(ref BuildSettings settings, in BuildPlatform platform, string tpath = null) const
	{
		final switch (settings.targetType) {
			case TargetType.autodetect: assert(false, "Invalid target type: autodetect");
			case TargetType.none: assert(false, "Invalid target type: none");
			case TargetType.sourceLibrary: assert(false, "Invalid target type: sourceLibrary");
			case TargetType.executable: break;
			case TargetType.library:
			case TargetType.staticLibrary:
				settings.addDFlags("-lib");
				break;
			case TargetType.dynamicLibrary:
				settings.addDFlags("-shared");
				break;
			case TargetType.object:
				settings.addDFlags("-c");
				break;
		}

		if (tpath is null)
			tpath = (NativePath(settings.targetPath) ~ getTargetFileName(settings, platform)).toNativeString();
		settings.addDFlags("-of"~tpath);
	}

	void invoke(in BuildSettings settings, in BuildPlatform platform, void delegate(int, string) output_callback)
	{
		auto res_file = getTempFile("dub-build", ".rsp");
		const(string)[] args = settings.dflags;
		if (platform.frontendVersion >= 2066) args ~= "-vcolumns";
		std.file.write(res_file.toNativeString(), escapeArgs(args).join("\n"));

		logDiagnostic("%s %s", platform.compilerBinary, escapeArgs(args).join(" "));
		string[string] env;
		foreach (aa; [settings.environments, settings.buildEnvironments])
			foreach (k, v; aa)
				env[k] = v;
		invokeTool([platform.compilerBinary, "@"~res_file.toNativeString()], output_callback, env);
	}

	void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects, void delegate(int, string) output_callback)
	{
		import std.string;
		auto tpath = NativePath(settings.targetPath) ~ getTargetFileName(settings, platform);
		auto args = ["-of"~tpath.toNativeString()];
		args ~= objects;
		args ~= settings.sourceFiles;
		if (platform.platform.canFind("linux"))
			args ~= "-L--no-as-needed"; // avoids linker errors due to libraries being specified in the wrong order
		args ~= lflagsToDFlags(settings.lflags);
		args ~= settings.dflags.filter!(f => isLinkerDFlag(f)).array;

		auto res_file = getTempFile("dub-build", ".lnk");
		std.file.write(res_file.toNativeString(), escapeArgs(args).join("\n"));

		logDiagnostic("%s %s", platform.compilerBinary, escapeArgs(args).join(" "));
		string[string] env;
		foreach (aa; [settings.environments, settings.buildEnvironments])
			foreach (k, v; aa)
				env[k] = v;
		invokeTool([platform.compilerBinary, "@"~res_file.toNativeString()], output_callback, env);
	}

	string[] lflagsToDFlags(const string[] lflags) const
	{
        return map!(f => "-L"~f)(lflags.filter!(f => f != "")()).array();
	}

	private auto escapeArgs(in string[] args)
	{
		return args.map!(s => s.canFind(' ') ? "\""~s~"\"" : s);
	}

	static bool isLinkerDFlag(string arg)
	{
		if (arg.length > 2 && arg.startsWith("--"))
			arg = arg[1 .. $]; // normalize to 1 leading hyphen

		switch (arg) {
			case "-g", "-gc", "-m32", "-m64", "-shared", "-lib",
			     "-betterC", "-disable-linker-strip-dead", "-static":
				return true;
			default:
				return arg.startsWith("-L")
				    || arg.startsWith("-Xcc=")
				    || arg.startsWith("-defaultlib=")
				    || arg.startsWith("-platformlib=")
				    || arg.startsWith("-flto")
				    || arg.startsWith("-fsanitize=")
				    || arg.startsWith("-gcc=")
				    || arg.startsWith("-link-")
				    || arg.startsWith("-linker=")
				    || arg.startsWith("-march=")
				    || arg.startsWith("-mscrtlib=")
				    || arg.startsWith("-mtriple=");
		}
	}
}
