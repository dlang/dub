/**
	DMD compiler support.

	Copyright: © 2013-2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.dmd;

import dub.compilers.compiler;
import dub.compilers.utils;
import dub.internal.utils;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.inet.path;
import dub.platform;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.process;
import std.random;
import std.typecons;


class DMDCompiler : Compiler {
	private static immutable s_options = [
		tuple(BuildOption.debugMode, ["-debug"]),
		tuple(BuildOption.releaseMode, ["-release"]),
		tuple(BuildOption.coverage, ["-cov"]),
		tuple(BuildOption.debugInfo, ["-g"]),
		tuple(BuildOption.debugInfoC, ["-gc"]),
		tuple(BuildOption.alwaysStackFrame, ["-gs"]),
		tuple(BuildOption.stackStomping, ["-gx"]),
		tuple(BuildOption.inline, ["-inline"]),
		tuple(BuildOption.noBoundsCheck, ["-noboundscheck"]),
		tuple(BuildOption.optimize, ["-O"]),
		tuple(BuildOption.profile, ["-profile"]),
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
		tuple(BuildOption.profileGC, ["-profile=gc"]),

		tuple(BuildOption._docs, ["-Dddocs"]),
		tuple(BuildOption._ddox, ["-Xfdocs.json", "-Df__dummy.html"]),
	];

	@property string name() const { return "dmd"; }

	BuildPlatform determinePlatform(ref BuildSettings settings, string compiler_binary, string arch_override)
	{
		import std.process;
		import std.string;

		auto fil = generatePlatformProbeFile();

		string[] arch_flags;

		switch (arch_override) {
			default: throw new Exception("Unsupported architecture: "~arch_override);
			case "": break;
			case "x86": arch_flags = ["-m32"]; break;
			case "x86_64": arch_flags = ["-m64"]; break;
		}
		settings.addDFlags(arch_flags);

		auto result = executeShell(escapeShellCommand(compiler_binary ~ arch_flags ~
			["-quiet", "-c", "-o-", fil.toNativeString()]));
		enforce(result.status == 0, format("Failed to invoke the compiler %s to determine the build platform: %s",
			compiler_binary, result.output));

		auto build_platform = readPlatformProbe(result.output);
		build_platform.compilerBinary = compiler_binary;

		if (build_platform.compiler != this.name) {
			logWarn(`The determined compiler type "%s" doesn't match the expected type "%s". This will probably result in build errors.`,
				build_platform.compiler, this.name);
		}

		if (arch_override.length && !build_platform.architecture.canFind(arch_override)) {
			logWarn(`Failed to apply the selected architecture %s. Got %s.`,
				arch_override, build_platform.architecture);
		}

		return build_platform;
	}

	void prepareBuildSettings(ref BuildSettings settings, BuildSetting fields = BuildSetting.all) const
	{
		enforceBuildRequirements(settings);

		if (!(fields & BuildSetting.options)) {
			foreach (t; s_options)
				if (settings.options & t[0])
					settings.addDFlags(t[1]);
		}

		if (!(fields & BuildSetting.versions)) {
			settings.addDFlags(settings.versions.map!(s => "-version="~s)().array());
			settings.versions = null;
		}

		if (!(fields & BuildSetting.debugVersions)) {
			settings.addDFlags(settings.debugVersions.map!(s => "-debug="~s)().array());
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

		if (!(fields & BuildSetting.libs)) {
			resolveLibs(settings);
			version(Windows) settings.addSourceFiles(settings.libs.map!(l => l~".lib")().array());
			else settings.addLFlags(settings.libs.map!(l => "-l"~l)().array());
		}

		if (!(fields & BuildSetting.sourceFiles)) {
			settings.addDFlags(settings.sourceFiles);
			settings.sourceFiles = null;
		}

		if (!(fields & BuildSetting.lflags)) {
			settings.addDFlags(lflagsToDFlags(settings.lflags));
			settings.lflags = null;
		}

		version (Posix) {
			if (settings.targetType == TargetType.dynamicLibrary)
				settings.addDFlags("-fPIC");
		}

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
			if (f.startsWith("-version=")) settings.addVersions(f[9 .. $]);
			else if (f.startsWith("-debug=")) settings.addDebugVersions(f[7 .. $]);
			else newflags ~= f;
		}
		settings.dflags = newflags.data;
	}

	string getTargetFileName(in BuildSettings settings, in BuildPlatform platform)
	const {
		assert(settings.targetName.length > 0, "No target name set.");
		final switch (settings.targetType) {
			case TargetType.autodetect: assert(false, "Configurations must have a concrete target type.");
			case TargetType.none: return null;
			case TargetType.sourceLibrary: return null;
			case TargetType.executable:
				if (platform.platform.canFind("windows"))
					return settings.targetName ~ ".exe";
				else return settings.targetName;
			case TargetType.library:
			case TargetType.staticLibrary:
				if (platform.platform.canFind("windows"))
					return settings.targetName ~ ".lib";
				else return "lib" ~ settings.targetName ~ ".a";
			case TargetType.dynamicLibrary:
				if (platform.platform.canFind("windows"))
					return settings.targetName ~ ".dll";
				else return "lib" ~ settings.targetName ~ ".so";
			case TargetType.object:
				if (platform.platform.canFind("windows"))
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
				version (Windows) settings.addDFlags("-shared");
				else version (OSX) settings.addDFlags("-shared");
				else settings.addDFlags("-shared", "-defaultlib=libphobos2.so");
				break;
			case TargetType.object:
				settings.addDFlags("-c");
				break;
		}

		if (tpath is null)
			tpath = (Path(settings.targetPath) ~ getTargetFileName(settings, platform)).toNativeString();
		settings.addDFlags("-of"~tpath);
	}

	void invoke(in BuildSettings settings, in BuildPlatform platform, void delegate(int, string) output_callback)
	{
		auto res_file = getTempFile("dub-build", ".rsp");
		const(string)[] args = settings.dflags;
		if (platform.frontendVersion >= 2066) args ~= "-vcolumns";
		std.file.write(res_file.toNativeString(), escapeArgs(args).join("\n"));

		logDiagnostic("%s %s", platform.compilerBinary, escapeArgs(args).join(" "));
		invokeTool([platform.compilerBinary, "@"~res_file.toNativeString()], output_callback);
	}

	void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects, void delegate(int, string) output_callback)
	{
		import std.string;
		auto tpath = Path(settings.targetPath) ~ getTargetFileName(settings, platform);
		auto args = ["-of"~tpath.toNativeString()];
		args ~= objects;
		args ~= settings.sourceFiles;
		version(linux) args ~= "-L--no-as-needed"; // avoids linker errors due to libraries being speficied in the wrong order by DMD
		args ~= lflagsToDFlags(settings.lflags);
		args ~= settings.dflags.filter!(f => isLinkerDFlag(f)).array;

		auto res_file = getTempFile("dub-build", ".lnk");
		std.file.write(res_file.toNativeString(), escapeArgs(args).join("\n"));

		logDiagnostic("%s %s", platform.compilerBinary, escapeArgs(args).join(" "));
		invokeTool([platform.compilerBinary, "@"~res_file.toNativeString()], output_callback);
	}

	string[] lflagsToDFlags(in string[] lflags) const
	{
		return  lflags.map!(f => "-L"~f)().array();
	}

	private auto escapeArgs(in string[] args)
	{
		return args.map!(s => s.canFind(' ') ? "\""~s~"\"" : s);
	}

	private static bool isLinkerDFlag(string arg)
	{
		switch (arg) {
			default:
				if (arg.startsWith("-defaultlib=")) return true;
				return false;
			case "-g", "-gc", "-m32", "-m64", "-shared", "-lib", "-m32mscoff":
				return true;
		}
	}
}
