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
import dub.recipe.packagerecipe : ToolchainRequirements;

import std.algorithm;
import std.array;
import std.exception;
import std.file;
import std.typecons;

// Determines whether the specified process is running under WOW64 or an Intel64 of x64 processor.
version (Windows)
private Nullable!bool isWow64() {
	// See also: https://docs.microsoft.com/de-de/windows/desktop/api/sysinfoapi/nf-sysinfoapi-getnativesysteminfo
	import core.sys.windows.windows : GetNativeSystemInfo, SYSTEM_INFO, PROCESSOR_ARCHITECTURE_AMD64;

	static Nullable!bool result;

	// A process's architecture won't change over while the process is in memory
	// Return the cached result
	if (!result.isNull)
		return result;

	SYSTEM_INFO systemInfo;
	GetNativeSystemInfo(&systemInfo);
	result = systemInfo.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_AMD64;
	return result;
}

class DMDCompiler : Compiler {
	private static immutable s_options = [
		tuple(BuildOption.debugMode, ["-debug"]),
		tuple(BuildOption.releaseMode, ["-release"]),
		tuple(BuildOption.coverage, ["-cov"]),
		tuple(BuildOption.debugInfo, ["-g"]),
		tuple(BuildOption.debugInfoC, ["-g"]),
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
		tuple(BuildOption.betterC, ["-betterC"]),

		tuple(BuildOption._docs, ["-Dddocs"]),
		tuple(BuildOption._ddox, ["-Xfdocs.json", "-Df__dummy.html"]),
	];

	@property string name() const { return "dmd"; }

	enum dmdVersionRe = `^version\s+v?(\d+\.\d+\.\d+[A-Za-z0-9.+-]*)`;

	unittest {
		import std.regex : matchFirst, regex;
		auto probe = `
binary    dmd
version   v2.082.0
config    /etc/dmd.conf
`;
		auto re = regex(dmdVersionRe, "m");
		auto c = matchFirst(probe, re);
		assert(c && c.length > 1 && c[1] == "2.082.0");
	}

	unittest {
		import std.regex : matchFirst, regex;
		auto probe = `
binary    dmd
version   v2.084.0-beta.1
config    /etc/dmd.conf
`;
		auto re = regex(dmdVersionRe, "m");
		auto c = matchFirst(probe, re);
		assert(c && c.length > 1 && c[1] == "2.084.0-beta.1");
	}

	string determineVersion(string compiler_binary, string verboseOutput)
	{
		import std.regex : matchFirst, regex;
		auto ver = matchFirst(verboseOutput, regex(dmdVersionRe, "m"));
		return ver && ver.length > 1 ? ver[1] : null;
	}

	BuildPlatform determinePlatform(ref BuildSettings settings, string compiler_binary, string arch_override)
	{
		string[] arch_flags;
		switch (arch_override) {
			default: throw new Exception("Unsupported architecture: "~arch_override);
			case "":
				// Don't use Optlink by default on Windows
				version (Windows) {
					const is64bit = isWow64();
					if (!is64bit.isNull)
						arch_flags = [is64bit.get ? "-m64" : "-m32mscoff"];
				}
				break;
			case "x86": arch_flags = ["-m32"]; break;
			case "x86_omf": arch_flags = ["-m32"]; break;
			case "x86_64": arch_flags = ["-m64"]; break;
			case "x86_mscoff": arch_flags = ["-m32mscoff"]; break;
		}
		settings.addDFlags(arch_flags);

		return probePlatform(
			compiler_binary,
			arch_flags ~ ["-quiet", "-c", "-o-", "-v"],
			arch_override
		);
	}
	version (Windows) version (DigitalMars) unittest
	{
		BuildSettings settings;
		auto compiler = new DMDCompiler;
		auto bp = compiler.determinePlatform(settings, "dmd", "x86");
		assert(bp.platform.canFind("windows"));
		assert(bp.architecture.canFind("x86"));
		assert(bp.architecture.canFind("x86_omf"));
		assert(!bp.architecture.canFind("x86_mscoff"));
		settings = BuildSettings.init;
		bp = compiler.determinePlatform(settings, "dmd", "x86_omf");
		assert(bp.platform.canFind("windows"));
		assert(bp.architecture.canFind("x86"));
		assert(bp.architecture.canFind("x86_omf"));
		assert(!bp.architecture.canFind("x86_mscoff"));
		settings = BuildSettings.init;
		bp = compiler.determinePlatform(settings, "dmd", "x86_mscoff");
		assert(bp.platform.canFind("windows"));
		assert(bp.architecture.canFind("x86"));
		assert(!bp.architecture.canFind("x86_omf"));
		assert(bp.architecture.canFind("x86_mscoff"));
		settings = BuildSettings.init;
		bp = compiler.determinePlatform(settings, "dmd", "x86_64");
		assert(bp.platform.canFind("windows"));
		assert(bp.architecture.canFind("x86_64"));
		assert(!bp.architecture.canFind("x86"));
		assert(!bp.architecture.canFind("x86_omf"));
		assert(!bp.architecture.canFind("x86_mscoff"));
		settings = BuildSettings.init;
		bp = compiler.determinePlatform(settings, "dmd", "");
		if (!isWow64.isNull && !isWow64.get) assert(bp.architecture.canFind("x86"));
		if (!isWow64.isNull && !isWow64.get) assert(bp.architecture.canFind("x86_mscoff"));
		if (!isWow64.isNull && !isWow64.get) assert(!bp.architecture.canFind("x86_omf"));
		if (!isWow64.isNull &&  isWow64.get) assert(bp.architecture.canFind("x86_64"));
	}

	version (LDC) unittest {
		BuildSettings settings;
		auto compiler = new DMDCompiler;
		auto bp = compiler.determinePlatform(settings, "ldmd2", "x86");
		assert(bp.architecture.canFind("x86"));
		assert(!bp.architecture.canFind("x86_omf"));
		bp = compiler.determinePlatform(settings, "ldmd2", "");
		version (X86) assert(bp.architecture.canFind("x86"));
		version (X86_64) assert(bp.architecture.canFind("x86_64"));
		assert(!bp.architecture.canFind("x86_omf"));
	}

	void prepareBuildSettings(ref BuildSettings settings, const scope ref BuildPlatform platform,
                              BuildSetting fields = BuildSetting.all) const
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
			resolveLibs(settings, platform);
			if (platform.platform.canFind("windows"))
				settings.addSourceFiles(settings.libs.map!(l => l~".lib")().array());
			else
				settings.addLFlags(settings.libs.map!(l => "-l"~l)().array());
		}

		if (!(fields & BuildSetting.sourceFiles)) {
			settings.addDFlags(settings.sourceFiles);
			settings.sourceFiles = null;
		}

		if (!(fields & BuildSetting.lflags)) {
			settings.addDFlags(lflagsToDFlags(settings.lflags));
			settings.lflags = null;
		}

		if (platform.platform.canFind("posix") && (settings.options & BuildOption.pic))
			settings.addDFlags("-fPIC");

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
		import std.conv: text;
		assert(settings.targetName.length > 0, "No target name set.");
		final switch (settings.targetType) {
			case TargetType.autodetect:
				assert(false,
					   text("Configurations must have a concrete target type, ", settings.targetName,
							" has ", settings.targetType));
			case TargetType.none: return null;
			case TargetType.sourceLibrary: return null;
			case TargetType.executable:
				if (platform.platform.canFind("windows"))
					return settings.targetName ~ ".exe";
				else return settings.targetName.idup;
			case TargetType.library:
			case TargetType.staticLibrary:
				if (platform.platform.canFind("windows"))
					return settings.targetName ~ ".lib";
				else return "lib" ~ settings.targetName ~ ".a";
			case TargetType.dynamicLibrary:
				if (platform.platform.canFind("windows"))
					return settings.targetName ~ ".dll";
				else if (platform.platform.canFind("darwin"))
					return "lib" ~ settings.targetName ~ ".dylib";
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
				if (platform.compiler != "dmd" || platform.platform.canFind("windows") || platform.platform.canFind("osx"))
					settings.addDFlags("-shared");
				else
					settings.prependDFlags("-shared", "-defaultlib=libphobos2.so");
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
		invokeTool([platform.compilerBinary, "@"~res_file.toNativeString()], output_callback);
	}

	void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects, void delegate(int, string) output_callback)
	{
		import std.string;
		auto tpath = NativePath(settings.targetPath) ~ getTargetFileName(settings, platform);
		auto args = ["-of"~tpath.toNativeString()];
		args ~= objects;
		args ~= settings.sourceFiles;
		if (platform.platform.canFind("linux"))
			args ~= "-L--no-as-needed"; // avoids linker errors due to libraries being specified in the wrong order by DMD
		args ~= lflagsToDFlags(settings.lflags);
		if (platform.compiler == "ldc") {
			// ldmd2: support the full LDC-specific list + extra "-m32mscoff", a superset of the DMD list
			import dub.compilers.ldc : LDCCompiler;
			args ~= settings.dflags.filter!(f => f == "-m32mscoff" || LDCCompiler.isLinkerDFlag(f)).array;
		} else {
			args ~= settings.dflags.filter!(f => isLinkerDFlag(f)).array;
		}

		auto res_file = getTempFile("dub-build", ".lnk");
		std.file.write(res_file.toNativeString(), escapeArgs(args).join("\n"));

		logDiagnostic("%s %s", platform.compilerBinary, escapeArgs(args).join(" "));
		invokeTool([platform.compilerBinary, "@"~res_file.toNativeString()], output_callback);
	}

	string[] lflagsToDFlags(in string[] lflags) const
	{
        return map!(f => "-L"~f)(lflags.filter!(f => f != "")()).array();
	}

	private auto escapeArgs(in string[] args)
	{
		return args.map!(s => s.canFind(' ') ? "\""~s~"\"" : s);
	}

	static bool isLinkerDFlag(string arg)
	{
		switch (arg) {
			case "-g", "-gc", "-m32", "-m64", "-shared", "-lib", "-m32mscoff", "-betterC":
				return true;
			default:
				return arg.startsWith("-L")
				    || arg.startsWith("-Xcc=")
				    || arg.startsWith("-defaultlib=");
		}
	}
}
