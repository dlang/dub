/**
	Utility functionality for compiler class implementations.

	Copyright: © 2013-2016 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.utils;

import dub.compilers.buildsettings;
import dub.platform : BuildPlatform, archCheck, compilerCheck, platformCheck;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.inet.path;
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
			return platform.platform.canFind("windows");
		case ".a", ".o", ".so", ".dylib":
			return !platform.platform.canFind("windows");
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
	Determines if a specific file name has the extension related to dynamic libraries.

	This includes dynamic libraries and for Windows pdb, export and import library files.
*/
bool isDynamicLibraryFile(const scope ref BuildPlatform platform, string f)
{
	import std.path;
	switch (extension(f)) {
		default:
			return false;
		case ".lib", ".pdb", ".dll", ".exp":
			return platform.platform.canFind("windows");
		case ".so", ".dylib":
			return !platform.platform.canFind("windows");
	}
}

unittest {
	BuildPlatform p;

	p.platform = ["windows"];
	assert(!isDynamicLibraryFile(p, "test.obj"));
	assert(isDynamicLibraryFile(p, "test.lib"));
	assert(isDynamicLibraryFile(p, "test.dll"));
	assert(isDynamicLibraryFile(p, "test.pdb"));
	assert(!isDynamicLibraryFile(p, "test.res"));
	assert(!isDynamicLibraryFile(p, "test.o"));
	assert(!isDynamicLibraryFile(p, "test.d"));
	assert(!isDynamicLibraryFile(p, "test.dylib"));

	p.platform = ["something else"];
	assert(!isDynamicLibraryFile(p, "test.o"));
	assert(!isDynamicLibraryFile(p, "test.a"));
	assert(isDynamicLibraryFile(p, "test.so"));
	assert(isDynamicLibraryFile(p, "test.dylib"));
	assert(!isDynamicLibraryFile(p, "test.obj"));
	assert(!isDynamicLibraryFile(p, "test.d"));
	assert(!isDynamicLibraryFile(p, "test.lib"));
	assert(!isDynamicLibraryFile(p, "test.dll"));
	assert(!isDynamicLibraryFile(p, "test.pdb"));
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
		if (platform.platform.canFind("windows"))
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
	be specified as build options (`BuildOptions`) or built requirements
	(`BuildRequirements`). This function will output warning messages to
	assist the user in making the best choice.
*/
void warnOnSpecialCompilerFlags(string[] compiler_flags, BuildOptions options, string package_name, string config_name)
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

/**
	Turn a DMD-like version (e.g. 2.082.1) into a SemVer-like version (e.g. 2.82.1).
    The function accepts a dependency operator prefix and some text postfix.
    Prefix and postfix are returned verbatim.
	Params:
		ver	=	version string, possibly with a dependency operator prefix and some
				test postfix.
	Returns:
		A Semver compliant string
*/
package(dub) string dmdLikeVersionToSemverLike(string ver)
{
	import std.algorithm : countUntil, joiner, map, skipOver, splitter;
	import std.array : join, split;
	import std.ascii : isDigit;
	import std.conv : text;
	import std.exception : enforce;
	import std.functional : not;
	import std.range : padRight;

	const start = ver.countUntil!isDigit;
	enforce(start != -1, "Invalid semver: "~ver);
	const prefix = ver[0 .. start];
	ver = ver[start .. $];

	const end = ver.countUntil!(c => !c.isDigit && c != '.');
	const postfix = end == -1 ? null : ver[end .. $];
	auto verStr = ver[0 .. $-postfix.length];

	auto comps = verStr
		.splitter(".")
		.map!((a) { if (a.length > 1) a.skipOver("0"); return a;})
		.padRight("0", 3);

	return text(prefix, comps.joiner("."), postfix);
}

///
unittest {
	assert(dmdLikeVersionToSemverLike("2.082.1") == "2.82.1");
	assert(dmdLikeVersionToSemverLike("2.082.0") == "2.82.0");
	assert(dmdLikeVersionToSemverLike("2.082") == "2.82.0");
	assert(dmdLikeVersionToSemverLike("~>2.082") == "~>2.82.0");
	assert(dmdLikeVersionToSemverLike("~>2.082-beta1") == "~>2.82.0-beta1");
	assert(dmdLikeVersionToSemverLike("2.4.6") == "2.4.6");
	assert(dmdLikeVersionToSemverLike("2.4.6-alpha12") == "2.4.6-alpha12");
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
	import dub.internal.vibecompat.data.json;
	import dub.internal.utils;
	import std.string : format;

	// try to not use phobos in the probe to avoid long import times
	enum probe = q{
		module dub_platform_probe;

		template toString(int v) { enum toString = v.stringof; }
		string stringArray(string[] ary) {
			string res;
			foreach (i, e; ary) {
				if (i)
					res ~= ", ";
				res ~= '"' ~ e ~ '"';
			}
			return res;
		}

		pragma(msg, `%1$s`
			~ '\n' ~ `{`
			~ '\n' ~ `  "compiler": "`~ determineCompiler() ~ `",`
			~ '\n' ~ `  "frontendVersion": ` ~ toString!__VERSION__ ~ `,`
			~ '\n' ~ `  "compilerVendor": "` ~ __VENDOR__ ~ `",`
			~ '\n' ~ `  "platform": [`
			~ '\n' ~ `    ` ~ determinePlatform().stringArray
			~ '\n' ~ `  ],`
			~ '\n' ~ `  "architecture": [`
			~ '\n' ~ `    ` ~ determineArchitecture().stringArray
			~ '\n' ~ `   ],`
			~ '\n' ~ `}`
			~ '\n' ~ `%2$s`);

		string[] determinePlatform() { %3$s }
		string[] determineArchitecture() { %4$s }
		string determineCompiler() { %5$s }

		}.format(probeBeginMark, probeEndMark, platformCheck, archCheck, compilerCheck);

	auto path = getTempFile("dub_platform_probe", ".d");
	auto fil = openFile(path, FileMode.createTrunc);
	fil.write(probe);

	return path;
}

/**
	Processes the JSON output generated by compiling the platform probe file.

	See_Also: `generatePlatformProbeFile`.
*/
BuildPlatform readPlatformJsonProbe(string output)
{
	import std.algorithm : map;
	import std.array : array;
	import std.exception : enforce;
	import std.string;

	// work around possible additional output of the compiler
	auto idx1 = output.indexOf(probeBeginMark);
	auto idx2 = output.lastIndexOf(probeEndMark);
	enforce(idx1 >= 0 && idx1 < idx2,
		"Unexpected platform information output - does not contain a JSON object.");
	output = output[idx1+probeBeginMark.length .. idx2];

	import dub.internal.vibecompat.data.json;
	auto json = parseJsonString(output);

	BuildPlatform build_platform;
	build_platform.platform = json["platform"].get!(Json[]).map!(e => e.get!string()).array();
	build_platform.architecture = json["architecture"].get!(Json[]).map!(e => e.get!string()).array();
	build_platform.compiler = json["compiler"].get!string;
	build_platform.frontendVersion = json["frontendVersion"].get!int;
	return build_platform;
}
