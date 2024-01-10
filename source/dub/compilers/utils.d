/**
	Utility functionality for compiler class implementations.

	Copyright: © 2013-2016 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.utils;

import dub.compilers.buildsettings;
import dub.platform : BuildPlatform, archCheck, compilerCheckPragmas, platformCheck, pragmaGen;
import dub.internal.vibecompat.inet.path;
import dub.internal.logging;

import std.algorithm : canFind, endsWith, filter;

/**
	Alters the build options to comply with the specified build requirements.

	And enabled options that do not comply will get disabled.
*/
void enforceBuildRequirements(ref BuildSettings settings)
{
	settings.addOptions(BuildOption.warningsAsErrors);
	if (settings.requirements & BuildRequirement.allowWarnings) { settings.options &= ~BuildOption.warningsAsErrors; settings.options |= BuildOption.warnings; }
	if (settings.requirements & BuildRequirement.silenceWarnings) settings.options &= ~(BuildOption.warningsAsErrors|BuildOption.warnings);
	if (settings.requirements & BuildRequirement.disallowDeprecations) { settings.options &= ~(BuildOption.ignoreDeprecations|BuildOption.deprecationWarnings); settings.options |= BuildOption.deprecationErrors; }
	if (settings.requirements & BuildRequirement.silenceDeprecations) { settings.options &= ~(BuildOption.deprecationErrors|BuildOption.deprecationWarnings); settings.options |= BuildOption.ignoreDeprecations; }
	if (settings.requirements & BuildRequirement.disallowInlining) settings.options &= ~BuildOption.inline;
	if (settings.requirements & BuildRequirement.disallowOptimization) settings.options &= ~BuildOption.optimize;
	if (settings.requirements & BuildRequirement.requireBoundsCheck) settings.options &= ~BuildOption.noBoundsCheck;
	if (settings.requirements & BuildRequirement.requireContracts) settings.options &= ~BuildOption.releaseMode;
	if (settings.requirements & BuildRequirement.relaxProperties) settings.options &= ~BuildOption.property;
}


/**
	Determines if a specific file name has the extension of a linker file.

	Linker files include static/dynamic libraries, resource files, object files
	and DLL definition files.
*/
bool isLinkerFile(const scope ref BuildPlatform platform, string f)
{
	import std.path;
	switch (extension(f)) {
		default:
			return false;
		case ".lib", ".obj", ".res", ".def":
			return platform.isWindows();
		case ".a", ".o", ".so", ".dylib":
			return !platform.isWindows();
	}
}

unittest {
	BuildPlatform p;

	p.platform = ["windows"];
	assert(isLinkerFile(p, "test.obj"));
	assert(isLinkerFile(p, "test.lib"));
	assert(isLinkerFile(p, "test.res"));
	assert(!isLinkerFile(p, "test.o"));
	assert(!isLinkerFile(p, "test.d"));

	p.platform = ["something else"];
	assert(isLinkerFile(p, "test.o"));
	assert(isLinkerFile(p, "test.a"));
	assert(isLinkerFile(p, "test.so"));
	assert(isLinkerFile(p, "test.dylib"));
	assert(!isLinkerFile(p, "test.obj"));
	assert(!isLinkerFile(p, "test.d"));
}


/**
	Adds a default DT_SONAME (ELF) / 'install name' (Mach-O) when linking a dynamic library.
	This makes dependees reference their dynamic-lib deps by filename only (DT_NEEDED etc.)
	instead of by the path used in the dependee linker cmdline, and enables loading the
	deps from the dependee's output directory - either by setting the LD_LIBRARY_PATH
	environment variable, or baking an rpath into the executable.
*/
package void addDynamicLibName(ref BuildSettings settings, in BuildPlatform platform, string fileName)
{
	if (!platform.isWindows()) {
		// *pre*pend to allow the user to override it
		if (platform.platform.canFind("darwin"))
			settings.prependLFlags("-install_name", "@rpath/" ~ fileName);
		else
			settings.prependLFlags("-soname", fileName);
	}
}


/**
	Replaces each referenced import library by the appropriate linker flags.

	This function tries to invoke "pkg-config" if possible and falls back to
	direct flag translation if that fails.
*/
void resolveLibs(ref BuildSettings settings, const scope ref BuildPlatform platform)
{
	import std.string : format;
	import std.array : array;

	if (settings.libs.length == 0) return;

	if (settings.targetType == TargetType.library || settings.targetType == TargetType.staticLibrary) {
		logDiagnostic("Ignoring all import libraries for static library build.");
		settings.libs = null;
		if (platform.isWindows())
			settings.sourceFiles = settings.sourceFiles.filter!(f => !f.endsWith(".lib")).array;
	}

	version (Posix) {
		import std.algorithm : any, map, partition, startsWith;
		import std.array : array, join, split;
		import std.exception : enforce;
		import std.process : execute;

		try {
			enum pkgconfig_bin = "pkg-config";

			bool exists(string lib) {
				return execute([pkgconfig_bin, "--exists", lib]).status == 0;
			}

			auto pkgconfig_libs = settings.libs.partition!(l => !exists(l));
			pkgconfig_libs ~= settings.libs[0 .. $ - pkgconfig_libs.length]
				.partition!(l => !exists("lib"~l)).map!(l => "lib"~l).array;
			settings.libs = settings.libs[0 .. $ - pkgconfig_libs.length];

			if (pkgconfig_libs.length) {
				logDiagnostic("Using pkg-config to resolve library flags for %s.", pkgconfig_libs.join(", "));
				auto libflags = execute([pkgconfig_bin, "--libs"] ~ pkgconfig_libs);
				enforce(libflags.status == 0, format("pkg-config exited with error code %s: %s", libflags.status, libflags.output));
				foreach (f; libflags.output.split()) {
					if (f.startsWith("-L-L")) {
						settings.addLFlags(f[2 .. $]);
					} else if (f.startsWith("-defaultlib")) {
						settings.addDFlags(f);
					} else if (f.startsWith("-L-defaultlib")) {
						settings.addDFlags(f[2 .. $]);
					} else if (f.startsWith("-pthread")) {
						settings.addLFlags("-lpthread");
					} else if (f.startsWith("-L-l")) {
						settings.addLFlags(f[2 .. $].split(","));
					} else if (f.startsWith("-Wl,")) settings.addLFlags(f[4 .. $].split(","));
					else settings.addLFlags(f);
				}
			}
			if (settings.libs.length) logDiagnostic("Using direct -l... flags for %s.", settings.libs.array.join(", "));
		} catch (Exception e) {
			logDiagnostic("pkg-config failed: %s", e.msg);
			logDiagnostic("Falling back to direct -l... flags.");
		}
	}
}


/** Searches the given list of compiler flags for ones that have a generic
	equivalent.

	Certain compiler flags should, instead of using compiler-specific syntax,
	be specified as build options (`BuildOption`) or built requirements
	(`BuildRequirements`). This function will output warning messages to
	assist the user in making the best choice.
*/
void warnOnSpecialCompilerFlags(string[] compiler_flags, Flags!BuildOption options, string package_name, string config_name)
{
	import std.algorithm : any, endsWith, startsWith;
	import std.range : empty;

	struct SpecialFlag {
		string[] flags;
		string alternative;
	}
	static immutable SpecialFlag[] s_specialFlags = [
		{["-c", "-o-"], "Automatically issued by DUB, do not specify in dub.json"},
		{["-w", "-Wall", "-Werr"], `Use "buildRequirements" to control warning behavior`},
		{["-property", "-fproperty"], "Using this flag may break building of dependencies and it will probably be removed from DMD in the future"},
		{["-wi"], `Use the "buildRequirements" field to control warning behavior`},
		{["-d", "-de", "-dw"], `Use the "buildRequirements" field to control deprecation behavior`},
		{["-of"], `Use "targetPath" and "targetName" to customize the output file`},
		{["-debug", "-fdebug", "-g"], "Call dub with --build=debug"},
		{["-release", "-frelease", "-O", "-inline"], "Call dub with --build=release"},
		{["-unittest", "-funittest"], "Call dub with --build=unittest"},
		{["-lib"], `Use {"targetType": "staticLibrary"} or let dub manage this`},
		{["-D"], "Call dub with --build=docs or --build=ddox"},
		{["-X"], "Call dub with --build=ddox"},
		{["-cov"], "Call dub with --build=cov or --build=unittest-cov"},
		{["-cov=ctfe"], "Call dub with --build=cov-ctfe or --build=unittest-cov-ctfe"},
		{["-profile"], "Call dub with --build=profile"},
		{["-version="], `Use "versions" to specify version constants in a compiler independent way`},
		{["-debug="], `Use "debugVersions" to specify version constants in a compiler independent way`},
		{["-I"], `Use "importPaths" to specify import paths in a compiler independent way`},
		{["-J"], `Use "stringImportPaths" to specify import paths in a compiler independent way`},
		{["-m32", "-m64", "-m32mscoff"], `Use --arch=x86/--arch=x86_64/--arch=x86_mscoff to specify the target architecture, e.g. 'dub build --arch=x86_64'`}
	];

	struct SpecialOption {
		BuildOption[] flags;
		string alternative;
	}
	static immutable SpecialOption[] s_specialOptions = [
		{[BuildOption.debugMode], "Call DUB with --build=debug"},
		{[BuildOption.releaseMode], "Call DUB with --build=release"},
		{[BuildOption.coverage], "Call DUB with --build=cov or --build=unittest-cov"},
		{[BuildOption.coverageCTFE], "Call DUB with --build=cov-ctfe or --build=unittest-cov-ctfe"},
		{[BuildOption.debugInfo], "Call DUB with --build=debug"},
		{[BuildOption.inline], "Call DUB with --build=release"},
		{[BuildOption.noBoundsCheck], "Call DUB with --build=release-nobounds"},
		{[BuildOption.optimize], "Call DUB with --build=release"},
		{[BuildOption.profile], "Call DUB with --build=profile"},
		{[BuildOption.unittests], "Call DUB with --build=unittest"},
		{[BuildOption.syntaxOnly], "Call DUB with --build=syntax"},
		{[BuildOption.warnings, BuildOption.warningsAsErrors], "Use \"buildRequirements\" to control the warning level"},
		{[BuildOption.ignoreDeprecations, BuildOption.deprecationWarnings, BuildOption.deprecationErrors], "Use \"buildRequirements\" to control the deprecation warning level"},
		{[BuildOption.property], "This flag is deprecated and has no effect"}
	];

	bool got_preamble = false;
	void outputPreamble()
	{
		if (got_preamble) return;
		got_preamble = true;
		logWarn("");
		if (config_name.empty) logWarn("## Warning for package %s ##", package_name);
		else logWarn("## Warning for package %s, configuration %s ##", package_name, config_name);
		logWarn("");
		logWarn("The following compiler flags have been specified in the package description");
		logWarn("file. They are handled by DUB and direct use in packages is discouraged.");
		logWarn("Alternatively, you can set the DFLAGS environment variable to pass custom flags");
		logWarn("to the compiler, or use one of the suggestions below:");
		logWarn("");
	}

	foreach (f; compiler_flags) {
		foreach (sf; s_specialFlags) {
			if (sf.flags.any!(sff => f == sff || (sff.endsWith("=") && f.startsWith(sff)))) {
				outputPreamble();
				logWarn("%s: %s", f, sf.alternative);
				break;
			}
		}
	}

	foreach (sf; s_specialOptions) {
		foreach (f; sf.flags) {
			if (options & f) {
				outputPreamble();
				logWarn("%s: %s", f, sf.alternative);
				break;
			}
		}
	}

	if (got_preamble) logWarn("");
}

private enum probeBeginMark = "__dub_probe_begin__";
private enum probeEndMark = "__dub_probe_end__";

/**
	Generate a file that will give, at compile time, information about the compiler (architecture, frontend version...)

	See_Also: `readPlatformProbe`
*/
NativePath generatePlatformProbeFile()
{
	import dub.internal.vibecompat.core.file;
	import dub.internal.utils;
	import std.string : format;

	enum moduleInfo = q{
		module object;
		alias string = const(char)[];
	};

	// avoid druntime so that this compiles without a compiler's builtin object.d
	enum probe = q{
		%1$s
		pragma(msg, `%2$s`);
		pragma(msg, `\n`);
		pragma(msg, `compiler`);
		%6$s
		pragma(msg, `\n`);
		pragma(msg, `frontendVersion "`);
		pragma(msg, __VERSION__.stringof);
		pragma(msg, `"\n`);
		pragma(msg, `compilerVendor "`);
		pragma(msg, __VENDOR__);
		pragma(msg, `"\n`);
		pragma(msg, `platform`);
		%4$s
		pragma(msg, `\n`);
		pragma(msg, `architecture `);
		%5$s
		pragma(msg, `\n`);
		pragma(msg, `%3$s`);
	}.format(moduleInfo, probeBeginMark, probeEndMark, pragmaGen(platformCheck), pragmaGen(archCheck), compilerCheckPragmas);

	auto path = getTempFile("dub_platform_probe", ".d");
	writeFile(path, probe);
	return path;
}


/**
	Processes the SDL output generated by compiling the platform probe file.

	See_Also: `generatePlatformProbeFile`.
*/
BuildPlatform readPlatformSDLProbe(string output)
{
	import std.algorithm : map, max, splitter, joiner, count, filter;
	import std.array : array;
	import std.exception : enforce;
	import std.range : front;
	import std.ascii : newline;
	import std.string;
	import dub.internal.sdlang.parser;
	import dub.internal.sdlang.ast;
	import std.conv;

	// work around possible additional output of the compiler
	auto idx1 = output.indexOf(probeBeginMark ~ newline ~ "\\n");
	auto idx2 = output[max(0, idx1) .. $].indexOf(probeEndMark) + idx1;
	enforce(idx1 >= 0 && idx1 < idx2,
		"Unexpected platform information output - does not contain a JSON object.");
	output = output[idx1 + probeBeginMark.length .. idx2].replace(newline, "").replace("\\n", "\n");

	output = output.splitter("\n").filter!((e) => e.length > 0)
		.map!((e) {
			if (e.count("\"") == 0)
			{
				return e ~ ` ""`;
			}
			return e;
		})
		.joiner("\n").array().to!string;

	BuildPlatform build_platform;
	Tag sdl = parseSource(output);

	foreach (n; sdl.all.tags)
	{
		switch (n.name)
		{
		default:
			break;
		case "platform":
			build_platform.platform = n.values.map!(e => e.toString()).array();
			break;
		case "architecture":
			build_platform.architecture = n.values.map!(e => e.toString()).array();
			break;
		case "compiler":
			build_platform.compiler = n.values.front.toString();
			break;
		case "frontendVersion":
			build_platform.frontendVersion = n.values.front.toString()
				.filter!((e) => e >= '0' && e <= '9').array().to!string
				.to!int;
			break;
		}
	}
	return build_platform;
}
