/**
	Determines the strings to identify the current build platform.

	Copyright: © 2012 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.platform;

import std.array;

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

string[] determineArchitecture()
{
	auto ret = appender!(string[])();
	version(X86) ret.put("x86");
	version(X86_64) ret.put("x86_64");
	version(ARM) ret.put("arm");
	version(ARM_Thumb) ret.put("arm_thumb");
	version(ARM_Soft) ret.put("arm_soft");
	version(ARM_SoftFP) ret.put("arm_softfp");
	version(ARM_HardFP) ret.put("arm_hardfp");
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

string determineCompiler()
{
	version(DigitalMars) return "dmd";
	else version(GNU) return "gdc";
	else version(LDC) return "ldc";
	else version(SDC) return "sdc";
	else return null;
}
