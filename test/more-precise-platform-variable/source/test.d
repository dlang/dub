module test;

import platform;

unittest
{
	version(WebAssembly) assert(dub_platform_os == "wasm");
	else version(PlayStation4) assert(dub_platform_os == "playstation4");
	else version(MinGW) assert(dub_platform_os == "mingw");
	else version(Cygwin) assert(dub_platform_os == "cygwin");
	else version(Android) assert(dub_platform_os == "android");
	else version(Hurd) assert(dub_platform_os == "hurd");
	else version(SysV4) assert(dub_platform_os == "sysv4");
	else version(SysV3) assert(dub_platform_os == "sysv3");
	else version(SkyOS) assert(dub_platform_os == "skyos");
	else version(Haiku) assert(dub_platform_os == "haiku");
	else version(AIX) assert(dub_platform_os == "aix");
	else version(Solaris) assert(dub_platform_os == "solaris");
	else version(BSD) assert(dub_platform_os == "bsd");
	else version(DragonFlyBSD) assert(dub_platform_os == "dragonflybsd");
	else version(NetBSD) assert(dub_platform_os == "netbsd");
	else version(OpenBSD) assert(dub_platform_os == "openbsd");
	else version(FreeBSD) assert(dub_platform_os == "freebsd");
	else version(WatchOS) assert(dub_platform_os ==  "watchos" );
	else version(TVOS) assert(dub_platform_os ==  "tvos");
	else version(iOS) assert(dub_platform_os ==  "ios");
	else version(OSX) assert(dub_platform_os ==  "osx");
	else version(linux) assert(dub_platform_os == "linux");
	else version(Windows) assert(dub_platform_os == "windows");
    else static assert(0, "unknown platform");
}
