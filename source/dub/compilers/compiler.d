/**
	Compiler settings and abstraction.

	Copyright: © 2013-2014 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.compiler;

public import dub.compilers.buildsettings;

import dub.compilers.dmd;
import dub.compilers.gdc;
import dub.compilers.ldc;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.path;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.process;


static this()
{
	registerCompiler(new DmdCompiler);
	registerCompiler(new GdcCompiler);
	registerCompiler(new LdcCompiler);
}

Compiler getCompiler(string name)
{
	foreach (c; s_compilers)
		if (c.name == name)
			return c;

	// try to match names like gdmd or gdc-2.61
	if (name.canFind("dmd")) return getCompiler("dmd");
	if (name.canFind("gdc")) return getCompiler("gdc");
	if (name.canFind("ldc")) return getCompiler("ldc");

	throw new Exception("Unknown compiler: "~name);
}

string defaultCompiler()
{
	static string name;
	if (!name.length) name = findCompiler();
	return name;
}

private string findCompiler()
{
	import std.process : env=environment;
	import dub.version_ : initialCompilerBinary;
	version (Windows) enum sep = ";", exe = ".exe";
	version (Posix) enum sep = ":", exe = "";

	auto def = Path(initialCompilerBinary);
	if (def.absolute && existsFile(def))
		return initialCompilerBinary;

	auto compilers = ["dmd", "gdc", "gdmd", "ldc2", "ldmd2"];
	if (!def.absolute)
		compilers = initialCompilerBinary ~ compilers;

	auto paths = env.get("PATH", "").splitter(sep).map!Path;
	auto res = compilers.find!(bin => paths.canFind!(p => existsFile(p ~ (bin~exe))));
	return res.empty ? initialCompilerBinary : res.front;
}

void registerCompiler(Compiler c)
{
	s_compilers ~= c;
}

void warnOnSpecialCompilerFlags(string[] compiler_flags, BuildOptions options, string package_name, string config_name)
{
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
		{["-cov"], "Call dub with --build=cov or --build=unittest-cox"},
		{["-profile"], "Call dub with --build=profile"},
		{["-version="], `Use "versions" to specify version constants in a compiler independent way`},
		{["-debug="], `Use "debugVersions" to specify version constants in a compiler independent way`},
		{["-I"], `Use "importPaths" to specify import paths in a compiler independent way`},
		{["-J"], `Use "stringImportPaths" to specify import paths in a compiler independent way`},
		{["-m32", "-m64"], `Use --arch=x86/--arch=x86_64 to specify the target architecture`}
	];

	struct SpecialOption {
		BuildOptions[] flags;
		string alternative;
	}
	static immutable SpecialOption[] s_specialOptions = [
		{[BuildOptions.debugMode], "Call DUB with --build=debug"},
		{[BuildOptions.releaseMode], "Call DUB with --build=release"},
		{[BuildOptions.coverage], "Call DUB with --build=cov or --build=unittest-cov"},
		{[BuildOptions.debugInfo], "Call DUB with --build=debug"},
		{[BuildOptions.inline], "Call DUB with --build=release"},
		{[BuildOptions.noBoundsCheck], "Call DUB with --build=release-nobounds"},
		{[BuildOptions.optimize], "Call DUB with --build=release"},
		{[BuildOptions.profile], "Call DUB with --build=profile"},
		{[BuildOptions.unittests], "Call DUB with --build=unittest"},
		{[BuildOptions.warnings, BuildOptions.warningsAsErrors], "Use \"buildRequirements\" to control the warning level"},
		{[BuildOptions.ignoreDeprecations, BuildOptions.deprecationWarnings, BuildOptions.deprecationErrors], "Use \"buildRequirements\" to control the deprecation warning level"},
		{[BuildOptions.property], "This flag is deprecated and has no effect"}
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
	Alters the build options to comply with the specified build requirements.
*/
void enforceBuildRequirements(ref BuildSettings settings)
{
	settings.addOptions(BuildOptions.warningsAsErrors);
	if (settings.requirements & BuildRequirements.allowWarnings) { settings.options &= ~BuildOptions.warningsAsErrors; settings.options |= BuildOptions.warnings; }
	if (settings.requirements & BuildRequirements.silenceWarnings) settings.options &= ~(BuildOptions.warningsAsErrors|BuildOptions.warnings);
	if (settings.requirements & BuildRequirements.disallowDeprecations) { settings.options &= ~(BuildOptions.ignoreDeprecations|BuildOptions.deprecationWarnings); settings.options |= BuildOptions.deprecationErrors; }
	if (settings.requirements & BuildRequirements.silenceDeprecations) { settings.options &= ~(BuildOptions.deprecationErrors|BuildOptions.deprecationWarnings); settings.options |= BuildOptions.ignoreDeprecations; }
	if (settings.requirements & BuildRequirements.disallowInlining) settings.options &= ~BuildOptions.inline;
	if (settings.requirements & BuildRequirements.disallowOptimization) settings.options &= ~BuildOptions.optimize;
	if (settings.requirements & BuildRequirements.requireBoundsCheck) settings.options &= ~BuildOptions.noBoundsCheck;
	if (settings.requirements & BuildRequirements.requireContracts) settings.options &= ~BuildOptions.releaseMode;
	if (settings.requirements & BuildRequirements.relaxProperties) settings.options &= ~BuildOptions.property;
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
		try {
			enum pkgconfig_bin = "pkg-config";
			string[] pkgconfig_libs;
			foreach (lib; settings.libs)
				if (execute([pkgconfig_bin, "--exists", "lib"~lib]).status == 0)
					pkgconfig_libs ~= lib;

			logDiagnostic("Using pkg-config to resolve library flags for %s.", pkgconfig_libs.map!(l => "lib"~l).array.join(", "));

			if (pkgconfig_libs.length) {
				auto libflags = execute([pkgconfig_bin, "--libs"] ~ pkgconfig_libs.map!(l => "lib"~l)().array());
				enforce(libflags.status == 0, format("pkg-config exited with error code %s: %s", libflags.status, libflags.output));
				foreach (f; libflags.output.split()) {
					if (f.startsWith("-Wl,")) settings.addLFlags(f[4 .. $].split(","));
					else settings.addLFlags(f);
				}
				settings.libs = settings.libs.filter!(l => !pkgconfig_libs.canFind(l)).array;
			}
			if (settings.libs.length) logDiagnostic("Using direct -l... flags for %s.", settings.libs.array.join(", "));
		} catch (Exception e) {
			logDiagnostic("pkg-config failed: %s", e.msg);
			logDiagnostic("Falling back to direct -l... flags.");
		}
	}
}


interface Compiler {
	@property string name() const;

	BuildPlatform determinePlatform(ref BuildSettings settings, string compiler_binary, string arch_override = null);

	/// Replaces high level fields with low level fields and converts
	/// dmd flags to compiler-specific flags
	void prepareBuildSettings(ref BuildSettings settings, BuildSetting supported_fields = BuildSetting.all) const;

	/// Removes any dflags that match one of the BuildOptions values and populates the BuildSettings.options field.
	void extractBuildOptions(ref BuildSettings settings) const;

	/// Adds the appropriate flag to set a target path
	void setTarget(ref BuildSettings settings, in BuildPlatform platform, string targetPath = null) const;

	/// Invokes the compiler using the given flags
	void invoke(in BuildSettings settings, in BuildPlatform platform, void delegate(int, string) output_callback);

	/// Invokes the underlying linker directly
	void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects, void delegate(int, string) output_callback);

	protected final void invokeTool(string[] args, void delegate(int, string) output_callback)
	{
		import std.string;

		int status;
		if (output_callback) {
			auto result = executeShell(escapeShellCommand(args));
			output_callback(result.status, result.output);
			status = result.status;
		} else {
			auto compiler_pid = spawnShell(escapeShellCommand(args));
			status = compiler_pid.wait();
		}

		version (Posix) if (status == -9) {
			throw new Exception(format("%s failed with exit code %s. This may indicate that the process has run out of memory."),
				args[0], status);
		}
		enforce(status == 0, format("%s failed with exit code %s.", args[0], status));
	}
}


/// Represents a platform a package can be build upon.
struct BuildPlatform {
	/// e.g. ["posix", "windows"]
	string[] platform;
	/// e.g. ["x86", "x86_64"]
	string[] architecture;
	/// Canonical compiler name e.g. "dmd"
	string compiler;
	/// Compiler binary name e.g. "ldmd2"
	string compilerBinary;
	/// Compiled frontend version (e.g. 2065)
	int frontendVersion;

	enum any = BuildPlatform(null, null, null, null, -1);

	/// Build platforms can be specified via a string specification.
	///
	/// Specifications are build upon the following scheme, where each component
	/// is optional (indicated by []), but the order is obligatory.
	/// "[-platform][-architecture][-compiler]"
	///
	/// So the following strings are valid specifications:
	/// "-windows-x86-dmd"
	/// "-dmd"
	/// "-arm"
	/// "-arm-dmd"
	/// "-windows-dmd"
	///
	/// Params:
	///     specification = The specification being matched. It must be the empty string or start with a dash.
	///
	/// Returns:
	///     true if the given specification matches this BuildPlatform, false otherwise. (The empty string matches)
	///
	bool matchesSpecification(const(char)[] specification)
	const {
		if (specification.empty) return true;
		if (this == any) return true;

		auto splitted=specification.splitter('-');
		assert(!splitted.empty, "No valid platform specification! The leading hyphen is required!");
		splitted.popFront(); // Drop leading empty match.
		enforce(!splitted.empty, "Platform specification if present, must not be empty!");
		if (platform.canFind(splitted.front)) {
			splitted.popFront();
			if(splitted.empty)
				return true;
		}
		if (architecture.canFind(splitted.front)) {
			splitted.popFront();
			if(splitted.empty)
				return true;
		}
		if (compiler == splitted.front) {
			splitted.popFront();
			enforce(splitted.empty, "No valid specification! The compiler has to be the last element!");
			return true;
		}
		return false;
	}
	unittest {
		auto platform=BuildPlatform(["posix", "linux"], ["x86_64"], "dmd");
		assert(platform.matchesSpecification("-posix"));
		assert(platform.matchesSpecification("-linux"));
		assert(platform.matchesSpecification("-linux-dmd"));
		assert(platform.matchesSpecification("-linux-x86_64-dmd"));
		assert(platform.matchesSpecification("-x86_64"));
		assert(!platform.matchesSpecification("-windows"));
		assert(!platform.matchesSpecification("-ldc"));
		assert(!platform.matchesSpecification("-windows-dmd"));
	}
}


string getTargetFileName(in BuildSettings settings, in BuildPlatform platform)
{
	assert(settings.targetName.length > 0, "No target name set.");
	final switch (settings.targetType) {
		case TargetType.autodetect: assert(false, "Configurations must have a concrete target type.");
		case TargetType.none: return null;
		case TargetType.sourceLibrary: return null;
		case TargetType.executable:
			if( platform.platform.canFind("windows") )
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
	}
}


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

/// Generate a file that will give, at compile time, informations about the compiler (architecture, frontend version...)
Path generatePlatformProbeFile()
{
	import dub.internal.vibecompat.core.file;
	import dub.internal.vibecompat.data.json;
	import dub.internal.utils;

	auto path = getTempFile("dub_platform_probe", ".d");

	auto fil = openFile(path, FileMode.CreateTrunc);
	scope (failure) {
		fil.close();
	}

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

BuildPlatform readPlatformProbe(string output)
{
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

private {
	Compiler[] s_compilers;
}
