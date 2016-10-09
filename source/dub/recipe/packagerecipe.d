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

import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.inet.url;

import std.algorithm : findSplit, sort;
import std.array : join, split;
import std.exception : enforce;
import std.file;
import std.range;


/**
	Returns the individual parts of a qualified package name.

	Sub qualified package names are lists of package names separated by ":". For
	example, "packa:packb:packc" references a package named "packc" that is a
	sub package of "packb", wich in turn is a sub package of "packa".
*/
string[] getSubPackagePath(string package_name)
{
	return package_name.split(":");
}

/**
	Returns the name of the top level package for a given (sub) package name.

	In case of a top level package, the qualified name is returned unmodified.
*/
string getBasePackageName(string package_name)
{
	return package_name.findSplit(":")[0];
}

/**
	Returns the qualified sub package part of the given package name.

	This is the part of the package name excluding the base package
	name. See also $(D getBasePackageName).
*/
string getSubPackageName(string package_name)
{
	return package_name.findSplit(":")[2];
}

unittest
{
	assert(getSubPackagePath("packa:packb:packc") == ["packa", "packb", "packc"]);
	assert(getSubPackagePath("pack") == ["pack"]);
	assert(getBasePackageName("packa:packb:packc") == "packa");
	assert(getBasePackageName("pack") == "pack");
	assert(getSubPackageName("packa:packb:packc") == "packb:packc");
	assert(getSubPackageName("pack") == "");
}

/**
	Represents the contents of a package recipe file (dub.json/dub.sdl) in an abstract way.

	This structure is used to reason about package descriptions in isolation.
	For higher level package handling, see the $(D Package) class.
*/
struct PackageRecipe {
	string name;
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
			if( platform.matchesSpecification("-"~p) )
				return true;
		return false;
	}
}

/// This keeps general information about how to build a package.
/// It contains functions to create a specific BuildSetting, targeted at
/// a certain BuildPlatform.
struct BuildSettingsTemplate {
	Dependency[string] dependencies;
	string systemDependencies;
	TargetType targetType = TargetType.autodetect;
	string targetPath;
	string targetName;
	string workingDirectory;
	string mainSourceFile;
	string[string] subConfigurations;
	string[][string] dflags;
	string[][string] lflags;
	string[][string] libs;
	string[][string] sourceFiles;
	string[][string] sourcePaths;
	string[][string] excludedSourceFiles;
	string[][string] copyFiles;
	string[][string] versions;
	string[][string] debugVersions;
	string[][string] importPaths;
	string[][string] stringImportPaths;
	string[][string] preGenerateCommands;
	string[][string] postGenerateCommands;
	string[][string] preBuildCommands;
	string[][string] postBuildCommands;
	string[][string] enviromentCommands; // mgw
	BuildRequirements[string] buildRequirements;
	BuildOptions[string] buildOptions;


	/// Constructs a BuildSettings object from this template.
	void getPlatformSettings(ref BuildSettings dst, in BuildPlatform platform, Path base_path)
	const {
		dst.targetType = this.targetType;
		if (!this.targetPath.empty) dst.targetPath = this.targetPath;
		if (!this.targetName.empty) dst.targetName = this.targetName;
		if (!this.workingDirectory.empty) dst.workingDirectory = this.workingDirectory;
		if (!this.mainSourceFile.empty) {
			dst.mainSourceFile = this.mainSourceFile;
			dst.addSourceFiles(this.mainSourceFile);
		}

		void collectFiles(string method)(in string[][string] paths_map, string pattern)
		{
			foreach (suffix, paths; paths_map) {
				if (!platform.matchesSpecification(suffix))
					continue;

				foreach (spath; paths) {
					enforce(!spath.empty, "Paths must not be empty strings.");
					auto path = Path(spath);
					if (!path.absolute) path = base_path ~ path;
					if (!existsFile(path) || !isDir(path.toNativeString())) {
						logWarn("Invalid source/import path: %s", path.toNativeString());
						continue;
					}

					foreach (d; dirEntries(path.toNativeString(), pattern, SpanMode.depth)) {
						import std.path : baseName;
						if (baseName(d.name)[0] == '.' || isDir(d.name)) continue;
						auto src = Path(d.name).relativeTo(base_path);
						__traits(getMember, dst, method)(src.toNativeString());
					}
				}
			}
		}

		// collect files from all source/import folders
		collectFiles!"addSourceFiles"(sourcePaths, "*.d");
		collectFiles!"addImportFiles"(importPaths, "*.{d,di}");
		dst.removeImportFiles(dst.sourceFiles);
		collectFiles!"addStringImportFiles"(stringImportPaths, "*");

		// ensure a deterministic order of files as passed to the compiler
		dst.sourceFiles.sort();

		getPlatformSetting!("dflags", "addDFlags")(dst, platform);
		getPlatformSetting!("lflags", "addLFlags")(dst, platform);
		getPlatformSetting!("libs", "addLibs")(dst, platform);
		getPlatformSetting!("sourceFiles", "addSourceFiles")(dst, platform);
		getPlatformSetting!("excludedSourceFiles", "removeSourceFiles")(dst, platform);
		getPlatformSetting!("copyFiles", "addCopyFiles")(dst, platform);
		getPlatformSetting!("versions", "addVersions")(dst, platform);
		getPlatformSetting!("debugVersions", "addDebugVersions")(dst, platform);
		getPlatformSetting!("importPaths", "addImportPaths")(dst, platform);
		getPlatformSetting!("stringImportPaths", "addStringImportPaths")(dst, platform);
		getPlatformSetting!("preGenerateCommands", "addPreGenerateCommands")(dst, platform);
		getPlatformSetting!("postGenerateCommands", "addPostGenerateCommands")(dst, platform);
		getPlatformSetting!("preBuildCommands", "addPreBuildCommands")(dst, platform);
		getPlatformSetting!("postBuildCommands", "addPostBuildCommands")(dst, platform);
		// mgw
		getPlatformSetting!("enviromentCommands", "addEnviromentCommands")(dst, platform);
		//
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

	void warnOnSpecialCompilerFlags(string package_name, string config_name)
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
			BuildOptions all_options;
			foreach (flags; this.dflags) all_dflags ~= flags;
			foreach (options; this.buildOptions) all_options |= options;
			.warnOnSpecialCompilerFlags(all_dflags, all_options, package_name, config_name);
		}
	}
}

private T clone(T)(ref const(T) val)
{
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
	} else static if (is(T == struct)) {
		T ret;
		foreach (i, M; typeof(T.tupleof))
			ret.tupleof[i] = clone!M(val.tupleof[i]);
		return ret;
	} else static assert(false, "Unsupported type: "~T.stringof);
}
