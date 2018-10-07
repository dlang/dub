/**
	GDC compiler support.

	Copyright: © 2013-2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.gdc;

import dub.compilers.compiler;
import dub.compilers.utils;
import dub.internal.utils;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.inet.path;
import dub.recipe.packagerecipe : ToolchainRequirements;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.process;
import std.typecons;


class GDCCompiler : Compiler {
	private static immutable s_options = [
		tuple(BuildOption.debugMode, ["-fdebug"]),
		tuple(BuildOption.releaseMode, ["-frelease"]),
		tuple(BuildOption.coverage, ["-fprofile-arcs", "-ftest-coverage"]),
		tuple(BuildOption.debugInfo, ["-g"]),
		tuple(BuildOption.debugInfoC, ["-g", "-fdebug-c"]),
		//tuple(BuildOption.alwaysStackFrame, ["-X"]),
		//tuple(BuildOption.stackStomping, ["-X"]),
		tuple(BuildOption.inline, ["-finline-functions"]),
		tuple(BuildOption.noBoundsCheck, ["-fno-bounds-check"]),
		tuple(BuildOption.optimize, ["-O3"]),
		tuple(BuildOption.profile, ["-pg"]),
		tuple(BuildOption.unittests, ["-funittest"]),
		tuple(BuildOption.verbose, ["-fd-verbose"]),
		tuple(BuildOption.ignoreUnknownPragmas, ["-fignore-unknown-pragmas"]),
		tuple(BuildOption.syntaxOnly, ["-fsyntax-only"]),
		tuple(BuildOption.warnings, ["-Wall"]),
		tuple(BuildOption.warningsAsErrors, ["-Werror", "-Wall"]),
		tuple(BuildOption.ignoreDeprecations, ["-Wno-deprecated"]),
		tuple(BuildOption.deprecationWarnings, ["-Wdeprecated"]),
		tuple(BuildOption.deprecationErrors, ["-Werror", "-Wdeprecated"]),
		tuple(BuildOption.property, ["-fproperty"]),
		//tuple(BuildOption.profileGC, ["-?"]),

		tuple(BuildOption._docs, ["-fdoc-dir=docs"]),
		tuple(BuildOption._ddox, ["-fXf=docs.json", "-fdoc-file=__dummy.html"]),
	];

	@property string name() const { return "gdc"; }

	enum gdcVersionRe1 = `GDC\s+(\d+\.\d+\.\d+[A-Za-z0-9.+-]*)`;
	enum gdcVersionRe2 = `^GNU D \(.*?\) version (\d+\.\d+\.\d+[A-Za-z0-9.+-]*)`;
	enum gdcVersionRe3 = `^gcc version (\d+\.\d+\.\d+[A-Za-z0-9.+-]*)`;

	unittest {
		import std.algorithm : equal, map;
		import std.range : only;
		import std.regex : matchFirst, regex;
		auto probe = `
Target: x86_64-pc-linux-gnu
Thread model: posix
gcc version 8.2.1 20180831 (GDC 8.2.1 based on D v2.068.2 built with ISL 0.20 for Arch Linux)
GGC heuristics: --param ggc-min-expand=100 --param ggc-min-heapsize=131072
GNU D (GDC 8.2.1 based on D v2.068.2 built with ISL 0.20 for Arch Linux) version 8.2.1 20180831 (x86_64-pc-linux-gnu)
GGC heuristics: --param ggc-min-expand=100 --param ggc-min-heapsize=131072
binary    /usr/lib/gcc/x86_64-pc-linux-gnu/8.2.1/cc1d
version   v2.068.2
predefs   GNU D_Version2 LittleEndian GNU_DWARF2_Exceptions GNU_StackGrowsDown GNU_InlineAsm D_LP64 D_PIC assert all X86_64 D_HardFloat Posix linux CRuntime_Glibc
`;
		auto vers = only(gdcVersionRe1, gdcVersionRe2, gdcVersionRe3)
			.map!(re => matchFirst(probe, regex(re, "m")))
			.filter!(c => c && c.length > 1)
			.map!(c => c[1]);

		assert(vers.equal([ "8.2.1", "8.2.1", "8.2.1" ]));
	}

	BuildPlatform determinePlatform(ref BuildSettings settings, string compiler_binary, string arch_override)
	{
		string[] arch_flags;
		switch (arch_override) {
			default: throw new Exception("Unsupported architecture: "~arch_override);
			case "": break;
			case "arm": arch_flags = ["-marm"]; break;
			case "arm_thumb": arch_flags = ["-mthumb"]; break;
			case "x86": arch_flags = ["-m32"]; break;
			case "x86_64": arch_flags = ["-m64"]; break;
		}
		settings.addDFlags(arch_flags);

		return probePlatform(
			compiler_binary,
			arch_flags ~ ["-S", "-v"],
			arch_override,
			[ gdcVersionRe1, gdcVersionRe2, gdcVersionRe3 ]
		);
	}

	void prepareBuildSettings(ref BuildSettings settings, BuildSetting fields = BuildSetting.all) const
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
			settings.addDFlags(lflagsToDFlags(settings.lflags));
			settings.lflags = null;
		}

		if (settings.options & BuildOption.pic)
			settings.addDFlags("-fPIC");

		assert(fields & BuildSetting.dflags);
		assert(fields & BuildSetting.copyFiles);
	}

	void extractBuildOptions(ref BuildSettings settings) const
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

	string getTargetFileName(in BuildSettings settings, in BuildPlatform platform)
	const {
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
				return "lib" ~ settings.targetName ~ ".a";
			case TargetType.dynamicLibrary:
				if (platform.platform.canFind("windows"))
					return settings.targetName ~ ".dll";
				else if (platform.platform.canFind("osx"))
					return "lib" ~ settings.targetName ~ ".dylib";
				else return "lib" ~ settings.targetName ~ ".so";
			case TargetType.object:
				if (platform.platform.canFind("windows"))
					return settings.targetName ~ ".obj";
				else return settings.targetName ~ ".o";
		}
	}

	void setTarget(ref BuildSettings settings, in BuildPlatform platform, string tpath = null) const
	{
		final switch (settings.targetType) {
			case TargetType.autodetect: assert(false, "Invalid target type: autodetect");
			case TargetType.none: assert(false, "Invalid target type: none");
			case TargetType.sourceLibrary: assert(false, "Invalid target type: sourceLibrary");
			case TargetType.executable: break;
			case TargetType.library:
			case TargetType.staticLibrary:
			case TargetType.object:
				settings.addDFlags("-c");
				break;
			case TargetType.dynamicLibrary:
				settings.addDFlags("-shared", "-fPIC");
				break;
		}

		if (tpath is null)
			tpath = (NativePath(settings.targetPath) ~ getTargetFileName(settings, platform)).toNativeString();
		settings.addDFlags("-o", tpath);
	}

	void invoke(in BuildSettings settings, in BuildPlatform platform, void delegate(int, string) output_callback)
	{
		auto res_file = getTempFile("dub-build", ".rsp");
		std.file.write(res_file.toNativeString(), join(settings.dflags.map!(s => escape(s)), "\n"));

		logDiagnostic("%s %s", platform.compilerBinary, join(cast(string[])settings.dflags, " "));
		invokeTool([platform.compilerBinary, "@"~res_file.toNativeString()], output_callback);
	}

	void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects, void delegate(int, string) output_callback)
	{
		import std.string;
		string[] args;
		// As the user is supposed to call setTarget prior to invoke, -o target is already set.
		if (settings.targetType == TargetType.staticLibrary || settings.targetType == TargetType.staticLibrary) {
			auto tpath = extractTarget(settings.dflags);
			assert(tpath !is null, "setTarget should be called before invoke");
			args = [ "ar", "rcs", tpath ] ~ objects;
		} else {
			args = platform.compilerBinary ~ objects ~ settings.sourceFiles ~ settings.lflags ~ settings.dflags.filter!(f => isLinkageFlag(f)).array;
			version(linux) args ~= "-L--no-as-needed"; // avoids linker errors due to libraries being specified in the wrong order by DMD
		}
		logDiagnostic("%s", args.join(" "));
		invokeTool(args, output_callback);
	}

	string[] lflagsToDFlags(in string[] lflags) const
	{
		string[] dflags;
		foreach( f; lflags )
		{
			dflags ~= "-Xlinker";
			dflags ~= f;
		}

		return  dflags;
	}

	final string toolchainRequirementString(const ref ToolchainRequirements tr)
	{
		return tr.gdc;
	}

	final bool checkCompilerRequirement(const ref BuildPlatform platform, const ref ToolchainRequirements tr)
	{
		import std.typecons : No;

		return checkRequirement(tr.gdc, platform.compilerVersion, No.dmdVer);
	}
}

private string extractTarget(const string[] args) { auto i = args.countUntil("-o"); return i >= 0 ? args[i+1] : null; }

private bool isLinkageFlag(string flag) {
	switch (flag) {
		case "-c":
			return false;
		default:
			return true;
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
