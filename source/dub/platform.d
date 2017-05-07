/**
	Build platform identification and speficiation matching.

	This module is useful for determining the build platform for a certain
	machine and compiler invocation. Example applications include classifying
	CI slave machines.

	It also contains means to match build platforms against a platform
	specification string as used in package reciptes.

	Copyright: © 2012-2016 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.platform;

import std.array;


/** Determines the full build platform used for the current build.

	Note that the `BuildPlatform.compilerBinary` field will be left empty.

	See_Also: `determinePlatform`, `determineArchitecture`, `determineCompiler`
*/
BuildPlatform determineBuildPlatform()
{
	BuildPlatform ret;
	ret.platform = determinePlatform();
	ret.architecture = determineArchitecture();
	ret.compiler = determineCompiler();
	ret.frontendVersion = __VERSION__;
	return ret;
}


/** Returns a list of platform identifiers that apply to the current
	build.

	Example results are `["windows"]` or `["posix", "osx"]`. The identifiers
	correspond to the compiler defined version constants built into the
	language, except that they are converted to lower case.

	See_Also: `determineBuildPlatform`
*/
string[] determinePlatform()
{
	auto ret = appender!(string[])();
	version(Windows) ret.put("windows");
	version(linux) ret.put("linux");
	version(Posix) ret.put("posix");
	version(OSX) ret.put("osx");
	version(FreeBSD) ret.put("freebsd");
	version(OpenBSD) ret.put("openbsd");
	version(NetBSD) ret.put("netbsd");
	version(DragonFlyBSD) ret.put("dragonflybsd");
	version(BSD) ret.put("bsd");
	version(Solaris) ret.put("solaris");
	version(AIX) ret.put("aix");
	version(Haiku) ret.put("haiku");
	version(SkyOS) ret.put("skyos");
	version(SysV3) ret.put("sysv3");
	version(SysV4) ret.put("sysv4");
	version(Hurd) ret.put("hurd");
	version(Android) ret.put("android");
	version(Cygwin) ret.put("cygwin");
	version(MinGW) ret.put("mingw");
	return ret.data;
}

/** Returns a list of architecture identifiers that apply to the current
	build.

	Example results are `["x86_64"]` or `["arm", "arm_softfloat"]`. The
	identifiers correspond to the compiler defined version constants built into
	the language, except that they are converted to lower case.

	See_Also: `determineBuildPlatform`
*/
string[] determineArchitecture()
{
	auto ret = appender!(string[])();
	version(X86) ret.put("x86");
	version(X86_64) ret.put("x86_64");
	version(ARM) ret.put("arm");
	version(ARM_Thumb) ret.put("arm_thumb");
	version(ARM_SoftFloat) ret.put("arm_softfloat");
	version(ARM_HardFloat) ret.put("arm_hardfloat");
	version(ARM64) ret.put("arm64");
	version(PPC) ret.put("ppc");
	version(PPC_SoftFP) ret.put("ppc_softfp");
	version(PPC_HardFP) ret.put("ppc_hardfp");
	version(PPC64) ret.put("ppc64");
	version(IA64) ret.put("ia64");
	version(MIPS) ret.put("mips");
	version(MIPS32) ret.put("mips32");
	version(MIPS64) ret.put("mips64");
	version(MIPS_O32) ret.put("mips_o32");
	version(MIPS_N32) ret.put("mips_n32");
	version(MIPS_O64) ret.put("mips_o64");
	version(MIPS_N64) ret.put("mips_n64");
	version(MIPS_EABI) ret.put("mips_eabi");
	version(MIPS_NoFloat) ret.put("mips_nofloat");
	version(MIPS_SoftFloat) ret.put("mips_softfloat");
	version(MIPS_HardFloat) ret.put("mips_hardfloat");
	version(SPARC) ret.put("sparc");
	version(SPARC_V8Plus) ret.put("sparc_v8plus");
	version(SPARC_SoftFP) ret.put("sparc_softfp");
	version(SPARC_HardFP) ret.put("sparc_hardfp");
	version(SPARC64) ret.put("sparc64");
	version(S390) ret.put("s390");
	version(S390X) ret.put("s390x");
	version(HPPA) ret.put("hppa");
	version(HPPA64) ret.put("hppa64");
	version(SH) ret.put("sh");
	version(SH64) ret.put("sh64");
	version(Alpha) ret.put("alpha");
	version(Alpha_SoftFP) ret.put("alpha_softfp");
	version(Alpha_HardFP) ret.put("alpha_hardfp");
	return ret.data;
}

/** Determines the canonical compiler name used for the current build.

	The possible values currently are "dmd", "gdc", "ldc2" or "sdc". If an
	unknown compiler is used, this function will return an empty string.

	See_Also: `determineBuildPlatform`
*/
string determineCompiler()
{
	version(DigitalMars) return "dmd";
	else version(GNU) return "gdc";
	else version(LDC) return "ldc2";
	else version(SDC) return "sdc";
	else return null;
}

/** Matches a platform specification string against a build platform.

	Specifications are build upon the following scheme, where each component
	is optional (indicated by []), but the order is obligatory:
	"[-platform][-architecture][-compiler]"

	So the following strings are valid specifications: `"-windows-x86-dmd"`,
	`"-dmd"`, `"-arm"`, `"-arm-dmd"`, `"-windows-dmd"`

	Params:
		platform = The build platform to match agains the platform specification
	    specification = The specification being matched. It must either be an
	    	empty string or start with a dash.

	Returns:
	    `true` if the given specification matches the build platform, `false`
	    otherwise. Using an empty string as the platform specification will
	    always result in a match.
*/
bool matchesSpecification(in BuildPlatform platform, const(char)[] specification)
{
	import std.string : format;
	import std.algorithm : canFind, splitter;
	import std.exception : enforce;

	if (specification.empty) return true;
	if (platform == BuildPlatform.any) return true;

	// TODO: support new target triple format

	auto splitted = specification.splitter('-');
	assert(!splitted.empty, "No valid platform specification! The leading hyphen is required!");
	splitted.popFront(); // Drop leading empty match.
	enforce(!splitted.empty, format("Platform specification, if present, must not be empty: \"%s\"", specification));

	if (platform.platform.canFind(splitted.front)) {
		splitted.popFront();
		if (splitted.empty)
			return true;
	}
	if (platform.architecture.canFind(splitted.front)) {
		splitted.popFront();
		if (splitted.empty)
			return true;
	}
	if (platform.compiler == splitted.front) {
		splitted.popFront();
		enforce(splitted.empty, "No valid specification! The compiler has to be the last element: " ~ specification);
		return true;
	}
	return false;
}

///
unittest {
	auto platform=BuildPlatform(["posix", "linux"], ["x86_64"], "dmd");
	assert(platform.matchesSpecification(""));
	assert(platform.matchesSpecification("-posix"));
	assert(platform.matchesSpecification("-linux"));
	assert(platform.matchesSpecification("-linux-dmd"));
	assert(platform.matchesSpecification("-linux-x86_64-dmd"));
	assert(platform.matchesSpecification("-x86_64"));
	assert(!platform.matchesSpecification("-windows"));
	assert(!platform.matchesSpecification("-ldc"));
	assert(!platform.matchesSpecification("-windows-dmd"));
}

TargetTriple parseArchitectureOverride(string arch)
{
	switch (arch) {
		default: break;
		case "x86": return TargetTriple("i386");
		case "x86_64": return TargetTriple("x86_64");
	}

	// TODO: parse target triple
	assert(false);
}

struct TargetTriple {
	string architecture;
	string subArchitecture;
	string os;
	string vendor;
	string abi;

	string toString()
	const {
		// TODO: return in LDC/GDC target triple format
		assert(false);
	}
}

/// Represents a platform a package can be build upon.
struct BuildPlatform {
	/// Special constant used to denote matching any build platform.
	enum any = BuildPlatform(null, null, null, null, -1);

	/// Platform identifiers, e.g. ["posix", "windows"]
	string[] platform;
	/// CPU architecture identifiers, e.g. ["x86", "x86_64"]
	string[] architecture;
	/// LLVM/GCC compatible target triple
	TargetTriple targetTriple;
	/// Canonical compiler name e.g. "dmd"
	string compiler;
	/// Compiler binary name e.g. "ldmd2"
	string compilerBinary;
	/// Compiled frontend version (e.g. `2067` for frontend versions 2.067.x)
	int frontendVersion;
}
