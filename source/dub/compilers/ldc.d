/**
	LDC compiler support.

	Copyright: © 2013-2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.ldc;

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


class LdcCompiler : Compiler {
	private static immutable s_options = [
		tuple(BuildOptions.debugMode, ["-d-debug"]),
		tuple(BuildOptions.releaseMode, ["-release"]),
		//tuple(BuildOptions.coverage, ["-?"]),
		tuple(BuildOptions.debugInfo, ["-g"]),
		tuple(BuildOptions.debugInfoC, ["-gc"]),
		//tuple(BuildOptions.alwaysStackFrame, ["-?"]),
		//tuple(BuildOptions.stackStomping, ["-?"]),
		tuple(BuildOptions.inline, ["-enable-inlining"]),
		tuple(BuildOptions.noBoundsCheck, ["-disable-boundscheck"]),
		tuple(BuildOptions.optimize, ["-O"]),
		//tuple(BuildOptions.profile, ["-?"]),
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

	@property string name() const { return "ldc"; }

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
				settings.addDFlags("-march=x86");
				break;
			case "x86_64":
				build_platform.architecture = ["x86_64"];
				settings.addDFlags("-march=x86_64");
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

		// since LDC always outputs multiple object files, avoid conflicts by default
		settings.addDFlags("-oq", "-od=.dub/obj");
	
		if (!(fields & BuildSetting.libs)) {
			resolveLibs(settings);
			settings.addLFlags(settings.libs.map!(l => "-l"~l)().array());
		}

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

		if (!(fields & BuildSetting.lflags)) {
			settings.addDFlags(settings.lflags.map!(s => "-L="~s)().array());
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
			if (f.startsWith("-d-version=")) settings.addVersions(f[11 .. $]);
			else if (f.startsWith("-d-debug=")) settings.addDebugVersions(f[9 .. $]);
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
				assert(false, "No LDC static libraries supported");
			case TargetType.dynamicLibrary:
				assert(false, "No LDC dynamic libraries supported");
		}

		auto tpath = Path(settings.targetPath) ~ getTargetFileName(settings, platform);
		settings.addDFlags("-of"~tpath.toNativeString());
	}

	void invoke(in BuildSettings settings, in BuildPlatform platform, void delegate(int, string) output_callback)
	{
		auto res_file = getTempDir() ~ ("dub-build-"~uniform(0, uint.max).to!string~"-.rsp");
		std.file.write(res_file.toNativeString(), join(cast(string[])settings.dflags, "\n"));
		scope (exit) remove(res_file.toNativeString());

		logDiagnostic("%s %s", platform.compilerBinary, join(cast(string[])settings.dflags, " "));
		invokeTool([platform.compilerBinary, "@"~res_file.toNativeString()], output_callback);
	}

	void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects, void delegate(int, string) output_callback)
	{
		assert(false, "Separate linking not implemented for GDC");
	}
}
