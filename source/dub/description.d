/**
	Types for project descriptions (dub describe).

	Copyright: © 2015 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.description;

import dub.compilers.buildsettings;
import dub.dependency;
import dub.internal.vibecompat.data.serialization;


/**
	Describes a complete project for use in IDEs or build tools.

	The build settings will be specific to the compiler, platform
	and configuration that has been selected.
*/
struct ProjectDescription {
	string rootPackage;
	alias mainPackage = rootPackage; /// Compatibility alias
	string configuration;
	string buildType;
	string compiler;
	string[] architecture;
	string[] platform;
	PackageDescription[] packages; /// All packages in the dependency tree
	TargetDescription[] targets; /// Build targets
	@ignore size_t[string] targetLookup; /// Target index by name
	
	/// Targets by name
	ref inout(TargetDescription) lookupTarget(string name) inout
	{
		import std.exception : enforce;
		auto pti = name in targetLookup;
		enforce(pti !is null, "Target '"~name~"' doesn't exist. Is the target type set to \"none\" in the package recipe?");
		return targets[*pti];
	}

	/// Projects by name
	ref inout(PackageDescription) lookupPackage(string name) inout
	{
		foreach (ref p; packages)
			if (p.name == name)
			{
				static if (__VERSION__ > 2065)
					return p;
				else
					return *cast(inout(PackageDescription)*)&p;
			}
		throw new Exception("Package '"~name~"' not found in dependency tree.");
	}

	/// Root package
	ref inout(PackageDescription) lookupRootPackage() inout { return lookupPackage(rootPackage); }
}


/**
	Build settings and meta data of a single package.
*/
struct PackageDescription {
	string path;
	string name;
	Version version_;
	string description;
	string homepage;
	string[] authors;
	string copyright;
	string license;
	string[] dependencies;

	bool active; /// Does this package take part in the build?
	string configuration; /// The configuration that is built
	@byName TargetType targetType;
	string targetPath;
	string targetName;
	string targetFileName;
	string workingDirectory;
	string mainSourceFile;
	string[] dflags;
	string[] lflags;
	string[] libs;
	string[] copyFiles;
	string[] versions;
	string[] debugVersions;
	string[] importPaths;
	string[] stringImportPaths;
	string[] preGenerateCommands;
	string[] postGenerateCommands;
	string[] preBuildCommands;
	string[] postBuildCommands;
	@byName BuildRequirement[] buildRequirements;
	@byName BuildOption[] options;
	SourceFileDescription[] files;
}

struct TargetDescription {
	string rootPackage;
	string[] packages;
	string rootConfiguration;
	BuildSettings buildSettings;
	string[] dependencies;
	string[] linkDependencies;
}

/**
	Description for a single source file.
*/
struct SourceFileDescription {
	@byName SourceFileRole role;
	alias type = role; /// Compatibility alias
	string path;
}

/**
	Determines 
*/
enum SourceFileRole {
	unusedStringImport,
	unusedImport,
	unusedSource,
	stringImport,
	import_,
	source
}
