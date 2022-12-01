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

import dub.internal.configy.Attributes;

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
string[] getSubPackagePath(string package_name) @safe pure
{
	return package_name.split(":");
}

/**
	Returns the name of the top level package for a given (sub) package name.

	In case of a top level package, the qualified name is returned unmodified.
*/
string getBasePackageName(string package_name) @safe pure
{
	return package_name.findSplit(":")[0];
}

/**
	Returns the qualified sub package part of the given package name.

	This is the part of the package name excluding the base package
	name. See also $(D getBasePackageName).
*/
string getSubPackageName(string package_name) @safe pure
{
	return package_name.findSplit(":")[2];
}

@safe unittest
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
	/**
	 * Name of the package, used to uniquely identify the package.
	 *
	 * This field is the only mandatory one.
	 * Must be comprised of only lower case ASCII alpha-numeric characters,
	 * "-" or "_".
	 */
	string name;

	/// Brief description of the package.
	@Optional string description;

	/// URL of the project website
	@Optional string homepage;

	/**
	 * List of project authors
	 *
	 * the suggested format is either:
	 * "Peter Parker"
	 * or
	 * "Peter Parker <pparker@example.com>"
	 */
	@Optional string[] authors;

	/// Copyright declaration string
	@Optional string copyright;

	/// License(s) under which the project can be used
	@Optional string license;

	/// Set of version requirements for DUB, compilers and/or language frontend.
	@Optional ToolchainRequirements toolchainRequirements;

	/**
	 * Speficies an optional list of build configurations
	 *
	 * By default, the first configuration present in the package recipe
	 * will be used, except for special configurations (e.g. "unittest").
	 * A specific configuration can be chosen from the command line using
	 * `--config=name` or `-c name`. A package can select a specific
	 * configuration in one of its dependency by using the `subConfigurations`
	 * build setting.
	 * Build settings defined at the top level affect all configurations.
	 */
	@Optional @Key("name") ConfigurationInfo[] configurations;

	/**
	 * Defines additional custom build types or overrides the default ones
	 *
	 * Build types can be selected from the command line using `--build=name`
	 * or `-b name`. The default build type is `debug`.
	 */
	@Optional BuildSettingsTemplate[string] buildTypes;

	/**
	 * Build settings influence the command line arguments and options passed
	 * to the compiler and linker.
	 *
	 * All build settings can be present at the top level, and are optional.
	 * Build settings can also be found in `configurations`.
	 */
	@Optional BuildSettingsTemplate buildSettings;
	alias buildSettings this;

	/**
	 * Specifies a list of command line flags usable for controlling
	 * filter behavior for `--build=ddox` [experimental]
	 */
	@Optional @Name("-ddoxFilterArgs") string[] ddoxFilterArgs;

	/// Specify which tool to use with `--build=ddox` (experimental)
	@Optional @Name("-ddoxTool") string ddoxTool;

	/**
	 * Sub-packages path or definitions
	 *
	 * Sub-packages allow to break component of a large framework into smaller
	 * packages. In the recipe file, subpackages entry can take one of two forms:
	 * either the path to a sub-folder where a recipe file exists,
	 * or an object of the same format as a recipe file (or `PackageRecipe`).
	 */
	@Optional SubPackage[] subPackages;

	/// Usually unused by users, this is set by dub automatically
	@Optional @Name("version") string version_;

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

	/**
	 * Given a YAML parser, recurses into `recipe` or use `path`
	 * depending on the node type.
	 *
	 * Two formats are supported for `subpackages`: a string format,
	 * which is just the path to the subpackage, and embedding the
	 * full subpackage recipe into the parent package recipe.
	 *
	 * To support such a dual syntax, Configy requires the use
	 * of a `fromYAML` method, as it exposes the underlying format.
	 */
	static SubPackage fromYAML (scope ConfigParser!SubPackage p)
	{
		import dub.internal.dyaml.node;

		if (p.node.nodeID == NodeID.mapping)
			return SubPackage(null, p.parseAs!PackageRecipe);
		else
			return SubPackage(p.parseAs!string);
	}
}

/// Describes minimal toolchain requirements
struct ToolchainRequirements
{
	import std.typecons : Tuple, tuple;

	// TODO: We can remove `@Optional` once bosagora/configy#30 is resolved,
	// currently it fails because `Dependency.opCmp` is not CTFE-able.

	/// DUB version requirement
	@Optional @converter((scope ConfigParser!Dependency p) => p.node.as!string.parseDependency)
	Dependency dub = Dependency.any;
	/// D front-end version requirement
	@Optional @converter((scope ConfigParser!Dependency p) => p.node.as!string.parseDMDDependency)
	Dependency frontend = Dependency.any;
	/// DMD version requirement
	@Optional @converter((scope ConfigParser!Dependency p) => p.node.as!string.parseDMDDependency)
	Dependency dmd = Dependency.any;
	/// LDC version requirement
	@Optional @converter((scope ConfigParser!Dependency p) => p.node.as!string.parseDependency)
	Dependency ldc = Dependency.any;
	/// GDC version requirement
	@Optional @converter((scope ConfigParser!Dependency p) => p.node.as!string.parseDependency)
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
	@Optional string[] platforms;
	@Optional BuildSettingsTemplate buildSettings;
	alias buildSettings this;

	/**
	 * Equivalent to the default constructor, used by Configy
	 */
	this(string name, string[] p, BuildSettingsTemplate build_settings)
		@safe pure nothrow @nogc
	{
		this.name = name;
		this.platforms = p;
		this.buildSettings = build_settings;
	}

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

/**
 * A dependency with possible `BuildSettingsTemplate`
 *
 * Currently only `dflags` is taken into account, but the parser accepts any
 * value that is in `BuildSettingsTemplate`.
 * This feature was originally introduced to support `-preview`, as setting
 * a `-preview` in `dflags` does not propagate down to dependencies.
 */
public struct RecipeDependency
{
	/// The dependency itself
	public Dependency dependency;

	/// Additional dflags, if any
	public BuildSettingsTemplate settings;

	/// Convenience alias as most uses just want to deal with the `Dependency`
	public alias dependency this;

	/**
	 * Read a `Dependency` and `BuildSettingsTemplate` from the config file
	 *
	 * Required to support both short and long form
	 */
	static RecipeDependency fromYAML (scope ConfigParser!RecipeDependency p)
	{
		import dub.internal.dyaml.node;

		if (p.node.nodeID == NodeID.scalar) {
			auto d = YAMLFormat(p.node.as!string);
			return RecipeDependency(d.toDependency());
		}
		auto d = p.parseAs!YAMLFormat;
		return RecipeDependency(d.toDependency(), d.settings);
	}

	/// In-file representation of a dependency as specified by the user
	private struct YAMLFormat
	{
		@Name("version") @Optional string version_;
		@Optional string path;
		@Optional string repository;
		bool optional;
		@Name("default") bool default_;

		@Optional BuildSettingsTemplate settings;
		alias settings this;

		/**
		 * Used by Configy to provide rich error message when parsing.
		 *
		 * Exceptions thrown from `validate` methods will be wrapped with field/file
		 * informations and rethrown from Configy, providing the user
		 * with the location of the configuration that triggered the error.
		 */
		public void validate () const
		{
			enforce(this.optional || !this.default_,
				"Setting default to 'true' has no effect if 'optional' is not set");
			enforce(this.version_.length || this.path.length || this.repository.length,
				"Need to provide one of the following fields: 'version', 'path', or 'repository'");

			enforce(!this.path.length || !this.repository.length,
				"Cannot provide a 'path' dependency if a repository dependency is used");
			enforce(!this.repository.length || this.version_.length,
				"Need to provide a commit hash in 'version' field with 'repository' dependency");

			// Need to deprecate this as it's fairly common
			version (none) {
				enforce(!this.path.length || !this.version_.length,
					"Cannot provide a 'path' dependency if a 'version' dependency is used");
			}
		}

		/// Turns this struct into a `Dependency`
		public Dependency toDependency () const
		{
			auto result = () {
				if (this.path.length)
					return Dependency(NativePath(this.path));
				if (this.repository.length)
					return Dependency(Repository(this.repository, this.version_));
				return Dependency(VersionRange.fromString(this.version_));
			}();
			result.optional = this.optional;
			result.default_ = this.default_;
			return result;
		}
	}
}

/// Type used to avoid a breaking change when `Dependency[string]`
/// was changed to `RecipeDependency[string]`
package struct RecipeDependencyAA
{
	/// The underlying data, `public` as `alias this` to `private` field doesn't
	/// always work.
	public RecipeDependency[string] data;

	/// Expose base function, e.g. `clear`
	alias data this;

	/// Supports assignment from a `RecipeDependency` (used in the parser)
	public void opIndexAssign(RecipeDependency dep, string key)
		pure nothrow
	{
		this.data[key] = dep;
	}

	/// Supports assignment from a `Dependency`, used in user code mostly
	public void opIndexAssign(Dependency dep, string key)
		pure nothrow
	{
		this.data[key] = RecipeDependency(dep);
	}

	/// Configy doesn't like `alias this` to an AA
	static RecipeDependencyAA fromYAML (scope ConfigParser!RecipeDependencyAA p)
	{
		return RecipeDependencyAA(p.parseAs!(typeof(this.data)));
	}
}

/// This keeps general information about how to build a package.
/// It contains functions to create a specific BuildSetting, targeted at
/// a certain BuildPlatform.
struct BuildSettingsTemplate {
	@Optional RecipeDependencyAA dependencies;
	@Optional string systemDependencies;
	@Optional TargetType targetType = TargetType.autodetect;
	@Optional string targetPath;
	@Optional string targetName;
	@Optional string workingDirectory;
	@Optional string mainSourceFile;
	@Optional string[string] subConfigurations;
	@StartsWith("dflags") string[][string] dflags;
	@StartsWith("lflags") string[][string] lflags;
	@StartsWith("libs") string[][string] libs;
	@StartsWith("sourceFiles") string[][string] sourceFiles;
	@StartsWith("sourcePaths") string[][string] sourcePaths;
	@StartsWith("cSourcePaths") string[][string] cSourcePaths;
	@StartsWith("excludedSourceFiles") string[][string] excludedSourceFiles;
	@StartsWith("injectSourceFiles") string[][string] injectSourceFiles;
	@StartsWith("copyFiles") string[][string] copyFiles;
	@StartsWith("extraDependencyFiles") string[][string] extraDependencyFiles;
	@StartsWith("versions") string[][string] versions;
	@StartsWith("debugVersions") string[][string] debugVersions;
	@StartsWith("versionFilters") string[][string] versionFilters;
	@StartsWith("debugVersionFilters") string[][string] debugVersionFilters;
	@StartsWith("importPaths") string[][string] importPaths;
	@StartsWith("stringImportPaths") string[][string] stringImportPaths;
	@StartsWith("preGenerateCommands") string[][string] preGenerateCommands;
	@StartsWith("postGenerateCommands") string[][string] postGenerateCommands;
	@StartsWith("preBuildCommands") string[][string] preBuildCommands;
	@StartsWith("postBuildCommands") string[][string] postBuildCommands;
	@StartsWith("preRunCommands") string[][string] preRunCommands;
	@StartsWith("postRunCommands") string[][string] postRunCommands;
	@StartsWith("environments") string[string][string] environments;
	@StartsWith("buildEnvironments")string[string][string] buildEnvironments;
	@StartsWith("runEnvironments") string[string][string] runEnvironments;
	@StartsWith("preGenerateEnvironments") string[string][string] preGenerateEnvironments;
	@StartsWith("postGenerateEnvironments") string[string][string] postGenerateEnvironments;
	@StartsWith("preBuildEnvironments") string[string][string] preBuildEnvironments;
	@StartsWith("postBuildEnvironments") string[string][string] postBuildEnvironments;
	@StartsWith("preRunEnvironments") string[string][string] preRunEnvironments;
	@StartsWith("postRunEnvironments") string[string][string] postRunEnvironments;

	@StartsWith("buildRequirements") @Optional
	Flags!BuildRequirement[string] buildRequirements;
	@StartsWith("buildOptions") @Optional
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
		dst.addSourceFiles(collectFiles(cSourcePaths, "*.c"));
		auto sourceFiles = dst.sourceFiles.sort();

 		// collect import files and remove sources
		import std.algorithm : copy, setDifference;

		auto importFiles = collectFiles(importPaths, "*.{d,di,h}").sort();
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
			Flags!BuildOption all_options;
			foreach (flags; this.dflags) all_dflags ~= flags;
			foreach (options; this.buildOptions) all_options |= options;
			.warnOnSpecialCompilerFlags(all_dflags, all_options, package_name, config_name);
		}
	}
}

package(dub) void checkPlatform(const scope ref ToolchainRequirements tr, BuildPlatform platform, string package_name)
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
			platform.compiler, platform.compilerVersion, package_name,
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
			package_name, platform.compiler, compilerspec
		)
	);

	enforce(tr.frontend.matches(dmdLikeVersionToSemverLike(platform.frontendVersionString)),
		format(
			"Installed %s-%s with frontend %s does not comply with %s frontend requirement: %s\n" ~
			"Please consider upgrading your installation.",
			platform.compiler, platform.compilerVersion,
			platform.frontendVersionString, package_name, tr.frontend
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
	import dub.internal.dyaml.stdsumtype;
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

/**
 * Edit all dependency names from `:foo` to `name:foo`.
 *
 * TODO: Remove the special case in the parser and remove this hack.
 */
package void fixDependenciesNames (T) (string root, ref T aggr) nothrow
{
	static foreach (idx, FieldRef; T.tupleof) {
		static if (is(immutable typeof(FieldRef) == immutable RecipeDependencyAA)) {
			string[] toReplace;
			foreach (key; aggr.tupleof[idx].byKey)
				if (key.length && key[0] == ':')
					toReplace ~= key;
			foreach (k; toReplace) {
				aggr.tupleof[idx][root ~ k] = aggr.tupleof[idx][k];
				aggr.tupleof[idx].data.remove(k);
			}
		}
		else static if (is(typeof(FieldRef) == struct))
			fixDependenciesNames(root, aggr.tupleof[idx]);
	}
}
