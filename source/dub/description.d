/**
	Types for project descriptions (dub describe).

	Copyright: © 2015-2016 rejectedsoftware e.K.
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
	string rootPackage; /// Name of the root package being built
	string configuration; /// Name of the selected build configuration
	string buildType; /// Name of the selected build type
	string compiler; /// Canonical name of the compiler used (e.g. "dmd", "gdc" or "ldc")
	string[] architecture; /// Architecture constants for the selected platform (e.g. `["x86_64"]`)
	string[] platform; /// Platform constants for the selected platform (e.g. `["posix", "osx"]`)
	PackageDescription[] packages; /// All packages in the dependency tree
	TargetDescription[] targets; /// Build targets
	@ignore size_t[string] targetLookup; /// Target index by package name name

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
				return p;
			}
		throw new Exception("Package '"~name~"' not found in dependency tree.");
	}

	/// Root package
	ref inout(PackageDescription) lookupRootPackage() inout { return lookupPackage(rootPackage); }
}


/**
	Describes the build settings and meta data of a single package.

	This structure contains the effective build settings and dependencies for
	the selected build platform. This structure is most useful for displaying
	information about a package in an IDE. Use `TargetDescription` instead when
	writing a build-tool.
*/
struct PackageDescription {
	string path; /// Path to the package
	string name; /// Qualified name of the package
	Version version_; /// Version of the package
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
	string[] dflags; /// Flags passed to the D compiler
	string[] lflags; /// Flags passed to the linker
	string[] libs; /// Librariy names to link against (typically using "-l<name>")
	string[] copyFiles; /// Files to copy to the target directory
	string[] extraDependencyFiles; /// Files to check for rebuild dub project
	string[] versions; /// D version identifiers to set
	string[] debugVersions; /// D debug version identifiers to set
	string[] importPaths;
	string[] stringImportPaths;
	string[] preGenerateCommands; /// commands executed before creating the description
	string[] postGenerateCommands; /// commands executed after creating the description
	string[] preBuildCommands; /// Commands to execute prior to every build
	string[] postBuildCommands; /// Commands to execute after every build
	string[] preRunCommands; /// Commands to execute prior to every run
	string[] postRunCommands; /// Commands to execute after every run
	@byName BuildRequirement[] buildRequirements;
	@byName BuildOption[] options;
	SourceFileDescription[] files; /// A list of all source/import files possibly used by the package
}


/**
	Describes the settings necessary to build a certain binary target.
*/
struct TargetDescription {
	string rootPackage; /// Main package associated with this target, this is also the name of the target.
	string[] packages; /// All packages contained in this target (e.g. for target type "sourceLibrary")
	string rootConfiguration; /// Build configuration of the target's root package used for building
	BuildSettings buildSettings; /// Final build settings to use when building the target
	string[] dependencies; /// List of all dependencies of this target (package names)
	string[] linkDependencies; /// List of all link-dependencies of this target (target names)
}

/**
	Description for a single source file known to the package.
*/
struct SourceFileDescription {
	@byName SourceFileRole role; /// Main role this file plays in the build process
	string path; /// Full path to the file
}

/**
	Determines the role that a file plays in the build process.

	If a file has multiple roles, higher enum values will have precedence, i.e.
	if a file is used both, as a source file and as an import file, it will
	be classified as a source file.
*/
enum SourceFileRole {
	unusedStringImport, /// Used as a string import for another configuration/platform
	unusedImport,       /// Used as an import for another configuration/platform
	unusedSource,       /// Used as a source file for another configuration/platform
	stringImport,       /// Used as a string import file
	import_,            /// Used as an import file
	source              /// Used as a source file
}
