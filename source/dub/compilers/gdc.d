/**
	GDC compiler support.

	Copyright: © 2013-2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.gdc;

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


class GdcCompiler : Compiler {
	private static immutable s_options = [
		tuple(BuildOptions.debugMode, ["-fdebug"]),
		tuple(BuildOptions.releaseMode, ["-frelease"]),
		tuple(BuildOptions.coverage, ["-fprofile-arcs", "-ftest-coverage"]),
		tuple(BuildOptions.debugInfo, ["-g"]),
		tuple(BuildOptions.debugInfoC, ["-g", "-fdebug-c"]),
		//tuple(BuildOptions.alwaysStackFrame, ["-X"]),
		//tuple(BuildOptions.stackStomping, ["-X"]),
		tuple(BuildOptions.inline, ["-finline-functions"]),
		tuple(BuildOptions.noBoundsCheck, ["-fno-bounds-check"]),
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

		auto compiler_result = execute(compiler_binary ~ arch_flags ~ ["-o", (getTempDir()~"dub_platform_probe").toNativeString(), fil.toNativeString()]);
		enforce(compiler_result.status == 0, format("Failed to invoke the compiler %s to determine the build platform: %s",
			compiler_binary, compiler_result.output));
		auto result = execute([(getTempDir()~"dub_platform_probe").toNativeString()]);
		enforce(result.status == 0, format("Failed to invoke the build platform probe: %s",
			result.output));

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

	void prepareBuildSettings(ref BuildSettings settings, BuildSetting fields = BuildSetting.all)
	{
		enforceBuildRequirements(settings);

		if (!(fields & BuildSetting.options)) {
			foreach (t; s_options)
				if (settings.options & t[0])
					settings.addDFlags(t[1]);
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

		if (!(fields & BuildSetting.libs)) {
			resolveLibs(settings);
			settings.addDFlags(settings.libs.map!(l => "-l"~l)().array());
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

	void invoke(in BuildSettings settings, in BuildPlatform platform, void delegate(int, string) output_callback)
	{
		auto res_file = getTempDir() ~ ("dub-build-"~uniform(0, uint.max).to!string~"-.rsp");
		std.file.write(res_file.toNativeString(), join(settings.dflags.map!(s => escape(s)), "\n"));
		scope (exit) remove(res_file.toNativeString());

		logDiagnostic("%s %s", platform.compilerBinary, join(cast(string[])settings.dflags, " "));
		invokeTool([platform.compilerBinary, "@"~res_file.toNativeString()], output_callback);
	}

	void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects, void delegate(int, string) output_callback)
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