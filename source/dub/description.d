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
	@ignore TargetDescription[string] targetLookup; /// Targets by name
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
