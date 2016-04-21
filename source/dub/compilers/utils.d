/**
	Utility functionality for compiler class implementations.

	Copyright: © 2013-2016 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.utils;

import dub.compilers.buildsettings;
import dub.platform;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.inet.path;
import std.algorithm : canFind;


/**
	Given a set of build settings and a target platform, determines the target
	binary file name.

	The returned string contains the file name, as well as the platform
	specific file extension. The directory is not included.
*/
string getTargetFileName(in BuildSettings settings, in BuildPlatform platform)
{
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
			if (platform.platform.canFind("windows") && platform.compiler == "dmd")
				return settings.targetName ~ ".lib";
			else return "lib" ~ settings.targetName ~ ".a";
		case TargetType.dynamicLibrary:
			if( platform.platform.canFind("windows") )
				return settings.targetName ~ ".dll";
			else return "lib" ~ settings.targetName ~ ".so";
		case TargetType.object:
			if (platform.platform.canFind("windows"))
				return settings.targetName ~ ".obj";
			else return settings.targetName ~ ".o";
	}
}


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
bool isLinkerFile(string f)
{
	import std.path;
	switch (extension(f)) {
		default:
			return false;
		version (Windows) {
			case ".lib", ".obj", ".res", ".def":
				return true;
		} else {
			case ".a", ".o", ".so", ".dylib":
				return true;
		}
	}
}

unittest {
	version (Windows) {
		assert(isLinkerFile("test.obj"));
		assert(isLinkerFile("test.lib"));
		assert(isLinkerFile("test.res"));
		assert(!isLinkerFile("test.o"));
		assert(!isLinkerFile("test.d"));
	} else {
		assert(isLinkerFile("test.o"));
		assert(isLinkerFile("test.a"));
		assert(isLinkerFile("test.so"));
		assert(isLinkerFile("test.dylib"));
		assert(!isLinkerFile("test.obj"));
		assert(!isLinkerFile("test.d"));
	}
}


/**
	Replaces each referenced import library by the appropriate linker flags.

	This function tries to invoke "pkg-config" if possible and falls back to
	direct flag translation if that fails.
*/
void resolveLibs(ref BuildSettings settings)
{
	import std.string : format;

	if (settings.libs.length == 0) return;

	if (settings.targetType == TargetType.library || settings.targetType == TargetType.staticLibrary) {
		logDiagnostic("Ignoring all import libraries for static library build.");
		settings.libs = null;
		version(Windows) settings.sourceFiles = settings.sourceFiles.filter!(f => !f.endsWith(".lib")).array;
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

	Certain compiler flags should, instead of using compiler-specfic syntax,
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
		{["-m32", "-m64"], `Use --arch=x86/--arch=x86_64 to specify the target architecture`}
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
	Generate a file that will give, at compile time, informations about the compiler (architecture, frontend version...)

	See_Also: `readPlatformProbe`
*/
Path generatePlatformProbeFile()
{
	import dub.internal.vibecompat.core.file;
	import dub.internal.vibecompat.data.json;
	import dub.internal.utils;

	auto path = getTempFile("dub_platform_probe", ".d");

	auto fil = openFile(path, FileMode.createTrunc);
	scope (failure) {
		fil.close();
	}

	// NOTE: This must be kept in sync with the dub.platform module
	fil.write(q{
		module dub_platform_probe;

		template toString(int v) { enum toString = v.stringof; }

		pragma(msg, `{`);
		pragma(msg,`  "compiler": "`~ determineCompiler() ~ `",`);
		pragma(msg, `  "frontendVersion": ` ~ toString!__VERSION__ ~ `,`);
		pragma(msg, `  "compilerVendor": "` ~ __VENDOR__ ~ `",`);
		pragma(msg, `  "platform": [`);
		pragma(msg, `    ` ~ determinePlatform());
		pragma(msg, `  ],`);
		pragma(msg, `  "architecture": [`);
		pragma(msg, `    ` ~ determineArchitecture());
		pragma(msg, `   ],`);
		pragma(msg, `}`);

		string determinePlatform()
		{
			string ret;
			version(Windows) ret ~= `"windows", `;
			version(linux) ret ~= `"linux", `;
			version(Posix) ret ~= `"posix", `;
			version(OSX) ret ~= `"osx", `;
			version(FreeBSD) ret ~= `"freebsd", `;
			version(OpenBSD) ret ~= `"openbsd", `;
			version(NetBSD) ret ~= `"netbsd", `;
			version(DragonFlyBSD) ret ~= `"dragonflybsd", `;
			version(BSD) ret ~= `"bsd", `;
			version(Solaris) ret ~= `"solaris", `;
			version(AIX) ret ~= `"aix", `;
			version(Haiku) ret ~= `"haiku", `;
			version(SkyOS) ret ~= `"skyos", `;
			version(SysV3) ret ~= `"sysv3", `;
			version(SysV4) ret ~= `"sysv4", `;
			version(Hurd) ret ~= `"hurd", `;
			version(Android) ret ~= `"android", `;
			version(Cygwin) ret ~= `"cygwin", `;
			version(MinGW) ret ~= `"mingw", `;
			return ret;
		}

		string determineArchitecture()
		{
			string ret;
			version(X86) ret ~= `"x86", `;
			version(X86_64) ret ~= `"x86_64", `;
			version(ARM) ret ~= `"arm", `;
			version(ARM_Thumb) ret ~= `"arm_thumb", `;
			version(ARM_SoftFloat) ret ~= `"arm_softfloat", `;
			version(ARM_HardFloat) ret ~= `"arm_hardfloat", `;
			version(ARM64) ret ~= `"arm64", `;
			version(PPC) ret ~= `"ppc", `;
			version(PPC_SoftFP) ret ~= `"ppc_softfp", `;
			version(PPC_HardFP) ret ~= `"ppc_hardfp", `;
			version(PPC64) ret ~= `"ppc64", `;
			version(IA64) ret ~= `"ia64", `;
			version(MIPS) ret ~= `"mips", `;
			version(MIPS32) ret ~= `"mips32", `;
			version(MIPS64) ret ~= `"mips64", `;
			version(MIPS_O32) ret ~= `"mips_o32", `;
			version(MIPS_N32) ret ~= `"mips_n32", `;
			version(MIPS_O64) ret ~= `"mips_o64", `;
			version(MIPS_N64) ret ~= `"mips_n64", `;
			version(MIPS_EABI) ret ~= `"mips_eabi", `;
			version(MIPS_NoFloat) ret ~= `"mips_nofloat", `;
			version(MIPS_SoftFloat) ret ~= `"mips_softfloat", `;
			version(MIPS_HardFloat) ret ~= `"mips_hardfloat", `;
			version(SPARC) ret ~= `"sparc", `;
			version(SPARC_V8Plus) ret ~= `"sparc_v8plus", `;
			version(SPARC_SoftFP) ret ~= `"sparc_softfp", `;
			version(SPARC_HardFP) ret ~= `"sparc_hardfp", `;
			version(SPARC64) ret ~= `"sparc64", `;
			version(S390) ret ~= `"s390", `;
			version(S390X) ret ~= `"s390x", `;
			version(HPPA) ret ~= `"hppa", `;
			version(HPPA64) ret ~= `"hppa64", `;
			version(SH) ret ~= `"sh", `;
			version(SH64) ret ~= `"sh64", `;
			version(Alpha) ret ~= `"alpha", `;
			version(Alpha_SoftFP) ret ~= `"alpha_softfp", `;
			version(Alpha_HardFP) ret ~= `"alpha_hardfp", `;
			return ret;
		}

		string determineCompiler()
		{
			version(DigitalMars) return "dmd";
			else version(GNU) return "gdc";
			else version(LDC) return "ldc";
			else version(SDC) return "sdc";
			else return null;
		}
	});

	fil.close();

	return path;
}

/**
	Processes the output generated by compiling the platform probe file.

	See_Also: `generatePlatformProbeFile`.
*/
BuildPlatform readPlatformProbe(string output)
{
	import std.algorithm : map;
	import std.array : array;
	import std.exception : enforce;
	import std.string;

	// work around possible additional output of the compiler
	auto idx1 = output.indexOf("{");
	auto idx2 = output.lastIndexOf("}");
	enforce(idx1 >= 0 && idx1 < idx2,
		"Unexpected platform information output - does not contain a JSON object.");
	output = output[idx1 .. idx2+1];

	import dub.internal.vibecompat.data.json;
	auto json = parseJsonString(output);

	BuildPlatform build_platform;
	build_platform.platform = json.platform.get!(Json[]).map!(e => e.get!string()).array();
	build_platform.architecture = json.architecture.get!(Json[]).map!(e => e.get!string()).array();
	build_platform.compiler = json.compiler.get!string;
	build_platform.frontendVersion = json.frontendVersion.get!int;
	return build_platform;
}
