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

import dub.internal.configy.attributes;
import dub.internal.vibecompat.inet.path;

import std.algorithm : findSplit, sort;
import std.array : join, split;
import std.exception : enforce;
import std.range;

deprecated("Use `dub.compilers.buildsettings : getPlatformSettings`")
public import dub.compilers.buildsettings : getPlatformSettings;

/**
	Returns the individual parts of a qualified package name.

	Sub qualified package names are lists of package names separated by ":". For
	example, "packa:packb:packc" references a package named "packc" that is a
	sub package of "packb", which in turn is a sub package of "packa".
*/
deprecated("This function is not supported as subpackages cannot be nested")
string[] getSubPackagePath(string package_name) @safe pure
{
	return package_name.split(":");
}

deprecated @safe unittest
{
	assert(getSubPackagePath("packa:packb:packc") == ["packa", "packb", "packc"]);
	assert(getSubPackagePath("pack") == ["pack"]);
}

/**
	Returns the name of the top level package for a given (sub) package name of
	format `"basePackageName"` or `"basePackageName:subPackageName"`.

	In case of a top level package, the qualified name is returned unmodified.
*/
deprecated("Use `dub.dependency : PackageName(arg).main` instead")
string getBasePackageName(string package_name) @safe pure
{
	return package_name.findSplit(":")[0];
}

/**
	Returns the qualified sub package part of the given package name of format
	`"basePackageName:subPackageName"`, or empty string if none.

	This is the part of the package name excluding the base package
	name. See also $(D getBasePackageName).
*/
deprecated("Use `dub.dependency : PackageName(arg).sub` instead")
string getSubPackageName(string package_name) @safe pure
{
	return package_name.findSplit(":")[2];
}

deprecated @safe unittest
{
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
	 * Specifies an optional list of build configurations
	 *
	 * By default, the first configuration present in the package recipe
	 * will be used, except for special configurations (e.g. "unittest").
	 * A specific configuration can be chosen from the command line using
	 * `--config=name` or `-c name`. A package can select a specific
	 * configuration in one of its dependency by using the `subConfigurations`
	 * build setting.
	 * Build settings defined at the top level affect all configurations.
	 */
	@Optional ConfigurationInfo[] configurations;

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
	 * packages. In the recipe file, sub-packages entry can take one of two forms:
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
	 * Two formats are supported for sub-packages: a string format,
	 * which is just the path to the sub-package, and embedding the
	 * full sub-package recipe into the parent package recipe.
	 *
	 * To support such a dual syntax, Configy requires the use
	 * of a `fromConfig` method, as it exposes the underlying format.
	 */
	static SubPackage fromConfig (scope ConfigParser p)
	{
		import dub.internal.configy.backend.node;

		if (p.node.type == Node.Type.Mapping)
			return SubPackage(null, p.parseAs!PackageRecipe);
		else
			return SubPackage(p.parseAs!string);
	}
}

/// Describes minimal toolchain requirements
struct ToolchainRequirements
{
	import std.typecons : Tuple, tuple;

	private static struct JSONFormat {
		private static struct VersionRangeC (bool asDMD) {
			public VersionRange range;
			alias range this;
			public static VersionRangeC fromConfig (scope ConfigParser parser) {
				scope scalar = parser.node.asScalar();
				enforce(scalar !is null, "Node should be a scalar (string)");
				static if (asDMD)
					return typeof(return)(scalar.str.parseDMDDependency);
				else
					return typeof(return)(scalar.str.parseVersionRange);
			}
		}
		VersionRangeC!false dub = VersionRangeC!false(VersionRange.Any);
		VersionRangeC!true frontend = VersionRangeC!true(VersionRange.Any);
		VersionRangeC!true dmd = VersionRangeC!true(VersionRange.Any);
		VersionRangeC!false ldc = VersionRangeC!false(VersionRange.Any);
		VersionRangeC!false gdc = VersionRangeC!false(VersionRange.Any);
	}

	/// DUB version requirement
	VersionRange dub = VersionRange.Any;
	/// D front-end version requirement
	VersionRange frontend = VersionRange.Any;
	/// DMD version requirement
	VersionRange dmd = VersionRange.Any;
	/// LDC version requirement
	VersionRange ldc = VersionRange.Any;
	/// GDC version requirement
	VersionRange gdc = VersionRange.Any;

	///
	public static ToolchainRequirements fromConfig (scope ConfigParser parser) {
		return ToolchainRequirements(parser.parseAs!(JSONFormat).tupleof);
	}

	/** Get the list of supported compilers.

		Returns:
			An array of couples of compiler name and compiler requirement
	*/
	@property Tuple!(string, VersionRange)[] supportedCompilers() const
	{
		Tuple!(string, VersionRange)[] res;
		if (dmd != VersionRange.Invalid) res ~= Tuple!(string, VersionRange)("dmd", dmd);
		if (ldc != VersionRange.Invalid) res ~= Tuple!(string, VersionRange)("ldc", ldc);
		if (gdc != VersionRange.Invalid) res ~= Tuple!(string, VersionRange)("gdc", gdc);
		return res;
	}

	bool empty()
	const {
		import std.algorithm.searching : all;
		return only(dub, frontend, dmd, ldc, gdc)
			.all!(r => r == VersionRange.Any);
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
	static RecipeDependency fromConfig (scope ConfigParser p)
	{
		if (scope scalar = p.node.asScalar()) {
			auto d = YAMLFormat(scalar.str);
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
		 * information and rethrown from Configy, providing the user
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
	static RecipeDependencyAA fromConfig (scope ConfigParser p)
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
	@StartsWith("frameworks") string[][string] frameworks;
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
	@StartsWith("cImportPaths") string[][string] cImportPaths;
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

    deprecated("This function is not intended for public consumption")
    void getPlatformSetting(string name, string addname)(ref BuildSettings dst,
        in BuildPlatform platform) const {
        this.getPlatformSetting_!(name, addname)(dst, platform);
    }

	package(dub) void getPlatformSetting_(string name, string addname)(
		ref BuildSettings dst, in BuildPlatform platform) const {
		foreach (suffix, values; __traits(getMember, this, name)) {
			if (platform.matchesSpecification(suffix) )
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
	import std.algorithm.iteration : map;
	import std.format : format;

	Version compilerver;
	VersionRange compilerspec;

	switch (platform.compiler) {
		default:
			compilerspec = VersionRange.Any;
			compilerver = Version.minRelease;
			break;
		case "dmd":
			compilerspec = tr.dmd;
			compilerver = platform.compilerVersion.length
				? Version(dmdLikeVersionToSemverLike(platform.compilerVersion))
				: Version.minRelease;
			break;
		case "ldc":
			compilerspec = tr.ldc;
			compilerver = platform.compilerVersion.length
				? Version(platform.compilerVersion)
				: Version.minRelease;
			break;
		case "gdc":
			compilerspec = tr.gdc;
			compilerver = platform.compilerVersion.length
				? Version(platform.compilerVersion)
				: Version.minRelease;
			break;
	}

	enforce(compilerspec != VersionRange.Invalid,
		format(
			"Installed %s %s is not supported by %s. Supported compiler(s):\n%s",
			platform.compiler, platform.compilerVersion, package_name,
			tr.supportedCompilers.map!((cs) {
				auto str = "  - " ~ cs[0];
				if (cs[1] != VersionRange.Any) str ~= ": " ~ cs[1].toString();
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

	enforce(tr.frontend.matches(Version(dmdLikeVersionToSemverLike(platform.frontendVersionString))),
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
		case "dub": req.dub = parseVersionRange(value); break;
		case "frontend": req.frontend = parseDMDDependency(value); break;
		case "ldc": req.ldc = parseVersionRange(value); break;
		case "gdc": req.gdc = parseVersionRange(value); break;
		case "dmd": req.dmd = parseDMDDependency(value); break;
	}
	return true;
}

private VersionRange parseVersionRange(string dep)
{
	if (dep == "no") return VersionRange.Invalid;
	return VersionRange.fromString(dep);
}

private VersionRange parseDMDDependency(string dep)
{
	import std.algorithm : map, splitter;
	import std.array : join;

	if (dep == "no") return VersionRange.Invalid;
	// `dmdLikeVersionToSemverLike` does not handle this, VersionRange does
	if (dep == "*")	 return VersionRange.Any;
	return VersionRange.fromString(dep
		.splitter(' ')
		.map!(r => dmdLikeVersionToSemverLike(r))
		.join(' '));
}

private T clone(T)(ref const(T) val)
{
	import dub.internal.dyaml.stdsumtype;
	import std.traits : isSomeString, isDynamicArray, isAssociativeArray, isBasicType, ValueType;

	static if (is(T == immutable)) return val;
	else static if (isBasicType!T || is(T Base == enum) && isBasicType!Base) {
		return val;
	} else static if (isDynamicArray!T) {
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

/**
 * Edit all dependency names from `:foo` to `name:foo`.
 *
 * TODO: Remove the special case in the parser and remove this hack.
 */
package void fixDependenciesNames (T) (string root, ref T aggr)
{
	static foreach (idx, FieldRef; T.tupleof)
        fixFieldDependenciesNames(root, aggr.tupleof[idx]);
}

/// Ditto
private void fixFieldDependenciesNames (Field) (string root, ref Field field)
{
    static if (is(immutable Field == immutable RecipeDependencyAA)) {
        string[] toReplace;
        foreach (key; field.byKey)
            if (key.length && key[0] == ':')
                toReplace ~= key;
        foreach (k; toReplace) {
            field[root ~ k] = field[k];
            field.data.remove(k);
        }
    } else static if (is(Field == struct))
        fixDependenciesNames(root, field);
    else static if (is(Field : Elem[], Elem))
        foreach (ref entry; field)
            fixFieldDependenciesNames(root, entry);
    else static if (is(Field : Value[Key], Value, Key))
        foreach (key, ref value; field)
            fixFieldDependenciesNames(root, value);
}

/**
	Turn a DMD-like version (e.g. 2.082.1) into a SemVer-like version (e.g. 2.82.1).
    The function accepts a dependency operator prefix and some text postfix.
    Prefix and postfix are returned verbatim.
	Params:
		ver	=	version string, possibly with a dependency operator prefix and some
				test postfix.
	Returns:
		A Semver compliant string
*/
private string dmdLikeVersionToSemverLike(string ver)
{
	import std.algorithm : countUntil, joiner, map, skipOver, splitter;
	import std.array : join, split;
	import std.ascii : isDigit;
	import std.conv : text;
	import std.exception : enforce;
	import std.functional : not;
	import std.range : padRight;

	const start = ver.countUntil!isDigit;
	enforce(start != -1, "Invalid semver: "~ver);
	const prefix = ver[0 .. start];
	ver = ver[start .. $];

	const end = ver.countUntil!(c => !c.isDigit && c != '.');
	const postfix = end == -1 ? null : ver[end .. $];
	auto verStr = ver[0 .. $-postfix.length];

	auto comps = verStr
		.splitter(".")
		.map!((a) { if (a.length > 1) a.skipOver("0"); return a;})
		.padRight("0", 3);

	return text(prefix, comps.joiner("."), postfix);
}

///
unittest {
	assert(dmdLikeVersionToSemverLike("2.082.1") == "2.82.1");
	assert(dmdLikeVersionToSemverLike("2.082.0") == "2.82.0");
	assert(dmdLikeVersionToSemverLike("2.082") == "2.82.0");
	assert(dmdLikeVersionToSemverLike("~>2.082") == "~>2.82.0");
	assert(dmdLikeVersionToSemverLike("~>2.082-beta1") == "~>2.82.0-beta1");
	assert(dmdLikeVersionToSemverLike("2.4.6") == "2.4.6");
	assert(dmdLikeVersionToSemverLike("2.4.6-alpha12") == "2.4.6-alpha12");
}

// Test for ToolchainRequirements as the implementation is custom
unittest {
    import dub.internal.configy.easy : parseConfigString;

    immutable content = `{ "name": "mytest",
    "toolchainRequirements": {
        "frontend": ">=2.089",
        "dmd":      ">=2.109",
        "dub":      "~>1.1",
        "gdc":      "no",
    }}`;

    auto s = parseConfigString!PackageRecipe(content, "/dev/null");
    assert(s.toolchainRequirements.frontend.toString() == ">=2.89.0");
    assert(s.toolchainRequirements.dmd.toString() == ">=2.109.0");
    assert(s.toolchainRequirements.dub.toString() == "~>1.1");
    assert(s.toolchainRequirements.gdc == VersionRange.Invalid);

}
