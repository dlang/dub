/**
	Contains high-level functionality for working with packages.

	Copyright: © 2012-2013 Matthias Dondorff, © 2012-2016 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff, Sönke Ludwig, Martin Nowak, Nick Sabalausky
*/
module dub.package_;

public import dub.recipe.packagerecipe;

import dub.compilers.compiler;
import dub.dependency;
import dub.description;
import dub.recipe.json;
import dub.recipe.sdl;

import dub.internal.logging;
import dub.internal.utils;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.path;

import dub.internal.configy.Read : StrictMode;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.range;
import std.string;
import std.typecons : Nullable;


/// Lists the supported package recipe formats.
enum PackageFormat {
	json, /// JSON based, using the ".json" file extension
	sdl   /// SDLang based, using the ".sdl" file extension
}

struct FilenameAndFormat {
	string filename;
	PackageFormat format;
}

/// Supported package descriptions in decreasing order of preference.
static immutable FilenameAndFormat[] packageInfoFiles = [
	{"dub.json", PackageFormat.json},
	{"dub.sdl", PackageFormat.sdl},
	{"package.json", PackageFormat.json}
];

/// Returns a list of all recognized package recipe file names in descending order of precedence.
deprecated("Open an issue if this is needed")
@property string[] packageInfoFilenames() { return packageInfoFiles.map!(f => cast(string)f.filename).array; }

/// Returns the default package recile file name.
@property string defaultPackageFilename() { return packageInfoFiles[0].filename; }

/// All built-in build type names except for the special `$DFLAGS` build type.
/// Has the default build type (`debug`) as first index.
static immutable string[] builtinBuildTypes = [
	"debug",
	"plain",
	"release",
	"release-debug",
	"release-nobounds",
	"unittest",
	"profile",
	"profile-gc",
	"docs",
	"ddox",
	"cov",
	"cov-ctfe",
	"unittest-cov",
	"unittest-cov-ctfe",
	"syntax"
];

/**	Represents a package, including its sub packages.
*/
class Package {
	// `package` visibility as it is set from the PackageManager
	package NativePath m_infoFile;
	private {
		NativePath m_path;
		PackageRecipe m_info;
		PackageRecipe m_rawRecipe;
		Package m_parentPackage;
	}

	/** Constructs a `Package` using an in-memory package recipe.

		Params:
			json_recipe = The package recipe in JSON format
			recipe = The package recipe in generic format
			root = The directory in which the package resides (if any).
			parent = Reference to the parent package, if the new package is a
				sub package.
			version_override = Optional version to associate to the package
				instead of the one declared in the package recipe, or the one
				determined by invoking the VCS (GIT currently).
	*/
	deprecated("Provide an already parsed PackageRecipe instead of a JSON object")
	this(Json json_recipe, NativePath root = NativePath(), Package parent = null, string version_override = "")
	{
		import dub.recipe.json;

		PackageRecipe recipe;
		parseJson(recipe, json_recipe, parent ? parent.name : null);
		this(recipe, root, parent, version_override);
	}
	/// ditto
	this(PackageRecipe recipe, NativePath root = NativePath(), Package parent = null, string version_override = "")
	{
		// save the original recipe
		m_rawRecipe = recipe.clone;

		if (!version_override.empty)
			recipe.version_ = version_override;

		// try to run git to determine the version of the package if no explicit version was given
		if (recipe.version_.length == 0 && !parent) {
			try recipe.version_ = determineVersionFromSCM(root);
			catch (Exception e) logDebug("Failed to determine version by SCM: %s", e.msg);

			if (recipe.version_.length == 0) {
				logDiagnostic("Note: Failed to determine version of package %s at %s. Assuming ~master.", recipe.name, this.path.toNativeString());
				// TODO: Assume unknown version here?
				// recipe.version_ = Version.unknown.toString();
				recipe.version_ = Version.masterBranch.toString();
			} else logDiagnostic("Determined package version using GIT: %s %s", recipe.name, recipe.version_);
		}

		m_parentPackage = parent;
		m_path = root;
		m_path.endsWithSlash = true;

		// use the given recipe as the basis
		m_info = recipe;

		checkDubRequirements();
		fillWithDefaults();
		mutuallyExcludeMainFiles();
	}

	/** Searches the given directory for package recipe files.

		Params:
			directory = The directory to search

		Returns:
			Returns the full path to the package file, if any was found.
			Otherwise returns an empty path.
	*/
	deprecated("Use `PackageManager.findPackageFile`")
	static NativePath findPackageFile(NativePath directory)
	{
		foreach (file; packageInfoFiles) {
			auto filename = directory ~ file.filename;
			if (existsFile(filename)) return filename;
		}
		return NativePath.init;
	}

	/** Constructs a `Package` using a package that is physically present on the local file system.

		Params:
			root = The directory in which the package resides.
			recipe_file = Optional path to the package recipe file. If left
				empty, the `root` directory will be searched for a recipe file.
			parent = Reference to the parent package, if the new package is a
				sub package.
			version_override = Optional version to associate to the package
				instead of the one declared in the package recipe, or the one
				determined by invoking the VCS (GIT currently).
			mode = Whether to issue errors, warning, or ignore unknown keys in dub.json
	*/
	deprecated("Use `PackageManager.getOrLoadPackage` instead of loading packages directly")
	static Package load(NativePath root, NativePath recipe_file = NativePath.init,
		Package parent = null, string version_override = "",
		StrictMode mode = StrictMode.Ignore)
	{
		import dub.recipe.io;

		if (recipe_file.empty) recipe_file = findPackageFile(root);

		enforce(!recipe_file.empty,
			"No package file found in %s, expected one of %s"
				.format(root.toNativeString(),
					packageInfoFiles.map!(f => cast(string)f.filename).join("/")));

		auto recipe = readPackageRecipe(recipe_file, parent ? parent.name : null, mode);

		auto ret = new Package(recipe, root, parent, version_override);
		ret.m_infoFile = recipe_file;
		return ret;
	}

	/** Returns the qualified name of the package.

		The qualified name includes any possible parent package if this package
		is a sub package.
	*/
	@property string name()
	const {
		if (m_parentPackage) return m_parentPackage.name ~ ":" ~ m_info.name;
		else return m_info.name;
	}

	/** Returns the directory in which the package resides.

		Note that this can be empty for packages that are not stored in the
		local file system.
	*/
	@property NativePath path() const { return m_path; }


	/** Accesses the version associated with this package.

		Note that this is a shortcut to `this.recipe.version_`.
	*/
	@property Version version_() const { return m_parentPackage ? m_parentPackage.version_ : Version(m_info.version_); }
	/// ditto
	@property void version_(Version value) { assert(m_parentPackage is null); m_info.version_ = value.toString(); }

	/** Accesses the recipe contents of this package.

		The recipe contains any default values and configurations added by DUB.
		To access the raw user recipe, use the `rawRecipe` property.

		See_Also: `rawRecipe`
	*/
	@property ref inout(PackageRecipe) recipe() inout { return m_info; }

	/** Accesses the original package recipe.

		The returned recipe matches exactly the contents of the original package
		recipe. For the effective package recipe, augmented with DUB generated
		default settings and configurations, use the `recipe` property.

		See_Also: `recipe`
	*/
	@property ref const(PackageRecipe) rawRecipe() const { return m_rawRecipe; }

	/** Returns the path to the package recipe file.

		Note that this can be empty for packages that are not stored in the
		local file system.
	*/
	@property NativePath recipePath() const { return m_infoFile; }


	/** Returns the base package of this package.

		The base package is the root of the sub package hierarchy (i.e. the
		topmost parent). This will be `null` for packages that are not sub
		packages.
	*/
	@property inout(Package) basePackage() inout { return m_parentPackage ? m_parentPackage.basePackage : this; }

	/** Returns the parent of this package.

		The parent package is the package that contains a sub package. This will
		be `null` for packages that are not sub packages.
	*/
	@property inout(Package) parentPackage() inout { return m_parentPackage; }

	/** Returns the list of all sub packages.

		Note that this is a shortcut for `this.recipe.subPackages`.
	*/
	@property inout(SubPackage)[] subPackages() inout { return m_info.subPackages; }

	/** Returns the list of all build configuration names.

		Configuration contents can be accessed using `this.recipe.configurations`.
	*/
	@property string[] configurations()
	const {
		auto ret = appender!(string[])();
		foreach (ref config; m_info.configurations)
			ret.put(config.name);
		return ret.data;
	}

	/** Returns the list of all custom build type names.

		Build type contents can be accessed using `this.recipe.buildTypes`.
	*/
	@property string[] customBuildTypes()
	const {
		auto ret = appender!(string[])();
		foreach (name; m_info.buildTypes.byKey)
			ret.put(name);
		return ret.data;
	}

	/** Writes the current recipe contents to a recipe file.

		The parameter-less overload writes to `this.path`, which must not be
		empty. The default recipe file name will be used in this case.
	*/
	void storeInfo()
	{
		storeInfo(m_path);
		m_infoFile = m_path ~ defaultPackageFilename;
	}
	/// ditto
	void storeInfo(NativePath path)
	const {
		auto filename = path ~ defaultPackageFilename;
		writeJsonFile(filename, m_info.toJson());
	}

	deprecated("Use `PackageManager.getSubPackage` instead")
	Nullable!PackageRecipe getInternalSubPackage(string name)
	{
		foreach (ref p; m_info.subPackages)
			if (p.path.empty && p.recipe.name == name)
				return Nullable!PackageRecipe(p.recipe);
		return Nullable!PackageRecipe();
	}

	/** Searches for use of compiler-specific flags that have generic
		alternatives.

		This will output a warning message for each such flag to the console.
	*/
	void warnOnSpecialCompilerFlags()
	{
		// warn about use of special flags
		m_info.buildSettings.warnOnSpecialCompilerFlags(m_info.name, null);
		foreach (ref config; m_info.configurations)
			config.buildSettings.warnOnSpecialCompilerFlags(m_info.name, config.name);
	}

	/** Retrieves a build settings template.

		If no `config` is given, this returns the build settings declared at the
		root level of the package recipe. Otherwise returns the settings
		declared within the given configuration (excluding those at the root
		level).

		Note that this is a shortcut to accessing `this.recipe.buildSettings` or
		`this.recipe.configurations[].buildSettings`.
	*/
	const(BuildSettingsTemplate) getBuildSettings(string config = null)
	const {
		if (config.length) {
			foreach (ref conf; m_info.configurations)
				if (conf.name == config)
					return conf.buildSettings;
			assert(false, "Unknown configuration: "~config);
		} else {
			return m_info.buildSettings;
		}
	}

	/** Returns all BuildSettings for the given platform and configuration.

		This will gather the effective build settings declared in the package
		recipe for when building on a particular platform and configuration.
		Root build settings and configuration specific settings will be
		merged.
	*/
	BuildSettings getBuildSettings(in BuildPlatform platform, string config)
	const {
		BuildSettings ret;
		m_info.buildSettings.getPlatformSettings(ret, platform, this.path);
		bool found = false;
		foreach(ref conf; m_info.configurations){
			if( conf.name != config ) continue;
			conf.buildSettings.getPlatformSettings(ret, platform, this.path);
			found = true;
			break;
		}
		assert(found || config is null, "Unknown configuration for "~m_info.name~": "~config);

		// construct default target name based on package name
		if( ret.targetName.empty ) ret.targetName = this.name.replace(":", "_");

		// special support for DMD style flags
		getCompiler("dmd").extractBuildOptions(ret);

		return ret;
	}

	/** Returns the combination of all build settings for all configurations
		and platforms.

		This can be useful for IDEs to gather a list of all potentially used
		files or settings.
	*/
	BuildSettings getCombinedBuildSettings()
	const {
		BuildSettings ret;
		m_info.buildSettings.getPlatformSettings(ret, BuildPlatform.any, this.path);
		foreach(ref conf; m_info.configurations)
			conf.buildSettings.getPlatformSettings(ret, BuildPlatform.any, this.path);

		// construct default target name based on package name
		if (ret.targetName.empty) ret.targetName = this.name.replace(":", "_");

		// special support for DMD style flags
		getCompiler("dmd").extractBuildOptions(ret);

		return ret;
	}

	/** Adds build type specific settings to an existing set of build settings.

		This function searches the package recipe for overridden build types. If
		none is found, the default build settings will be applied, if
		`build_type` matches a default build type name. An exception is thrown
		otherwise.
	*/
	void addBuildTypeSettings(ref BuildSettings settings, in BuildPlatform platform, string build_type)
	const {
		if (auto pbt = build_type in m_info.buildTypes) {
			logDiagnostic("Using custom build type '%s'.", build_type);
			pbt.getPlatformSettings(settings, platform, this.path);
		} else {
			with(BuildOption) switch (build_type) {
				default: throw new Exception(format("Unknown build type for %s: '%s'", this.name, build_type));
				case "$DFLAGS": break;
				case "plain": break;
				case "debug": settings.addOptions(debugMode, debugInfo); break;
				case "release": settings.addOptions(releaseMode, optimize, inline); break;
				case "release-debug": settings.addOptions(releaseMode, optimize, inline, debugInfo); break;
				case "release-nobounds": settings.addOptions(releaseMode, optimize, inline, noBoundsCheck); break;
				case "unittest": settings.addOptions(unittests, debugMode, debugInfo); break;
				case "docs": settings.addOptions(syntaxOnly, _docs); break;
				case "ddox": settings.addOptions(syntaxOnly,  _ddox); break;
				case "profile": settings.addOptions(profile, optimize, inline, debugInfo); break;
				case "profile-gc": settings.addOptions(profileGC, debugInfo); break;
				case "cov": settings.addOptions(coverage, debugInfo); break;
				case "cov-ctfe": settings.addOptions(coverageCTFE, debugInfo); break;
				case "unittest-cov": settings.addOptions(unittests, coverage, debugMode, debugInfo); break;
				case "unittest-cov-ctfe": settings.addOptions(unittests, coverageCTFE, debugMode, debugInfo); break;
				case "syntax": settings.addOptions(syntaxOnly); break;
			}
		}

		// Add environment DFLAGS last so that user specified values are not overriden by us.
		import std.process : environment;
		string dflags = environment.get("DFLAGS", "");
		settings.addDFlags(dflags.split());
	}

	/** Returns the selected configuration for a certain dependency.

		If no configuration is specified in the package recipe, null will be
		returned instead.

		FIXME: The `platform` parameter is currently ignored, as the
			`"subConfigurations"` field doesn't support platform suffixes.
	*/
	string getSubConfiguration(string config, in Package dependency, in BuildPlatform platform)
	const {
		bool found = false;
		foreach(ref c; m_info.configurations){
			if( c.name == config ){
				if( auto pv = dependency.name in c.buildSettings.subConfigurations ) return *pv;
				found = true;
				break;
			}
		}
		assert(found || config is null, "Invalid configuration \""~config~"\" for "~this.name);
		if( auto pv = dependency.name in m_info.buildSettings.subConfigurations ) return *pv;
		return null;
	}

	/** Returns the default configuration to build for the given platform.

		This will return the first configuration that is applicable to the given
		platform, or `null` if none is applicable. By default, only library
		configurations will be returned. Setting `allow_non_library` to `true`
		will also return executable configurations.

		See_Also: `getPlatformConfigurations`
	*/
	string getDefaultConfiguration(in BuildPlatform platform, bool allow_non_library = false)
	const {
		foreach (ref conf; m_info.configurations) {
			if (!conf.matchesPlatform(platform)) continue;
			if (!allow_non_library && conf.buildSettings.targetType == TargetType.executable) continue;
			return conf.name;
		}
		return null;
	}

	/** Returns a list of configurations suitable for the given platform.

		Params:
			platform = The platform against which to match configurations
			allow_non_library = If set to true, executable configurations will
				also be included.

		See_Also: `getDefaultConfiguration`
	*/
	string[] getPlatformConfigurations(in BuildPlatform platform, bool allow_non_library = false)
	const {
		auto ret = appender!(string[]);
		foreach(ref conf; m_info.configurations){
			if (!conf.matchesPlatform(platform)) continue;
			if (!allow_non_library && conf.buildSettings.targetType == TargetType.executable) continue;
			ret ~= conf.name;
		}
		if (ret.data.length == 0) ret.put(null);
		return ret.data;
	}

	/** Determines if the package has a dependency to a certain package.

		Params:
			dependency_name = The name of the package to search for
			config = Name of the configuration to use when searching
				for dependencies

		See_Also: `getDependencies`
	*/
	bool hasDependency(string dependency_name, string config)
	const {
		if (dependency_name in m_info.buildSettings.dependencies) return true;
		foreach (ref c; m_info.configurations)
			if ((config.empty || c.name == config) && dependency_name in c.buildSettings.dependencies)
				return true;
		return false;
	}

	/** Retrieves all dependencies for a particular configuration.

		This includes dependencies that are declared at the root level of the
		package recipe, as well as those declared within the specified
		configuration. If no configuration with the given name exists, only
		dependencies declared at the root level will be returned.

		See_Also: `hasDependency`
	*/
	const(Dependency[string]) getDependencies(string config)
	const {
		Dependency[string] ret;
		foreach (k, v; m_info.buildSettings.dependencies) {
			// DMD bug: Not giving `Dependency` here leads to RangeError
			Dependency dep = v;
			ret[k] = dep;
		}
		foreach (ref conf; m_info.configurations)
			if (conf.name == config) {
				foreach (k, v; conf.buildSettings.dependencies) {
					Dependency dep = v;
					ret[k] = dep;
				}
				break;
			}
		return ret;
	}

	/** Returns a list of all possible dependencies of the package.

		This list includes all dependencies of all configurations. The same
		package may occur multiple times with possibly different `Dependency`
		values.
	*/
	PackageDependency[] getAllDependencies()
	const {
		auto ret = appender!(PackageDependency[]);
		getAllDependenciesRange().copy(ret);
		return ret.data;
	}

	// Left as package until the final API for this has been found
	package auto getAllDependenciesRange()
	const {
		return
			chain(
				only(this.recipe.buildSettings.dependencies.byKeyValue),
				this.recipe.configurations.map!(c => c.buildSettings.dependencies.byKeyValue)
			)
			.joiner()
			.map!(d => PackageDependency(PackageName(d.key), d.value));
	}


	/** Returns a description of the package for use in IDEs or build tools.
	*/
	PackageDescription describe(BuildPlatform platform, string config)
	const {
		return describe(platform, getCompiler(platform.compilerBinary), config);
	}
	/// ditto
	PackageDescription describe(BuildPlatform platform, Compiler compiler, string config)
	const {
		PackageDescription ret;
		ret.configuration = config;
		ret.path = m_path.toNativeString();
		ret.name = this.name;
		ret.version_ = this.version_;
		ret.description = m_info.description;
		ret.homepage = m_info.homepage;
		ret.authors = m_info.authors.dup;
		ret.copyright = m_info.copyright;
		ret.license = m_info.license;
		ret.dependencies = getDependencies(config).keys;

		// save build settings
		BuildSettings bs = getBuildSettings(platform, config);
		BuildSettings allbs = getCombinedBuildSettings();

		ret.targetType = bs.targetType;
		ret.targetPath = bs.targetPath;
		ret.targetName = bs.targetName;
		if (ret.targetType != TargetType.none && compiler)
			ret.targetFileName = compiler.getTargetFileName(bs, platform);
		ret.workingDirectory = bs.workingDirectory;
		ret.mainSourceFile = bs.mainSourceFile;
		ret.dflags = bs.dflags;
		ret.lflags = bs.lflags;
		ret.libs = bs.libs;
		ret.injectSourceFiles = bs.injectSourceFiles;
		ret.copyFiles = bs.copyFiles;
		ret.versions = bs.versions;
		ret.debugVersions = bs.debugVersions;
		ret.importPaths = bs.importPaths;
		ret.cImportPaths = bs.cImportPaths;
		ret.stringImportPaths = bs.stringImportPaths;
		ret.preGenerateCommands = bs.preGenerateCommands;
		ret.postGenerateCommands = bs.postGenerateCommands;
		ret.preBuildCommands = bs.preBuildCommands;
		ret.postBuildCommands = bs.postBuildCommands;
		ret.environments = bs.environments;
		ret.buildEnvironments = bs.buildEnvironments;
		ret.runEnvironments = bs.runEnvironments;
		ret.preGenerateEnvironments = bs.preGenerateEnvironments;
		ret.postGenerateEnvironments = bs.postGenerateEnvironments;
		ret.preBuildEnvironments = bs.preBuildEnvironments;
		ret.postBuildEnvironments = bs.postBuildEnvironments;
		ret.preRunEnvironments = bs.preRunEnvironments;
		ret.postRunEnvironments = bs.postRunEnvironments;

		// prettify build requirements output
		for (int i = 1; i <= BuildRequirement.max; i <<= 1)
			if (bs.requirements & cast(BuildRequirement)i)
				ret.buildRequirements ~= cast(BuildRequirement)i;

		// prettify options output
		for (int i = 1; i <= BuildOption.max; i <<= 1)
			if (bs.options & cast(BuildOption)i)
				ret.options ~= cast(BuildOption)i;

		// collect all possible source files and determine their types
		SourceFileRole[string] sourceFileTypes;
		foreach (f; allbs.stringImportFiles) sourceFileTypes[f] = SourceFileRole.unusedStringImport;
		foreach (f; allbs.importFiles) sourceFileTypes[f] = SourceFileRole.unusedImport;
		foreach (f; allbs.sourceFiles) sourceFileTypes[f] = SourceFileRole.unusedSource;
		foreach (f; bs.stringImportFiles) sourceFileTypes[f] = SourceFileRole.stringImport;
		foreach (f; bs.importFiles) sourceFileTypes[f] = SourceFileRole.import_;
		foreach (f; bs.sourceFiles) sourceFileTypes[f] = SourceFileRole.source;
		foreach (f; sourceFileTypes.byKey.array.sort()) {
			SourceFileDescription sf;
			sf.path = f;
			sf.role = sourceFileTypes[f];
			ret.files ~= sf;
		}

		return ret;
	}

	private void checkDubRequirements()
	{
		import dub.semver : isValidVersion;
		import dub.version_ : dubVersion;
		import std.exception : enforce;

		const dep = m_info.toolchainRequirements.dub;

		static assert(dubVersion.length);
		immutable dv = Version(dubVersion[(dubVersion[0] == 'v') .. $]);

		enforce(dep.matches(dv),
			"dub-" ~ dv.toString() ~ " does not comply with toolchainRequirements.dub "
			~ "specification: " ~ m_info.toolchainRequirements.dub.toString()
			~ "\nPlease consider upgrading your DUB installation");
	}

	private void fillWithDefaults()
	{
		auto bs = &m_info.buildSettings;

		// check for default string import folders
		if ("" !in bs.stringImportPaths) {
			foreach(defvf; ["views"]){
				if( existsFile(m_path ~ defvf) )
					bs.stringImportPaths[""] ~= defvf;
			}
		}

		// check for default source folders
		immutable hasSP = ("" in bs.sourcePaths) !is null;
		immutable hasIP = ("" in bs.importPaths) !is null;
		if (!hasSP || !hasIP) {
			foreach (defsf; ["source/", "src/"]) {
				if (existsFile(m_path ~ defsf)) {
					if (!hasSP) bs.sourcePaths[""] ~= defsf;
					if (!hasIP) bs.importPaths[""] ~= defsf;
				}
			}
		}

		// generate default configurations if none are defined
		if (m_info.configurations.length == 0) {
			// check for default app_main
			string app_main_file;
			auto pkg_name = m_info.name.length ? m_info.name : "unknown";
			MainFileSearch: foreach_reverse(sf; bs.sourcePaths.get("", null)){
				auto p = m_path ~ sf;
				if( !existsFile(p) ) continue;
				foreach(fil; ["app.d", "main.d", pkg_name ~ "/main.d", pkg_name ~ "/" ~ "app.d"]){
					if( existsFile(p ~ fil) ) {
						app_main_file = (NativePath(sf) ~ fil).toNativeString();
						break MainFileSearch;
					}
				}
			}

			if (bs.targetType == TargetType.executable) {
				BuildSettingsTemplate app_settings;
				app_settings.targetType = TargetType.executable;
				if (bs.mainSourceFile.empty) app_settings.mainSourceFile = app_main_file;
				m_info.configurations ~= ConfigurationInfo("application", app_settings);
			} else if (bs.targetType != TargetType.none) {
				BuildSettingsTemplate lib_settings;
				lib_settings.targetType = bs.targetType == TargetType.autodetect ? TargetType.library : bs.targetType;

				if (bs.targetType == TargetType.autodetect) {
					if (app_main_file.length) {
						lib_settings.excludedSourceFiles[""] ~= app_main_file;

						BuildSettingsTemplate app_settings;
						app_settings.targetType = TargetType.executable;
						app_settings.mainSourceFile = app_main_file;
						m_info.configurations ~= ConfigurationInfo("application", app_settings);
					}
				}

				m_info.configurations ~= ConfigurationInfo("library", lib_settings);
			}
		}
	}

	package void simpleLint()
	const {
		if (m_parentPackage) {
			if (m_parentPackage.path != path) {
				if (this.recipe.license.length && this.recipe.license != m_parentPackage.recipe.license)
					logWarn("Warning: License in sub-package %s is different than its parent package, this is discouraged.", name);
			}
		}
		if (name.empty) logWarn("Warning: The package in %s has no name.", path);
		bool[string] cnames;
		foreach (ref c; this.recipe.configurations) {
			if (c.name in cnames)
				logWarn("Warning: Multiple configurations with the name \"%s\" are defined in package \"%s\". This will most likely cause configuration resolution issues.",
					c.name, this.name);
			cnames[c.name] = true;
		}
	}

	/// Exclude files listed in mainSourceFile for other configurations unless they are listed in sourceFiles
	private void mutuallyExcludeMainFiles()
	{
		string[] allMainFiles;
		foreach (ref config; m_info.configurations)
			if (!config.buildSettings.mainSourceFile.empty())
				allMainFiles ~= config.buildSettings.mainSourceFile;

		if (allMainFiles.length == 0)
			return;

		foreach (ref config; m_info.configurations) {
			import std.algorithm.searching : canFind;
			auto bs = &config.buildSettings;
			auto otherMainFiles = allMainFiles.filter!(elem => (elem != bs.mainSourceFile)).array;

			if (bs.sourceFiles.length == 0)
				bs.excludedSourceFiles[""] ~= otherMainFiles;
			else
				foreach (suffix, arr; bs.sourceFiles)
					bs.excludedSourceFiles[suffix] ~= otherMainFiles.filter!(elem => !canFind(arr, elem)).array;
		}
	}
}

private string determineVersionFromSCM(NativePath path)
{
	if (existsFile(path ~ ".git"))
	{
		import dub.internal.git : determineVersionWithGit;

		return determineVersionWithGit(path);
	}
	return null;
}
