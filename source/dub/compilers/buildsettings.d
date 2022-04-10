/**
	Build settings definitions.

	Copyright: © 2013-2014 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.buildsettings;

import dub.internal.vibecompat.inet.path;

import std.array : array;
import std.algorithm : filter, any;
import std.path : globMatch;
import std.typecons : BitFlags;
import std.algorithm.iteration : uniq;
import std.range : chain;

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
	string[] injectSourceFiles;
	string[] copyFiles;
	string[] extraDependencyFiles;
	string[] versions;
	string[] debugVersions;
	string[] versionFilters;
	string[] debugVersionFilters;
	string[] importPaths;
	string[] stringImportPaths;
	string[] importFiles;
	string[] stringImportFiles;
	string[] preGenerateCommands;
	string[] postGenerateCommands;
	string[] preBuildCommands;
	string[] postBuildCommands;
	string[] preRunCommands;
	string[] postRunCommands;
	string[string] environments;
	string[string] buildEnvironments;
	string[string] runEnvironments;
	string[string] preGenerateEnvironments;
	string[string] postGenerateEnvironments;
	string[string] preBuildEnvironments;
	string[string] postBuildEnvironments;
	string[string] preRunEnvironments;
	string[string] postRunEnvironments;
	@byName BuildRequirements requirements;
	@byName BuildOptions options;

	BuildSettings dup()
	const {
		import std.traits: FieldNameTuple;
		import std.algorithm: map;
		import std.typecons: tuple;
		import std.array: assocArray;
		BuildSettings ret;
		foreach (m; FieldNameTuple!BuildSettings) {
			static if (is(typeof(__traits(getMember, ret, m) = __traits(getMember, this, m).dup)))
				__traits(getMember, ret, m) = __traits(getMember, this, m).dup;
			else static if (is(typeof(add(__traits(getMember, ret, m), __traits(getMember, this, m)))))
				add(__traits(getMember, ret, m), __traits(getMember, this, m));
			else static if (is(typeof(__traits(getMember, ret, m) = __traits(getMember, this, m))))
				__traits(getMember, ret, m) = __traits(getMember, this, m);
			else static assert(0, "Cannot duplicate BuildSettings." ~ m);
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
		addExtraDependencyFiles(bs.extraDependencyFiles);
		addVersions(bs.versions);
		addDebugVersions(bs.debugVersions);
		addVersionFilters(bs.versionFilters);
		addDebugVersionFilters(bs.debugVersionFilters);
		addImportPaths(bs.importPaths);
		addStringImportPaths(bs.stringImportPaths);
		addImportFiles(bs.importFiles);
		addStringImportFiles(bs.stringImportFiles);
		addPreGenerateCommands(bs.preGenerateCommands);
		addPostGenerateCommands(bs.postGenerateCommands);
		addPreBuildCommands(bs.preBuildCommands);
		addPostBuildCommands(bs.postBuildCommands);
		addPreRunCommands(bs.preRunCommands);
		addPostRunCommands(bs.postRunCommands);
	}

	void addDFlags(in string[] value...) { dflags = chain(dflags, value.dup).uniq.array; }
	void prependDFlags(in string[] value...) { prepend(dflags, value); }
	void removeDFlags(in string[] value...) { remove(dflags, value); }
	void addLFlags(in string[] value...) { lflags ~= value; }
	void addLibs(in string[] value...) { add(libs, value); }
	void addLinkerFiles(in string[] value...) { add(linkerFiles, value); }
	void addSourceFiles(in string[] value...) { add(sourceFiles, value); }
	void prependSourceFiles(in string[] value...) { prepend(sourceFiles, value); }
	void removeSourceFiles(in string[] value...) { removePaths(sourceFiles, value); }
	void addInjectSourceFiles(in string[] value...) { add(injectSourceFiles, value); }
	void addCopyFiles(in string[] value...) { add(copyFiles, value); }
	void addExtraDependencyFiles(in string[] value...) { add(extraDependencyFiles, value); }
	void addVersions(in string[] value...) { add(versions, value); }
	void addDebugVersions(in string[] value...) { add(debugVersions, value); }
	void addVersionFilters(in string[] value...) { add(versionFilters, value); }
	void addDebugVersionFilters(in string[] value...) { add(debugVersionFilters, value); }
	void addImportPaths(in string[] value...) { add(importPaths, value); }
	void addStringImportPaths(in string[] value...) { add(stringImportPaths, value); }
	void prependStringImportPaths(in string[] value...) { prepend(stringImportPaths, value); }
	void addImportFiles(in string[] value...) { add(importFiles, value); }
	void addStringImportFiles(in string[] value...) { addSI(stringImportFiles, value); }
	void addPreGenerateCommands(in string[] value...) { add(preGenerateCommands, value, false); }
	void addPostGenerateCommands(in string[] value...) { add(postGenerateCommands, value, false); }
	void addPreBuildCommands(in string[] value...) { add(preBuildCommands, value, false); }
	void addPostBuildCommands(in string[] value...) { add(postBuildCommands, value, false); }
	void addPreRunCommands(in string[] value...) { add(preRunCommands, value, false); }
	void addPostRunCommands(in string[] value...) { add(postRunCommands, value, false); }
	void addEnvironments(in string[string] value) { add(environments, value); }
	void updateEnvironments(in string[string] value) { update(environments, value); }
	void addBuildEnvironments(in string[string] value) { add(buildEnvironments, value); }
	void updateBuildEnvironments(in string[string] value) { update(buildEnvironments, value); }
	void addRunEnvironments(in string[string] value) { add(runEnvironments, value); }
	void updateRunEnvironments(in string[string] value) { update(runEnvironments, value); }
	void addPreGenerateEnvironments(in string[string] value) { add(preGenerateEnvironments, value); }
	void updatePreGenerateEnvironments(in string[string] value) { update(preGenerateEnvironments, value); }
	void addPostGenerateEnvironments(in string[string] value) { add(postGenerateEnvironments, value); }
	void updatePostGenerateEnvironments(in string[string] value) { update(postGenerateEnvironments, value); }
	void addPreBuildEnvironments(in string[string] value) { add(preBuildEnvironments, value); }
	void updatePreBuildEnvironments(in string[string] value) { update(preBuildEnvironments, value); }
	void addPostBuildEnvironments(in string[string] value) { add(postBuildEnvironments, value); }
	void updatePostBuildEnvironments(in string[string] value) { update(postBuildEnvironments, value); }
	void addPreRunEnvironments(in string[string] value) { add(preRunEnvironments, value); }
	void updatePreRunEnvironments(in string[string] value) { update(preRunEnvironments, value); }
	void addPostRunEnvironments(in string[string] value) { add(postRunEnvironments, value); }
	void updatePostRunEnvironments(in string[string] value) { update(postRunEnvironments, value); }
	void addRequirements(in BuildRequirement[] value...) { foreach (v; value) this.requirements |= v; }
	void addRequirements(in BuildRequirements value) { this.requirements |= value; }
	void addOptions(in BuildOption[] value...) { foreach (v; value) this.options |= v; }
	void addOptions(in BuildOptions value) { this.options |= value; }
	void removeOptions(in BuildOption[] value...) { foreach (v; value) this.options &= ~v; }
	void removeOptions(in BuildOptions value) { this.options &= ~value; }

private:
	static auto filterDuplicates(T)(ref string[] arr, in T vals, bool noDuplicates = true)
	{
		return noDuplicates
			? vals.filter!(filtered => !arr.any!(item => item == filtered)).array
			: vals;
	}

	// Append vals to arr without adding duplicates.
	static void add(ref string[] arr, in string[] vals, bool noDuplicates = true)
	{
		// vals might contain duplicates, add each val individually
		foreach (val; vals)
			arr ~= filterDuplicates(arr, [val], noDuplicates);
	}
	// Append vals to AA
	static void add(ref string[string] aa, in string[string] vals)
	{
		// vals might contain duplicated keys, add each val individually
		foreach (key, val; vals)
			if (key !in aa)
				aa[key] = val;
	}
	// Update vals to AA
	static void update(ref string[string] aa, in string[string] vals)
	{
		// If there are duplicate keys, they will be ignored and overwritten.
		foreach (key, val; vals)
			aa[key] = val;
	}

	unittest
	{
		auto ary = ["-dip1000", "-vgc"];
		BuildSettings.add(ary, ["-dip1000", "-vgc"]);
		assert(ary == ["-dip1000", "-vgc"]);
		BuildSettings.add(ary, ["-dip1001", "-vgc"], false);
		assert(ary == ["-dip1000", "-vgc", "-dip1001", "-vgc"]);
		BuildSettings.add(ary, ["-dupflag", "-notdupflag", "-dupflag"]);
		assert(ary == ["-dip1000", "-vgc", "-dip1001", "-vgc", "-dupflag", "-notdupflag"]);
	}

	// Prepend arr by vals without adding duplicates.
	static void prepend(ref string[] arr, in string[] vals, bool noDuplicates = true)
	{
		import std.range : retro;
		// vals might contain duplicates, add each val individually
		foreach (val; vals.retro)
			arr = filterDuplicates(arr, [val], noDuplicates) ~ arr;
	}

	unittest
	{
		auto ary = ["-dip1000", "-vgc"];
		BuildSettings.prepend(ary, ["-dip1000", "-vgc"]);
		assert(ary == ["-dip1000", "-vgc"]);
		BuildSettings.prepend(ary, ["-dip1001", "-vgc"], false);
		assert(ary == ["-dip1001", "-vgc", "-dip1000", "-vgc"]);
		BuildSettings.prepend(ary, ["-dupflag", "-notdupflag", "-dupflag"]);
		assert(ary == ["-notdupflag", "-dupflag", "-dip1001", "-vgc", "-dip1000", "-vgc"]);
	}

	// add string import files (avoids file name duplicates in addition to path duplicates)
	static void addSI(ref string[] arr, in string[] vals)
	{
		bool[string] existing;
		foreach (v; arr) existing[NativePath(v).head.name] = true;
		foreach (v; vals) {
			auto s = NativePath(v).head.name;
			if (s !in existing) {
				existing[s] = true;
				arr ~= v;
			}
		}
	}

	unittest
	{
		auto ary = ["path/foo.txt"];
		BuildSettings.addSI(ary, ["path2/foo2.txt"]);
		assert(ary == ["path/foo.txt", "path2/foo2.txt"]);
		BuildSettings.addSI(ary, ["path2/foo.txt"]); // no duplicate basenames
		assert(ary == ["path/foo.txt", "path2/foo2.txt"]);
	}

	static bool pathMatch(string path, string pattern)
	{
		import std.functional : memoize;

		alias nativePath = memoize!((string stringPath) => NativePath(stringPath));

		return nativePath(path) == nativePath(pattern) || globMatch(path, pattern);
	}

	static void removeValuesFromArray(alias Match)(ref string[] arr, in string[] vals)
	{
		bool matches(string s)
		{
			return vals.any!(item => Match(s, item));
		}
		arr = arr.filter!(s => !matches(s)).array;
	}

	static void removePaths(ref string[] arr, in string[] vals)
	{
		removeValuesFromArray!(pathMatch)(arr, vals);
	}

	unittest
	{
		auto ary = ["path1", "root/path1", "root/path2", "root2/path1"];
		BuildSettings.removePaths(ary, ["path1"]);
		assert(ary == ["root/path1", "root/path2", "root2/path1"]);
		BuildSettings.removePaths(ary, ["*/path1"]);
		assert(ary == ["root/path2"]);
		BuildSettings.removePaths(ary, ["foo", "bar", "root/path2"]);
		assert(ary == []);
	}

	static void remove(ref string[] arr, in string[] vals)
	{
		removeValuesFromArray!((a, b) => a == b)(arr, vals);
	}

	unittest
	{
		import std.string : join;

		auto ary = ["path1", "root/path1", "root/path2", "root2/path1"];
		BuildSettings.remove(ary, ["path1"]);
		assert(ary == ["root/path1", "root/path2", "root2/path1"]);
		BuildSettings.remove(ary, ["root/path*"]);
		assert(ary == ["root/path1", "root/path2", "root2/path1"]);
		BuildSettings.removePaths(ary, ["foo", "root/path2", "bar", "root2/path1"]);
		assert(ary == ["root/path1"]);
		BuildSettings.remove(ary, ["root/path1", "foo"]);
		assert(ary == []);
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

		@ignore BitFlags!BuildRequirement values;
		this(BuildRequirement req) { values = req; }

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
	betterC = 1<<23,              /// Compile in betterC mode (-betterC)
	lowmem = 1<<24,               /// Compile in lowmem mode (-lowmem)

	// for internal usage
	_docs = 1<<25,                // Write ddoc to docs
	_ddox = 1<<26                 // Compile docs.json
}

	struct BuildOptions {
		import dub.internal.vibecompat.data.serialization : ignore;

		@ignore BitFlags!BuildOption values;
		this(BuildOption opt) { values = opt; }
		this(BitFlags!BuildOption v) { values = v; }

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
