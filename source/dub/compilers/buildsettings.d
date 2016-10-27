/**
	Build settings definitions.

	Copyright: © 2013-2014 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.buildsettings;

import dub.internal.vibecompat.inet.path;

import std.array : array;
import std.algorithm : filter;
import std.path : globMatch;
static if (__VERSION__ >= 2067)
	import std.typecons : BitFlags;


/// BuildPlatform specific settings, like needed libraries or additional
/// include paths.
struct BuildSettings {
	import dub.internal.vibecompat.data.serialization : byName;

	TargetType targetType;
	string targetPath;
	string targetName;
	string workingDirectory;
	string mainSourceFile;
	string[] dflags;
	string[] lflags;
	string[] libs;
	string[] linkerFiles;
	string[] sourceFiles;
	string[] copyFiles;
	string[] versions;
	string[] debugVersions;
	string[] importPaths;
	string[] stringImportPaths;
	string[] importFiles;
	string[] stringImportFiles;
	string[] preGenerateCommands;
	string[] postGenerateCommands;
	string[] preBuildCommands;
	string[] postBuildCommands;
	@byName BuildRequirements requirements;
	@byName BuildOptions options;

	BuildSettings dup()
	const {
		BuildSettings ret;
		foreach (m; __traits(allMembers, BuildSettings)) {
			static if (is(typeof(__traits(getMember, ret, m) = __traits(getMember, this, m).dup)))
				__traits(getMember, ret, m) = __traits(getMember, this, m).dup;
			else static if (is(typeof(__traits(getMember, ret, m) = __traits(getMember, this, m))))
				__traits(getMember, ret, m) = __traits(getMember, this, m);
		}
		assert(ret.targetType == targetType);
		assert(ret.targetName == targetName);
		assert(ret.importPaths == importPaths);
		return ret;
	}

	void add(in BuildSettings bs)
	{
		addDFlags(bs.dflags);
		addLFlags(bs.lflags);
		addLibs(bs.libs);
		addLinkerFiles(bs.linkerFiles);
		addSourceFiles(bs.sourceFiles);
		addCopyFiles(bs.copyFiles);
		addVersions(bs.versions);
		addDebugVersions(bs.debugVersions);
		addImportPaths(bs.importPaths);
		addStringImportPaths(bs.stringImportPaths);
		addImportFiles(bs.importFiles);
		addStringImportFiles(bs.stringImportFiles);
		addPreGenerateCommands(bs.preGenerateCommands);
		addPostGenerateCommands(bs.postGenerateCommands);
		addPreBuildCommands(bs.preBuildCommands);
		addPostBuildCommands(bs.postBuildCommands);
	}

	void addDFlags(in string[] value...) { dflags ~= value; }
	void prependDFlags(in string[] value...) { prepend(dflags, value); }
	void removeDFlags(in string[] value...) { remove(dflags, value); }
	void addLFlags(in string[] value...) { lflags ~= value; }
	void addLibs(in string[] value...) { add(libs, value); }
	void addLinkerFiles(in string[] value...) { add(linkerFiles, value); }
	void addSourceFiles(in string[] value...) { add(sourceFiles, value); }
	void prependSourceFiles(in string[] value...) { prepend(sourceFiles, value); }
	void removeSourceFiles(in string[] value...) { removePaths(sourceFiles, value); }
	void addCopyFiles(in string[] value...) { add(copyFiles, value); }
	void addVersions(in string[] value...) { add(versions, value); }
	void addDebugVersions(in string[] value...) { add(debugVersions, value); }
	void addImportPaths(in string[] value...) { add(importPaths, value); }
	void addStringImportPaths(in string[] value...) { add(stringImportPaths, value); }
	void prependStringImportPaths(in string[] value...) { prepend(stringImportPaths, value); }
	void addImportFiles(in string[] value...) { add(importFiles, value); }
	void addStringImportFiles(in string[] value...) { addSI(stringImportFiles, value); }
	void addPreGenerateCommands(in string[] value...) { add(preGenerateCommands, value, false); }
	void addPostGenerateCommands(in string[] value...) { add(postGenerateCommands, value, false); }
	void addPreBuildCommands(in string[] value...) { add(preBuildCommands, value, false); }
	void addPostBuildCommands(in string[] value...) { add(postBuildCommands, value, false); }
	void addRequirements(in BuildRequirement[] value...) { foreach (v; value) this.requirements |= v; }
	void addRequirements(in BuildRequirements value) { this.requirements |= value; }
	void addOptions(in BuildOption[] value...) { foreach (v; value) this.options |= v; }
	void addOptions(in BuildOptions value) { this.options |= value; }
	void removeOptions(in BuildOption[] value...) { foreach (v; value) this.options &= ~v; }
	void removeOptions(in BuildOptions value) { this.options &= ~value; }

	// Adds vals to arr without adding duplicates.
	private void add(ref string[] arr, in string[] vals, bool no_duplicates = true)
	{
		if (!no_duplicates) {
			arr ~= vals;
			return;
		}

		foreach (v; vals) {
			bool found = false;
			foreach (i; 0 .. arr.length)
				if (arr[i] == v) {
					found = true;
					break;
				}
			if (!found) arr ~= v;
		}
	}

	private void prepend(ref string[] arr, in string[] vals, bool no_duplicates = true)
	{
		if (!no_duplicates) {
			arr = vals ~ arr;
			return;
		}

		foreach_reverse (v; vals) {
			bool found = false;
			foreach (i; 0 .. arr.length)
				if (arr[i] == v) {
					found = true;
					break;
				}
			if (!found) arr = v ~ arr;
		}
	}

	// add string import files (avoids file name duplicates in addition to path duplicates)
	private void addSI(ref string[] arr, in string[] vals)
	{
		bool[string] existing;
		foreach (v; arr) existing[Path(v).head.toString()] = true;
		foreach (v; vals) {
			auto s = Path(v).head.toString();
			if (s !in existing) {
				existing[s] = true;
				arr ~= v;
			}
		}
	}

	private void removePaths(ref string[] arr, in string[] vals)
	{
		bool matches(string s)
		{
			foreach (p; vals)
				if (Path(s) == Path(p) || globMatch(s, p))
					return true;
			return false;
		}
		arr = arr.filter!(s => !matches(s))().array();
	}

	private void remove(ref string[] arr, in string[] vals)
	{
		bool matches(string s)
		{
			foreach (p; vals)
				if (s == p)
					return true;
			return false;
		}
		arr = arr.filter!(s => !matches(s))().array();
	}
}

enum BuildSetting {
	dflags            = 1<<0,
	lflags            = 1<<1,
	libs              = 1<<2,
	sourceFiles       = 1<<3,
	copyFiles         = 1<<4,
	versions          = 1<<5,
	debugVersions     = 1<<6,
	importPaths       = 1<<7,
	stringImportPaths = 1<<8,
	options           = 1<<9,
	none = 0,
	commandLine = dflags|copyFiles,
	commandLineSeparate = commandLine|lflags,
	all = dflags|lflags|libs|sourceFiles|copyFiles|versions|debugVersions|importPaths|stringImportPaths|options,
	noOptions = all & ~options
}

enum TargetType {
	autodetect,
	none,
	executable,
	library,
	sourceLibrary,
	dynamicLibrary,
	staticLibrary,
	object
}

enum BuildRequirement {
	none = 0,                     /// No special requirements
	allowWarnings        = 1<<0,  /// Warnings do not abort compilation
	silenceWarnings      = 1<<1,  /// Don't show warnings
	disallowDeprecations = 1<<2,  /// Using deprecated features aborts compilation
	silenceDeprecations  = 1<<3,  /// Don't show deprecation warnings
	disallowInlining     = 1<<4,  /// Avoid function inlining, even in release builds
	disallowOptimization = 1<<5,  /// Avoid optimizations, even in release builds
	requireBoundsCheck   = 1<<6,  /// Always perform bounds checks
	requireContracts     = 1<<7,  /// Leave assertions and contracts enabled in release builds
	relaxProperties      = 1<<8,  /// DEPRECATED: Do not enforce strict property handling (-property)
	noDefaultFlags       = 1<<9,  /// Do not issue any of the default build flags (e.g. -debug, -w, -property etc.) - use only for development purposes
}

	struct BuildRequirements {
		import dub.internal.vibecompat.data.serialization : ignore;

		static if (__VERSION__ >= 2067) {
			@ignore BitFlags!BuildRequirement values;
			this(BuildRequirement req) { values = req; }
		} else {
			@ignore BuildRequirement values;
			this(BuildRequirement req) { values = req; }
			BuildRequirement[] toRepresentation()
			const {
				BuildRequirement[] ret;
				for (int f = 1; f <= BuildRequirement.max; f *= 2)
					if (values & f) ret ~= cast(BuildRequirement)f;
				return ret;
			}
			static BuildRequirements fromRepresentation(BuildRequirement[] v)
			{
				BuildRequirements ret;
				foreach (f; v) ret.values |= f;
				return ret;
			}
		}
		alias values this;
	}

enum BuildOption {
	none = 0,                     /// Use compiler defaults
	debugMode = 1<<0,             /// Compile in debug mode (enables contracts, -debug)
	releaseMode = 1<<1,           /// Compile in release mode (disables assertions and bounds checks, -release)
	coverage = 1<<2,              /// Enable code coverage analysis (-cov)
	debugInfo = 1<<3,             /// Enable symbolic debug information (-g)
	debugInfoC = 1<<4,            /// Enable symbolic debug information in C compatible form (-gc)
	alwaysStackFrame = 1<<5,      /// Always generate a stack frame (-gs)
	stackStomping = 1<<6,         /// Perform stack stomping (-gx)
	inline = 1<<7,                /// Perform function inlining (-inline)
	noBoundsCheck = 1<<8,         /// Disable all bounds checking (-noboundscheck)
	optimize = 1<<9,              /// Enable optimizations (-O)
	profile = 1<<10,              /// Emit profiling code (-profile)
	unittests = 1<<11,            /// Compile unit tests (-unittest)
	verbose = 1<<12,              /// Verbose compiler output (-v)
	ignoreUnknownPragmas = 1<<13, /// Ignores unknown pragmas during compilation (-ignore)
	syntaxOnly = 1<<14,           /// Don't generate object files (-o-)
	warnings = 1<<15,             /// Enable warnings (-wi)
	warningsAsErrors = 1<<16,     /// Treat warnings as errors (-w)
	ignoreDeprecations = 1<<17,   /// Do not warn about using deprecated features (-d)
	deprecationWarnings = 1<<18,  /// Warn about using deprecated features (-dw)
	deprecationErrors = 1<<19,    /// Stop compilation upon usage of deprecated features (-de)
	property = 1<<20,             /// DEPRECATED: Enforce property syntax (-property)
	profileGC = 1<<21,            /// Profile runtime allocations
	pic = 1<<22,                  /// Generate position independent code
	// for internal usage
	_docs = 1<<23,                // Write ddoc to docs
	_ddox = 1<<24                 // Compile docs.json
}

	struct BuildOptions {
		import dub.internal.vibecompat.data.serialization : ignore;

		static if (__VERSION__ >= 2067) {
			@ignore BitFlags!BuildOption values;
			this(BuildOption opt) { values = opt; }
			this(BitFlags!BuildOption v) { values = v; }
		} else {
			@ignore BuildOption values;
			this(BuildOption opt) { values = opt; }
			BuildOption[] toRepresentation()
			const {
				BuildOption[] ret;
				for (int f = 1; f <= BuildOption.max; f *= 2)
					if (values & f) ret ~= cast(BuildOption)f;
				return ret;
			}
			static BuildOptions fromRepresentation(BuildOption[] v)
			{
				BuildOptions ret;
				foreach (f; v) ret.values |= f;
				return ret;
			}
		}

		alias values this;
	}

/**
	All build options that will be inherited upwards in the dependency graph

	Build options in this category fulfill one of the following properties:
	$(UL
		$(LI The option affects the semantics of the generated code)
		$(LI The option affects if a certain piece of code is valid or not)
		$(LI The option enabled meta information in dependent projects that are useful for the dependee (e.g. debug information))
	)
*/
enum BuildOptions inheritedBuildOptions = BuildOption.debugMode | BuildOption.releaseMode
	| BuildOption.coverage | BuildOption.debugInfo | BuildOption.debugInfoC
	| BuildOption.alwaysStackFrame | BuildOption.stackStomping | BuildOption.inline
	| BuildOption.noBoundsCheck | BuildOption.profile | BuildOption.ignoreUnknownPragmas
	| BuildOption.syntaxOnly | BuildOption.warnings	| BuildOption.warningsAsErrors
	| BuildOption.ignoreDeprecations | BuildOption.deprecationWarnings
	| BuildOption.deprecationErrors | BuildOption.property | BuildOption.profileGC
	| BuildOption.pic;
