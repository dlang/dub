/**
	DMD compiler support.

	Copyright: © 2013-2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.dmd;

import dub.compilers.compiler;
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


class DmdCompiler : Compiler {
	private static immutable s_options = [
		tuple(BuildOptions.debug_, ["-debug"]),
		tuple(BuildOptions.release, ["-release"]),
		tuple(BuildOptions.coverage, ["-cov"]),
		tuple(BuildOptions.debugInfo, ["-g"]),
		tuple(BuildOptions.debugInfoC, ["-gc"]),
		tuple(BuildOptions.alwaysStackFrame, ["-gs"]),
		tuple(BuildOptions.stackStomping, ["-gx"]),
		tuple(BuildOptions.inline, ["-inline"]),
		tuple(BuildOptions.noBoundsChecks, ["-noboundscheck"]),
		tuple(BuildOptions.optimize, ["-O"]),
		tuple(BuildOptions.profile, ["-profile"]),
		tuple(BuildOptions.unittests, ["-unittest"]),
		tuple(BuildOptions.verbose, ["-v"]),
		tuple(BuildOptions.ignoreUnknownPragmas, ["-ignore"]),
		tuple(BuildOptions.syntaxOnly, ["-o-"]),
		tuple(BuildOptions.warnings, ["-wi"]),
		tuple(BuildOptions.warningsAsErrors, ["-w"]),
		tuple(BuildOptions.ignoreDeprecations, ["-d"]),
		tuple(BuildOptions.deprecationWarnings, ["-dw"]),
		tuple(BuildOptions.deprecationErrors, ["-de"]),
		tuple(BuildOptions.property, ["-property"]),
	];

	@property string name() const { return "dmd"; }

	BuildPlatform determinePlatform(ref BuildSettings settings, string compiler_binary, string arch_override)
	{
		// TODO: determine platform by invoking the compiler instead
		BuildPlatform build_platform;
		build_platform.platform = .determinePlatform();
		build_platform.architecture = .determineArchitecture();
		build_platform.compiler = this.name;
		build_platform.compilerBinary = compiler_binary;

		switch (arch_override) {
			default: throw new Exception("Unsupported architecture: "~arch_override);
			case "": break;
			case "x86":
				build_platform.architecture = ["x86"];
				settings.addDFlags("-m32");
				break;
			case "x86_64":
				build_platform.architecture = ["x86_64"];
				settings.addDFlags("-m64");
				break;
		}
		return build_platform;
	}

	void prepareBuildSettings(ref BuildSettings settings, BuildSetting fields = BuildSetting.all)
	{
		enforceBuildRequirements(settings);

		if (!(fields & BuildSetting.options)) {
			foreach (t; s_options)
				if (settings.options & t[0])
					settings.addDFlags(t[1]);
		}

		if (!(fields & BuildSetting.libs)) {
			resolveLibs(settings);
			version(Windows) settings.addSourceFiles(settings.libs.map!(l => l~".lib")().array());
			else settings.addLFlags(settings.libs.map!(l => "-l"~l)().array());
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

		if (!(fields & BuildSetting.sourceFiles)) {
			settings.addDFlags(settings.sourceFiles);
			settings.sourceFiles = null;
		}

		if (!(fields & BuildSetting.lflags)) {
			settings.addDFlags(settings.lflags.map!(f => "-L"~f)().array());
			settings.lflags = null;
		}

		assert(fields & BuildSetting.dflags);
		assert(fields & BuildSetting.copyFiles);
	}

	void extractBuildOptions(ref BuildSettings settings)
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

	void setTarget(ref BuildSettings settings, in BuildPlatform platform)
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
				else settings.addDFlags("-shared", "-fPIC");
				break;
		}

		auto tpath = Path(settings.targetPath) ~ getTargetFileName(settings, platform);
		settings.addDFlags("-of"~tpath.toNativeString());
	}

	void invoke(in BuildSettings settings, in BuildPlatform platform)
	{
		auto res_file = getTempDir() ~ ("dub-build-"~uniform(0, uint.max).to!string~"-.rsp");
		std.file.write(res_file.toNativeString(), join(settings.dflags.map!(s => s.canFind(' ') ? "\""~s~"\"" : s), "\n"));
		scope (exit) remove(res_file.toNativeString());

		logDiagnostic("%s %s", platform.compilerBinary, join(cast(string[])settings.dflags, " "));
		auto compiler_pid = spawnProcess([platform.compilerBinary, "@"~res_file.toNativeString()]);
		auto result = compiler_pid.wait();
		enforce(result == 0, "DMD compile run failed with exit code "~to!string(result));
	}

	void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects)
	{
		import std.string;
		auto tpath = Path(settings.targetPath) ~ getTargetFileName(settings, platform);
		auto args = [platform.compiler, "-of"~tpath.toNativeString()] ~ objects ~ settings.lflags.map!(l => "-L"~l)().array() ~ settings.sourceFiles;
		static linkerargs = ["-g", "-gc", "-m32", "-m64", "-shared"];
		args ~= settings.dflags.filter!(f => linkerargs.canFind(f))().array();
		logDiagnostic("%s", args.join(" "));
		auto res = spawnProcess(args).wait();
		enforce(res == 0, "Link command failed with exit code "~to!string(res));
	}
}
