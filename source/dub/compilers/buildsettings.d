/**
	Build settings definitions.

	Copyright: © 2013-2014 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.buildsettings;

import dub.internal.configy.attributes;
import dub.internal.logging;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.inet.path;
import dub.platform : BuildPlatform, matchesSpecification;
import dub.recipe.packagerecipe;

import std.array : appender, array;
import std.algorithm : filter, any, sort;
import std.path : globMatch;
import std.typecons : BitFlags;
import std.algorithm.iteration : uniq;
import std.exception : enforce;
import std.file;
import std.process : environment;
import std.range : empty, chain;

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
	string[] frameworks;
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
	string[] cImportPaths;
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
	@byName Flags!BuildRequirement requirements;
	@byName Flags!BuildOption options;

	BuildSettings dup() const {
		// Forwards to `add`, but `add` doesn't handle the first 5 fields
		// as they are not additive, hence the `tupleof` call.
		return typeof(return)(this.tupleof[0 .. /* dflags, not included */ 5])
			.add(this);
	}

	/**
	 * Merges $(LREF bs) onto `this` BuildSettings instance. This is called for
	 * sourceLibrary dependencies when they are included in the build to be
	 * merged into the root package build settings as well as configuring
	 * targets for different build types such as `release` or `unittest-cov`.
	 */
	ref BuildSettings add(in BuildSettings bs)
	{
		addDFlags(bs.dflags);
		addLFlags(bs.lflags);
		addLibs(bs.libs);
		addFrameworks(bs.frameworks);
		addLinkerFiles(bs.linkerFiles);
		addSourceFiles(bs.sourceFiles);
		addInjectSourceFiles(bs.injectSourceFiles);
		addCopyFiles(bs.copyFiles);
		addExtraDependencyFiles(bs.extraDependencyFiles);
		addVersions(bs.versions);
		addDebugVersions(bs.debugVersions);
		addVersionFilters(bs.versionFilters);
		addDebugVersionFilters(bs.debugVersionFilters);
		addImportPaths(bs.importPaths);
		addCImportPaths(bs.cImportPaths);
		addStringImportPaths(bs.stringImportPaths);
		addImportFiles(bs.importFiles);
		addStringImportFiles(bs.stringImportFiles);
		addPreGenerateCommands(bs.preGenerateCommands);
		addPostGenerateCommands(bs.postGenerateCommands);
		addPreBuildCommands(bs.preBuildCommands);
		addPostBuildCommands(bs.postBuildCommands);
		addPreRunCommands(bs.preRunCommands);
		addPostRunCommands(bs.postRunCommands);
		addEnvironments(bs.environments);
		addBuildEnvironments(bs.buildEnvironments);
		addRunEnvironments(bs.runEnvironments);
		addPreGenerateEnvironments(bs.preGenerateEnvironments);
		addPostGenerateEnvironments(bs.postGenerateEnvironments);
		addPreBuildEnvironments(bs.preBuildEnvironments);
		addPostBuildEnvironments(bs.postBuildEnvironments);
		addPreRunEnvironments(bs.preRunEnvironments);
		addPostRunEnvironments(bs.postRunEnvironments);
		addRequirements(bs.requirements);
		addOptions(bs.options);
		return this;
	}

	void addDFlags(in string[] value...) { dflags = chain(dflags, value.dup).uniq.array; }
	void prependDFlags(in string[] value...) { prepend(dflags, value); }
	void removeDFlags(in string[] value...) { remove(dflags, value); }
	void addLFlags(in string[] value...) { lflags ~= value; }
	void prependLFlags(in string[] value...) { prepend(lflags, value, false); }
	void addLibs(in string[] value...) { add(libs, value); }
	void addFrameworks(in string[] value...) { add(frameworks, value); }
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
	void addCImportPaths(in string[] value...) { add(cImportPaths, value); }
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
	void addRequirements(in Flags!BuildRequirement value) { this.requirements |= value; }
	void addOptions(in BuildOption[] value...) { foreach (v; value) this.options |= v; }
	void addOptions(in Flags!BuildOption value) { this.options |= value; }
	void removeOptions(in BuildOption[] value...) { foreach (v; value) this.options &= ~v; }
	void removeOptions(in Flags!BuildOption value) { this.options &= ~value; }

private:
	static auto filterDuplicates(T)(ref string[] arr, in T vals, bool noDuplicates = true)
	{
		return noDuplicates
			? vals.filter!(filtered => !arr.any!(item => item == filtered)).array
			: vals;
	}

	// Append `vals` to `arr` without adding duplicates.
	static void add(ref string[] arr, in string[] vals, bool noDuplicates = true)
	{
		// vals might contain duplicates, add each val individually
		foreach (val; vals)
			arr ~= filterDuplicates(arr, [val], noDuplicates);
	}
	// Append `vals` to `aa`
	static void add(ref string[string] aa, in string[string] vals)
	{
		// vals might contain duplicated keys, add each val individually
		foreach (key, val; vals)
			if (key !in aa)
				aa[key] = val;
	}
	// Update `vals` to `aa`
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

	// Prepend `arr` by `vals` without adding duplicates.
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
	cImportPaths      = 1<<8,
	stringImportPaths = 1<<9,
	options           = 1<<10,
	frameworks        = 1<<11,
	none = 0,
	commandLine = dflags|copyFiles,
	commandLineSeparate = commandLine|lflags,
	all = dflags|lflags|libs|sourceFiles|copyFiles|versions|debugVersions|importPaths|cImportPaths|stringImportPaths|options|frameworks,
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
	lowmem = 1<<24,               /// Compile in low-memory mode (-lowmem)
	coverageCTFE = 1<<25,         /// Enable code coverage analysis including at compile-time (-cov=ctfe)
	color = 1<<26,                /// Colorize output (-color)

	// for internal usage
	_docs = 1<<27,                // Write ddoc to docs
	_ddox = 1<<28,                // Compile docs.json
}

struct Flags (T) {
	import dub.internal.vibecompat.data.serialization : ignore;
	import dub.internal.vibecompat.data.json : Json;

	@ignore BitFlags!T values;

	public this(T opt) @safe pure nothrow @nogc
	{
		this.values = opt;
	}

	public this(BitFlags!T v) @safe pure nothrow @nogc
	{
		this.values = v;
	}

	alias values this;

	public Json toJson() const
	{
		import std.conv : to;
		import std.traits : EnumMembers;

		auto json = Json.emptyArray;

		static foreach (em; EnumMembers!T) {
			static if (em != 0) {
				if (values & em) {
					json ~= em.to!string;
				}
			}
		}

		return json;
	}

	public static Flags!T fromJson(Json json)
	{
		import std.conv : to;
		import std.exception : enforce;

		BitFlags!T flags;

		enforce(json.type == Json.Type.array, "Should be an array");
		foreach (jval; json) {
			flags |= jval.get!string.to!T;
		}

		return Flags!T(flags);
	}

	/**
	 * Reads a list of flags from a JSON/YAML document and converts them
	 * to our internal representation.
	 *
	 * Flags inside of dub code are stored as a `BitFlags`,
	 * but they are specified in the recipe using an array of their name.
	 * This routine handles the conversion from `string[]` to `BitFlags!T`.
	 */
	public static Flags!T fromConfig (scope ConfigParser p)
	{
		import dub.internal.configy.backend.node;
		import std.exception;
		import std.conv;

		auto seq = p.node.asSequence();
        enforce(seq !is null, "Should be a sequence");
		typeof(return) res;
		foreach (idx, entry; seq) {
            if (scope scalar = entry.asScalar())
                res |= scalar.str.to!T;
        }
		return res;
	}
}

/// Constructs a BuildSettings object from this template.
void getPlatformSettings(in BuildSettingsTemplate* this_, ref BuildSettings dst,
	in BuildPlatform platform, NativePath base_path) {
    getPlatformSettings(*this_, dst, platform, base_path);
}

/// Ditto
void getPlatformSettings(in BuildSettingsTemplate this_, ref BuildSettings dst,
	in BuildPlatform platform, NativePath base_path) {
	dst.targetType = this_.targetType;
	if (!this_.targetPath.empty) dst.targetPath = this_.targetPath;
	if (!this_.targetName.empty) dst.targetName = this_.targetName;
	if (!this_.workingDirectory.empty) dst.workingDirectory = this_.workingDirectory;
	if (!this_.mainSourceFile.empty) {
		auto p = NativePath(this_.mainSourceFile);
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
				if (!existsDirectory(path)) {
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

	// collect source files. Note: D source from 'sourcePaths' and C sources from 'cSourcePaths' are joint into 'sourceFiles'
	dst.addSourceFiles(collectFiles(this_.sourcePaths, "*.d"));
	dst.addSourceFiles(collectFiles(this_.cSourcePaths, "*.{c,i}"));
	auto sourceFiles = dst.sourceFiles.sort();

	// collect import files and remove sources
	import std.algorithm : copy, setDifference;

	auto importFiles =
		chain(collectFiles(this_.importPaths, "*.{d,di}"), collectFiles(this_.cImportPaths, "*.h"))
		.array()
		.sort();
	immutable nremoved = importFiles.setDifference(sourceFiles).copy(importFiles.release).length;
	importFiles = importFiles[0 .. $ - nremoved];
	dst.addImportFiles(importFiles.release);

	dst.addStringImportFiles(collectFiles(this_.stringImportPaths, "*"));

	this_.getPlatformSetting_!("dflags", "addDFlags")(dst, platform);
	this_.getPlatformSetting_!("lflags", "addLFlags")(dst, platform);
	this_.getPlatformSetting_!("libs", "addLibs")(dst, platform);
	this_.getPlatformSetting_!("frameworks", "addFrameworks")(dst, platform);
	this_.getPlatformSetting_!("sourceFiles", "addSourceFiles")(dst, platform);
	this_.getPlatformSetting_!("excludedSourceFiles", "removeSourceFiles")(dst, platform);
	this_.getPlatformSetting_!("injectSourceFiles", "addInjectSourceFiles")(dst, platform);
	this_.getPlatformSetting_!("copyFiles", "addCopyFiles")(dst, platform);
	this_.getPlatformSetting_!("extraDependencyFiles", "addExtraDependencyFiles")(dst, platform);
	this_.getPlatformSetting_!("versions", "addVersions")(dst, platform);
	this_.getPlatformSetting_!("debugVersions", "addDebugVersions")(dst, platform);
	this_.getPlatformSetting_!("versionFilters", "addVersionFilters")(dst, platform);
	this_.getPlatformSetting_!("debugVersionFilters", "addDebugVersionFilters")(dst, platform);
	this_.getPlatformSetting_!("importPaths", "addImportPaths")(dst, platform);
	this_.getPlatformSetting_!("cImportPaths", "addCImportPaths")(dst, platform);
	this_.getPlatformSetting_!("stringImportPaths", "addStringImportPaths")(dst, platform);
	this_.getPlatformSetting_!("preGenerateCommands", "addPreGenerateCommands")(dst, platform);
	this_.getPlatformSetting_!("postGenerateCommands", "addPostGenerateCommands")(dst, platform);
	this_.getPlatformSetting_!("preBuildCommands", "addPreBuildCommands")(dst, platform);
	this_.getPlatformSetting_!("postBuildCommands", "addPostBuildCommands")(dst, platform);
	this_.getPlatformSetting_!("preRunCommands", "addPreRunCommands")(dst, platform);
	this_.getPlatformSetting_!("postRunCommands", "addPostRunCommands")(dst, platform);
	this_.getPlatformSetting_!("environments", "addEnvironments")(dst, platform);
	this_.getPlatformSetting_!("buildEnvironments", "addBuildEnvironments")(dst, platform);
	this_.getPlatformSetting_!("runEnvironments", "addRunEnvironments")(dst, platform);
	this_.getPlatformSetting_!("preGenerateEnvironments", "addPreGenerateEnvironments")(dst, platform);
	this_.getPlatformSetting_!("postGenerateEnvironments", "addPostGenerateEnvironments")(dst, platform);
	this_.getPlatformSetting_!("preBuildEnvironments", "addPreBuildEnvironments")(dst, platform);
	this_.getPlatformSetting_!("postBuildEnvironments", "addPostBuildEnvironments")(dst, platform);
	this_.getPlatformSetting_!("preRunEnvironments", "addPreRunEnvironments")(dst, platform);
	this_.getPlatformSetting_!("postRunEnvironments", "addPostRunEnvironments")(dst, platform);
	this_.getPlatformSetting_!("buildRequirements", "addRequirements")(dst, platform);
	this_.getPlatformSetting_!("buildOptions", "addOptions")(dst, platform);
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

unittest
{
	import dub.internal.vibecompat.data.json;

	auto opts = Flags!BuildOption(BuildOption.debugMode | BuildOption.debugInfo | BuildOption.warningsAsErrors);
	const str = serializeToJsonString(opts);
	assert(str == `["debugMode","debugInfo","warningsAsErrors"]`);
	assert(deserializeJson!(typeof(opts))(str) == opts);
}

unittest
{
	import dub.internal.configy.easy;

	static struct Config
	{
		Flags!BuildRequirement flags;
	}

	auto c = parseConfigString!Config(`
{
	"flags": [ "allowWarnings", "noDefaultFlags", "disallowInlining" ]
}
`, __FILE__);
	assert(c.flags.allowWarnings);
	c.flags.allowWarnings = false;
	assert(c.flags.noDefaultFlags);
	c.flags.noDefaultFlags = false;
	assert(c.flags.disallowInlining);
	c.flags.disallowInlining = false;
	assert(c.flags == c.flags.init);
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
enum Flags!BuildOption inheritedBuildOptions =
	BuildOption.debugMode | BuildOption.releaseMode
	| BuildOption.coverage | BuildOption.coverageCTFE | BuildOption.debugInfo | BuildOption.debugInfoC
	| BuildOption.alwaysStackFrame | BuildOption.stackStomping | BuildOption.inline
	| BuildOption.noBoundsCheck | BuildOption.profile | BuildOption.ignoreUnknownPragmas
	| BuildOption.syntaxOnly | BuildOption.warnings	| BuildOption.warningsAsErrors
	| BuildOption.ignoreDeprecations | BuildOption.deprecationWarnings
	| BuildOption.deprecationErrors | BuildOption.property | BuildOption.profileGC
	| BuildOption.pic;

deprecated("Use `Flags!BuildOption` instead")
public alias BuildOptions = Flags!BuildOption;

deprecated("Use `Flags!BuildRequirement` instead")
public alias BuildRequirements = Flags!BuildRequirement;
