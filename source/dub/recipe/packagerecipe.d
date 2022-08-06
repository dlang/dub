/**
	Abstract representation of a package description file.

	Copyright: © 2012-2014 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Matthias Dondorff
*/
module dub.recipe.packagerecipe;

import dub.compilers.compiler;
import dub.compilers.utils : warnOnSpecialCompilerFlags;
import dub.dependency;
import dub.internal.logging;

import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.inet.path;

import std.algorithm : findSplit, sort;
import std.array : join, split;
import std.exception : enforce;
import std.file;
import std.range;
import std.process : environment;


/**
	Returns the individual parts of a qualified package name.

	Sub qualified package names are lists of package names separated by ":". For
	example, "packa:packb:packc" references a package named "packc" that is a
	sub package of "packb", which in turn is a sub package of "packa".
*/
string[] getSubPackagePath(PackageName name) @safe pure
{
	return name[].split(":");
}

/**
	Returns the name of the top level package for a given (sub) package name.

	In case of a top level package, the qualified name is returned unmodified.
*/
PackageName getBasePackageName(PackageName name) @safe pure
{
	return typeof(return)(name[].findSplit(":")[0]);
}

/**
	Returns the qualified sub package part of the given package name.

	This is the part of the package name excluding the base package
	name. See also $(D getBasePackageName).
*/
PackageName getSubPackageName(PackageName name) @safe pure
{
	return typeof(return)(name[].findSplit(":")[2]);
}

@safe unittest
{
	assert(getSubPackagePath(PackageName("packa:packb:packc")) == ["packa", "packb", "packc"]);
	assert(getSubPackagePath(PackageName("pack")) == ["pack"]);
	assert(getBasePackageName(PackageName("packa:packb:packc")) == "packa");
	assert(getBasePackageName(PackageName("pack")) == "pack");
	assert(getSubPackageName(PackageName("packa:packb:packc")) == "packb:packc");
	assert(getSubPackageName(PackageName("pack")) == "");
}

/**
	Represents the contents of a package recipe file (dub.json/dub.sdl) in an abstract way.

	This structure is used to reason about package descriptions in isolation.
	For higher level package handling, see the $(D Package) class.
*/
struct PackageRecipe {
	PackageName name;
	string version_;
	string description;
	string homepage;
	string[] authors;
	string copyright;
	string license;
	string[] ddoxFilterArgs;
	string ddoxTool;
	BuildSettingsTemplate buildSettings;
	ConfigurationInfo[] configurations;
	BuildSettingsTemplate[string] buildTypes;

	ToolchainRequirements toolchainRequirements;

	SubPackage[] subPackages;

	inout(ConfigurationInfo) getConfiguration(string name)
	inout {
		foreach (c; configurations)
			if (c.name == name)
				return c;
		throw new Exception("Unknown configuration: "~name);
	}

	/** Clones the package recipe recursively.
	*/
	PackageRecipe clone() const { return .clone(this); }
}

struct SubPackage
{
	string path;
	PackageRecipe recipe;
}

/// Describes minimal toolchain requirements
struct ToolchainRequirements
{
	import std.typecons : Tuple, tuple;

	/// DUB version requirement
	Dependency dub = Dependency.any;
	/// D front-end version requirement
	Dependency frontend = Dependency.any;
	/// DMD version requirement
	Dependency dmd = Dependency.any;
	/// LDC version requirement
	Dependency ldc = Dependency.any;
	/// GDC version requirement
	Dependency gdc = Dependency.any;

	/** Get the list of supported compilers.

		Returns:
			An array of couples of compiler name and compiler requirement
	*/
	@property Tuple!(string, Dependency)[] supportedCompilers() const
	{
		Tuple!(string, Dependency)[] res;
		if (dmd != Dependency.invalid) res ~= Tuple!(string, Dependency)("dmd", dmd);
		if (ldc != Dependency.invalid) res ~= Tuple!(string, Dependency)("ldc", ldc);
		if (gdc != Dependency.invalid) res ~= Tuple!(string, Dependency)("gdc", gdc);
		return res;
	}

	bool empty()
	const {
		import std.algorithm.searching : all;
		return only(dub, frontend, dmd, ldc, gdc)
			.all!(r => r == Dependency.any);
	}
}


/// Bundles information about a build configuration.
struct ConfigurationInfo {
	string name;
	string[] platforms;
	BuildSettingsTemplate buildSettings;

	this(string name, BuildSettingsTemplate build_settings)
	{
		enforce(!name.empty, "Configuration name is empty.");
		this.name = name;
		this.buildSettings = build_settings;
	}

	bool matchesPlatform(in BuildPlatform platform)
	const {
		if( platforms.empty ) return true;
		foreach(p; platforms)
			if (platform.matchesSpecification(p))
				return true;
		return false;
	}
}

/// This keeps general information about how to build a package.
/// It contains functions to create a specific BuildSetting, targeted at
/// a certain BuildPlatform.
struct BuildSettingsTemplate {
	Dependency[PackageName] dependencies;
	BuildSettingsTemplate[PackageName] dependencyBuildSettings;
	string systemDependencies;
	TargetType targetType = TargetType.autodetect;
	string targetPath;
	string targetName;
	string workingDirectory;
	string mainSourceFile;
	string[PackageName] subConfigurations;
	string[][string] dflags;
	string[][string] lflags;
	string[][string] libs;
	string[][string] sourceFiles;
	string[][string] sourcePaths;
	string[][string] excludedSourceFiles;
	string[][string] injectSourceFiles;
	string[][string] copyFiles;
	string[][string] extraDependencyFiles;
	string[][string] versions;
	string[][string] debugVersions;
	string[][string] versionFilters;
	string[][string] debugVersionFilters;
	string[][string] importPaths;
	string[][string] stringImportPaths;
	string[][string] preGenerateCommands;
	string[][string] postGenerateCommands;
	string[][string] preBuildCommands;
	string[][string] postBuildCommands;
	string[][string] preRunCommands;
	string[][string] postRunCommands;
	string[string][string] environments;
	string[string][string] buildEnvironments;
	string[string][string] runEnvironments;
	string[string][string] preGenerateEnvironments;
	string[string][string] postGenerateEnvironments;
	string[string][string] preBuildEnvironments;
	string[string][string] postBuildEnvironments;
	string[string][string] preRunEnvironments;
	string[string][string] postRunEnvironments;
	Flags!BuildRequirement[string] buildRequirements;
	Flags!BuildOption[string] buildOptions;


	BuildSettingsTemplate dup() const {
		return clone(this);
	}

	/// Constructs a BuildSettings object from this template.
	void getPlatformSettings(ref BuildSettings dst, in BuildPlatform platform, NativePath base_path)
	const {
		dst.targetType = this.targetType;
		if (!this.targetPath.empty) dst.targetPath = this.targetPath;
		if (!this.targetName.empty) dst.targetName = this.targetName;
		if (!this.workingDirectory.empty) dst.workingDirectory = this.workingDirectory;
		if (!this.mainSourceFile.empty) {
			auto p = NativePath(this.mainSourceFile);
			p.normalize();
			dst.mainSourceFile = p.toNativeString();
			dst.addSourceFiles(dst.mainSourceFile);
		}

		string[] collectFiles(in string[][string] paths_map, string pattern)
		{
			auto files = appender!(string[]);

			import dub.project : buildSettingsVars;
			import std.typecons : Nullable;

			static Nullable!(string[string]) envVarCache;

			if (envVarCache.isNull) envVarCache = environment.toAA();

			foreach (suffix, paths; paths_map) {
				if (!platform.matchesSpecification(suffix))
					continue;

				foreach (spath; paths) {
					enforce(!spath.empty, "Paths must not be empty strings.");
					auto path = NativePath(spath);
					if (!path.absolute) path = base_path ~ path;
					if (!existsFile(path) || !isDir(path.toNativeString())) {
						import std.algorithm : any, find;
						const hasVar = chain(buildSettingsVars, envVarCache.get.byKey).any!((string var) {
							return spath.find("$"~var).length > 0 || spath.find("${"~var~"}").length > 0;
						});
						if (!hasVar)
							logWarn("Invalid source/import path: %s", path.toNativeString());
						continue;
					}

					auto pstr = path.toNativeString();
					foreach (d; dirEntries(pstr, pattern, SpanMode.depth)) {
						import std.path : baseName, pathSplitter;
						import std.algorithm.searching : canFind;
						// eliminate any hidden files, or files in hidden directories. But always include
						// files that are listed inside hidden directories that are specifically added to
						// the project.
						if (d.isDir || pathSplitter(d.name[pstr.length .. $])
								   .canFind!(name => name.length && name[0] == '.'))
							continue;
						auto src = NativePath(d.name).relativeTo(base_path);
						files ~= src.toNativeString();
					}
				}
			}

			return files.data;
		}

 		// collect source files
		dst.addSourceFiles(collectFiles(sourcePaths, "*.d"));
		auto sourceFiles = dst.sourceFiles.sort();

 		// collect import files and remove sources
		import std.algorithm : copy, setDifference;

		auto importFiles = collectFiles(importPaths, "*.{d,di}").sort();
		immutable nremoved = importFiles.setDifference(sourceFiles).copy(importFiles.release).length;
		importFiles = importFiles[0 .. $ - nremoved];
		dst.addImportFiles(importFiles.release);

		dst.addStringImportFiles(collectFiles(stringImportPaths, "*"));

		getPlatformSetting!("dflags", "addDFlags")(dst, platform);
		getPlatformSetting!("lflags", "addLFlags")(dst, platform);
		getPlatformSetting!("libs", "addLibs")(dst, platform);
		getPlatformSetting!("sourceFiles", "addSourceFiles")(dst, platform);
		getPlatformSetting!("excludedSourceFiles", "removeSourceFiles")(dst, platform);
		getPlatformSetting!("injectSourceFiles", "addInjectSourceFiles")(dst, platform);
		getPlatformSetting!("copyFiles", "addCopyFiles")(dst, platform);
		getPlatformSetting!("extraDependencyFiles", "addExtraDependencyFiles")(dst, platform);
		getPlatformSetting!("versions", "addVersions")(dst, platform);
		getPlatformSetting!("debugVersions", "addDebugVersions")(dst, platform);
		getPlatformSetting!("versionFilters", "addVersionFilters")(dst, platform);
		getPlatformSetting!("debugVersionFilters", "addDebugVersionFilters")(dst, platform);
		getPlatformSetting!("importPaths", "addImportPaths")(dst, platform);
		getPlatformSetting!("stringImportPaths", "addStringImportPaths")(dst, platform);
		getPlatformSetting!("preGenerateCommands", "addPreGenerateCommands")(dst, platform);
		getPlatformSetting!("postGenerateCommands", "addPostGenerateCommands")(dst, platform);
		getPlatformSetting!("preBuildCommands", "addPreBuildCommands")(dst, platform);
		getPlatformSetting!("postBuildCommands", "addPostBuildCommands")(dst, platform);
		getPlatformSetting!("preRunCommands", "addPreRunCommands")(dst, platform);
		getPlatformSetting!("postRunCommands", "addPostRunCommands")(dst, platform);
		getPlatformSetting!("environments", "addEnvironments")(dst, platform);
		getPlatformSetting!("buildEnvironments", "addBuildEnvironments")(dst, platform);
		getPlatformSetting!("runEnvironments", "addRunEnvironments")(dst, platform);
		getPlatformSetting!("preGenerateEnvironments", "addPreGenerateEnvironments")(dst, platform);
		getPlatformSetting!("postGenerateEnvironments", "addPostGenerateEnvironments")(dst, platform);
		getPlatformSetting!("preBuildEnvironments", "addPreBuildEnvironments")(dst, platform);
		getPlatformSetting!("postBuildEnvironments", "addPostBuildEnvironments")(dst, platform);
		getPlatformSetting!("preRunEnvironments", "addPreRunEnvironments")(dst, platform);
		getPlatformSetting!("postRunEnvironments", "addPostRunEnvironments")(dst, platform);
		getPlatformSetting!("buildRequirements", "addRequirements")(dst, platform);
		getPlatformSetting!("buildOptions", "addOptions")(dst, platform);
	}

	void getPlatformSetting(string name, string addname)(ref BuildSettings dst, in BuildPlatform platform)
	const {
		foreach(suffix, values; __traits(getMember, this, name)){
			if( platform.matchesSpecification(suffix) )
				__traits(getMember, dst, addname)(values);
		}
	}

	void warnOnSpecialCompilerFlags(PackageName name, string config_name)
	{
		auto nodef = false;
		auto noprop = false;
		foreach (req; this.buildRequirements) {
			if (req & BuildRequirement.noDefaultFlags) nodef = true;
			if (req & BuildRequirement.relaxProperties) noprop = true;
		}

		if (noprop) {
			logWarn(`Warning: "buildRequirements": ["relaxProperties"] is deprecated and is now the default behavior. Note that the -property switch will probably be removed in future versions of DMD.`);
			logWarn("");
		}

		if (nodef) {
			logWarn("Warning: This package uses the \"noDefaultFlags\" build requirement. Please use only for development purposes and not for released packages.");
			logWarn("");
		} else {
			string[] all_dflags;
			Flags!BuildOption all_options;
			foreach (flags; this.dflags) all_dflags ~= flags;
			foreach (options; this.buildOptions) all_options |= options;
			.warnOnSpecialCompilerFlags(all_dflags, all_options, name, config_name);
		}
	}
}

package(dub) void checkPlatform(const scope ref ToolchainRequirements tr, BuildPlatform platform, PackageName name)
{
	import dub.compilers.utils : dmdLikeVersionToSemverLike;
	import std.algorithm.iteration : map;
	import std.format : format;

	string compilerver;
	Dependency compilerspec;

	switch (platform.compiler) {
		default:
			compilerspec = Dependency.any;
			compilerver = "0.0.0";
			break;
		case "dmd":
			compilerspec = tr.dmd;
			compilerver = platform.compilerVersion.length
				? dmdLikeVersionToSemverLike(platform.compilerVersion)
				: "0.0.0";
			break;
		case "ldc":
			compilerspec = tr.ldc;
			compilerver = platform.compilerVersion;
			if (!compilerver.length) compilerver = "0.0.0";
			break;
		case "gdc":
			compilerspec = tr.gdc;
			compilerver = platform.compilerVersion;
			if (!compilerver.length) compilerver = "0.0.0";
			break;
	}

	enforce(compilerspec != Dependency.invalid,
		format(
			"Installed %s %s is not supported by %s. Supported compiler(s):\n%s",
			platform.compiler, platform.compilerVersion, name,
			tr.supportedCompilers.map!((cs) {
				auto str = "  - " ~ cs[0];
				if (cs[1] != Dependency.any) str ~= ": " ~ cs[1].toString();
				return str;
			}).join("\n")
		)
	);

	enforce(compilerspec.matches(compilerver),
		format(
			"Installed %s-%s does not comply with %s compiler requirement: %s %s\n" ~
			"Please consider upgrading your installation.",
			platform.compiler, platform.compilerVersion,
			name, platform.compiler, compilerspec
		)
	);

	enforce(tr.frontend.matches(dmdLikeVersionToSemverLike(platform.frontendVersionString)),
		format(
			"Installed %s-%s with frontend %s does not comply with %s frontend requirement: %s\n" ~
			"Please consider upgrading your installation.",
			platform.compiler, platform.compilerVersion,
			platform.frontendVersionString, name, tr.frontend
		)
	);
}

package bool addRequirement(ref ToolchainRequirements req, string name, string value)
{
	switch (name) {
		default: return false;
		case "dub": req.dub = parseDependency(value); break;
		case "frontend": req.frontend = parseDMDDependency(value); break;
		case "ldc": req.ldc = parseDependency(value); break;
		case "gdc": req.gdc = parseDependency(value); break;
		case "dmd": req.dmd = parseDMDDependency(value); break;
	}
	return true;
}

private static Dependency parseDependency(string dep)
{
	if (dep == "no") return Dependency.invalid;
	return Dependency(dep);
}

private static Dependency parseDMDDependency(string dep)
{
	import dub.compilers.utils : dmdLikeVersionToSemverLike;
	import dub.dependency : Dependency;
	import std.algorithm : map, splitter;
	import std.array : join;

	if (dep == "no") return Dependency.invalid;
	return dep
		.splitter(' ')
		.map!(r => dmdLikeVersionToSemverLike(r))
		.join(' ')
		.Dependency;
}

private T clone(T)(ref const(T) val)
{
	import std.sumtype;
	import std.traits : isSomeString, isDynamicArray, isAssociativeArray, isBasicType, ValueType;

	static if (is(T == immutable)) return val;
	else static if (isBasicType!T) return val;
	else static if (isDynamicArray!T) {
		alias V = typeof(T.init[0]);
		static if (is(V == immutable)) return val;
		else {
			T ret = new V[val.length];
			foreach (i, ref f; val)
				ret[i] = clone!V(f);
			return ret;
		}
	} else static if (isAssociativeArray!T) {
		alias V = ValueType!T;
		T ret;
		foreach (k, ref f; val)
			ret[k] = clone!V(f);
		return ret;
	} else static if (is(T == SumType!A, A...)) {
		return val.match!((any) => T(clone(any)));
	} else static if (is(T == struct)) {
		T ret;
		foreach (i, M; typeof(T.tupleof))
			ret.tupleof[i] = clone!M(val.tupleof[i]);
		return ret;
	} else static assert(false, "Unsupported type: "~T.stringof);
}

unittest { // issue #1407 - duplicate main source file
	{
		BuildSettingsTemplate t;
		t.mainSourceFile = "./foo.d";
		t.sourceFiles[""] = ["foo.d"];
		BuildSettings bs;
		t.getPlatformSettings(bs, BuildPlatform.init, NativePath("/"));
		assert(bs.sourceFiles == ["foo.d"]);
	}

	version (Windows) {{
		BuildSettingsTemplate t;
		t.mainSourceFile = "src/foo.d";
		t.sourceFiles[""] = ["src\\foo.d"];
		BuildSettings bs;
		t.getPlatformSettings(bs, BuildPlatform.init, NativePath("/"));
		assert(bs.sourceFiles == ["src\\foo.d"]);
	}}
}
