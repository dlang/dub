/**
	Build platform identification and specification matching.

	This module is useful for determining the build platform for a certain
	machine and compiler invocation. Example applications include classifying
	CI slave machines.

	It also contains means to match build platforms against a platform
	specification string as used in package reciptes.

	Copyright: © 2012-2017 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.platform;

import std.array;

// archCheck, compilerCheck, and platformCheck are used below and in
// generatePlatformProbeFile, so they've been extracted into these strings
// that can be reused.
// Try to not use phobos in the probes to avoid long import times.
/// private
enum string platformCheck = q{
	string[] ret;
	version(Windows) ret ~= "windows";
	version(linux) ret ~= "linux";
	version(Posix) ret ~= "posix";
	version(OSX) ret ~= [ "darwin", "osx" ];
	version(iOS) ret ~= [ "darwin", "ios" ];
	version(TVOS) ret ~= [ "darwin", "tvos" ];
	version(WatchOS) ret ~= [ "darwin", "watchos" ];
	version(FreeBSD) ret ~= "freebsd";
	version(OpenBSD) ret ~= "openbsd";
	version(NetBSD) ret ~= "netbsd";
	version(DragonFlyBSD) ret ~= "dragonflybsd";
	version(BSD) ret ~= "bsd";
	version(Solaris) ret ~= "solaris";
	version(AIX) ret ~= "aix";
	version(Haiku) ret ~= "haiku";
	version(SkyOS) ret ~= "skyos";
	version(SysV3) ret ~= "sysv3";
	version(SysV4) ret ~= "sysv4";
	version(Hurd) ret ~= "hurd";
	version(Android) ret ~= "android";
	version(Cygwin) ret ~= "cygwin";
	version(MinGW) ret ~= "mingw";
	version(PlayStation4) ret ~= "playstation4";
	version(WebAssembly) ret ~= "wasm";
	return ret;
};

/// private
enum string archCheck = q{
	string[] ret;
	version(X86) ret ~= "x86";
	// Hack: see #1535
	// Makes "x86_omf" available as a platform specifier in the package recipe
	version(X86) version(CRuntime_DigitalMars) ret ~= "x86_omf";
	// Hack: see #1059
	// When compiling with --arch=x86_mscoff build_platform.architecture is equal to ["x86"] and canFind below is false.
	// This hack prevents unnesessary warning 'Failed to apply the selected architecture x86_mscoff. Got ["x86"]'.
	// And also makes "x86_mscoff" available as a platform specifier in the package recipe
	version(X86) version(CRuntime_Microsoft) ret ~= "x86_mscoff";
	version(X86_64) ret ~= "x86_64";
	version(ARM) ret ~= "arm";
	version(AArch64) ret ~= "aarch64";
	version(ARM_Thumb) ret ~= "arm_thumb";
	version(ARM_SoftFloat) ret ~= "arm_softfloat";
	version(ARM_HardFloat) ret ~= "arm_hardfloat";
	version(PPC) ret ~= "ppc";
	version(PPC_SoftFP) ret ~= "ppc_softfp";
	version(PPC_HardFP) ret ~= "ppc_hardfp";
	version(PPC64) ret ~= "ppc64";
	version(IA64) ret ~= "ia64";
	version(MIPS) ret ~= "mips";
	version(MIPS32) ret ~= "mips32";
	version(MIPS64) ret ~= "mips64";
	version(MIPS_O32) ret ~= "mips_o32";
	version(MIPS_N32) ret ~= "mips_n32";
	version(MIPS_O64) ret ~= "mips_o64";
	version(MIPS_N64) ret ~= "mips_n64";
	version(MIPS_EABI) ret ~= "mips_eabi";
	version(MIPS_NoFloat) ret ~= "mips_nofloat";
	version(MIPS_SoftFloat) ret ~= "mips_softfloat";
	version(MIPS_HardFloat) ret ~= "mips_hardfloat";
	version(SPARC) ret ~= "sparc";
	version(SPARC_V8Plus) ret ~= "sparc_v8plus";
	version(SPARC_SoftFP) ret ~= "sparc_softfp";
	version(SPARC_HardFP) ret ~= "sparc_hardfp";
	version(SPARC64) ret ~= "sparc64";
	version(S390) ret ~= "s390";
	version(S390X) ret ~= "s390x";
	version(HPPA) ret ~= "hppa";
	version(HPPA64) ret ~= "hppa64";
	version(SH) ret ~= "sh";
	version(SH64) ret ~= "sh64";
	version(Alpha) ret ~= "alpha";
	version(Alpha_SoftFP) ret ~= "alpha_softfp";
	version(Alpha_HardFP) ret ~= "alpha_hardfp";
	return ret;
};

/// private
enum string compilerCheck = q{
	version(DigitalMars) return "dmd";
	else version(GNU) return "gdc";
	else version(LDC) return "ldc";
	else version(SDC) return "sdc";
	else return null;
};

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
	mixin(platformCheck);
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
	mixin(archCheck);
}

/** Determines the canonical compiler name used for the current build.

	The possible values currently are "dmd", "gdc", "ldc" or "sdc". If an
	unknown compiler is used, this function will return an empty string.

	See_Also: `determineBuildPlatform`
*/
string determineCompiler()
{
	mixin(compilerCheck);
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

/// Represents a platform a package can be build upon.
struct BuildPlatform {
	/// Special constant used to denote matching any build platform.
	enum any = BuildPlatform(null, null, null, null, -1);

	/// Platform identifiers, e.g. ["posix", "windows"]
	string[] platform;
	/// CPU architecture identifiers, e.g. ["x86", "x86_64"]
	string[] architecture;
	/// Canonical compiler name e.g. "dmd"
	string compiler;
	/// Compiler binary name e.g. "ldmd2"
	string compilerBinary;
	/// Compiled frontend version (e.g. `2067` for frontend versions 2.067.x)
	int frontendVersion;
	/// Compiler version e.g. "1.11.0"
	string compilerVersion;
	/// Frontend version string from frontendVersion
	/// e.g: 2067 => "2.067"
	string frontendVersionString() const
	{
		import std.format : format;

		const maj = frontendVersion / 1000;
		const min = frontendVersion % 1000;
		return format("%d.%03d", maj, min);
	}
	///
	unittest
	{
		BuildPlatform bp;
		bp.frontendVersion = 2067;
		assert(bp.frontendVersionString == "2.067");
	}
}


