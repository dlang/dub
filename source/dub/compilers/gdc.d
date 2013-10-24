/**
	GDC compiler support.

	Copyright: © 2013-2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.gdc;

import dub.compilers.compiler;
import dub.internal.std.process;
import dub.internal.utils;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.inet.path;
import dub.platform;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.random;
import std.typecons;


class GdcCompiler : Compiler {
	private static immutable s_options = [
		tuple(BuildOptions.debug_, ["-fdebug"]),
		tuple(BuildOptions.release, ["-frelease"]),
		tuple(BuildOptions.coverage, ["-fprofile-arcs", "-ftest-coverage"]),
		tuple(BuildOptions.debugInfo, ["-g"]),
		tuple(BuildOptions.debugInfoC, ["-g", "-fdebug-c"]),
		//tuple(BuildOptions.alwaysStackFrame, ["-X"]),
		//tuple(BuildOptions.stackStomping, ["-X"]),
		tuple(BuildOptions.inline, ["-finline-functions"]),
		tuple(BuildOptions.noBoundsChecks, ["-fno-bounds-check"]),
		tuple(BuildOptions.optimize, ["-O3"]),
		//tuple(BuildOptions.profile, ["-X"]),
		tuple(BuildOptions.unittests, ["-funittest"]),
		tuple(BuildOptions.verbose, ["-fd-verbose"]),
		tuple(BuildOptions.ignoreUnknownPragmas, ["-fignore-unknown-pragmas"]),
		tuple(BuildOptions.syntaxOnly, ["-fsyntax-only"]),
		tuple(BuildOptions.warnings, ["-Wall"]),
		tuple(BuildOptions.warningsAsErrors, ["-Werror", "-Wall"]),
		//tuple(BuildOptions.ignoreDeprecations, ["-?"]),
		//tuple(BuildOptions.deprecationWarnings, ["-?"]),
		//tuple(BuildOptions.deprecationErrors, ["-?"]),
		tuple(BuildOptions.property, ["-fproperty"]),
	];

	@property string name() const { return "gdc"; }

	BuildPlatform determinePlatform(ref BuildSettings settings, string compiler_binary, string arch_override)
	{
		// TODO: determine platform by invoking the compiler instead
		BuildPlatform build_platform;
		build_platform.platform = .determinePlatform();
		build_platform.architecture = .determineArchitecture();
		build_platform.compiler = this.name;
		build_platform.compilerBinary = compiler_binary;

		enforce(arch_override.length == 0, "Architecture override not implemented for GDC.");
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
			settings.addDFlags(settings.libs.map!(l => "-l"~l)().array());
		}

		if (!(fields & BuildSetting.versions)) {
			settings.addDFlags(settings.versions.map!(s => "-fversion="~s)().array());
			settings.versions = null;
		}

		if (!(fields & BuildSetting.debugVersions)) {
			settings.addDFlags(settings.debugVersions.map!(s => "-fdebug="~s)().array());
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
			foreach( f; settings.lflags )
				settings.addDFlags(["-Xlinker", f]);
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
			if (f.startsWith("-fversion=")) settings.addVersions(f[10 .. $]);
			else if (f.startsWith("-fdebug=")) settings.addDebugVersions(f[8 .. $]);
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
				settings.addDFlags("-c");
				break;
			case TargetType.dynamicLibrary:
				settings.addDFlags("-shared", "-fPIC");
				break;
		}

		auto tpath = Path(settings.targetPath) ~ getTargetFileName(settings, platform);
		settings.addDFlags("-o", tpath.toNativeString());
	}

	void invoke(in BuildSettings settings, in BuildPlatform platform)
	{
		auto res_file = getTempDir() ~ ("dub-build-"~uniform(0, uint.max).to!string~"-.rsp");
		std.file.write(res_file.toNativeString(), join(settings.dflags.map!(s => escape(s)), "\n"));
		scope (exit) remove(res_file.toNativeString());

		logDiagnostic("%s %s", platform.compilerBinary, join(cast(string[])settings.dflags, " "));
		auto compiler_pid = spawnProcess([platform.compilerBinary, "@"~res_file.toNativeString()]);
		auto result = compiler_pid.wait();
		enforce(result == 0, "GDC compile run failed with exit code "~to!string(result));
	}

	void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects)
	{
		assert(false, "Separate linking not implemented for GDC");
	}
}

private string escape(string str)
{
	auto ret = appender!string();
	foreach (char ch; str) {
		switch (ch) {
			default: ret.put(ch); break;
			case '\\': ret.put(`\\`); break;
			case ' ': ret.put(`\ `); break;
		}
	}
	return ret.data;
}