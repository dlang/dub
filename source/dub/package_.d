/**
	Stuff with dependencies.

	Copyright: © 2012-2013 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.package_;

import dub.compilers.compiler;
import dub.dependency;
import dub.internal.utils;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.url;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.range;
import std.string;
import std.traits : EnumMembers;


// Supported package descriptions in decreasing order of preference.
enum packageInfoFilenames = ["dub.json", /*"dub.sdl",*/ "package.json"];
string defaultPackageFilename() {
	return packageInfoFilenames[0];
}

/**
	Represents a package, including its sub packages

	Documentation of the dub.json can be found at
	http://registry.vibed.org/package-format
*/
class Package {
	static struct LocalPackageDef { string name; Version version_; Path path; }

	private {
		Path m_path;
		Path m_infoFile;
		PackageInfo m_info;
		Package m_parentPackage;
		Package[] m_subPackages;
		Path[] m_exportedPackages;
	}

	static bool isPackageAt(Path path)
	{
		foreach (f; packageInfoFilenames)
			if (existsFile(path ~ f))
				return true;
		return false;
	}

	this(Path root, Package parent = null, string versionOverride = "")
	{
		Json info;
		try {
			foreach (f; packageInfoFilenames) {
				auto name = root ~ f;
				if (existsFile(name)) {
					m_infoFile = name;
					info = jsonFromFile(m_infoFile);
					break;
				}
			}
		} catch (Exception ex) throw new Exception(format("Failed to load package at %s: %s", root.toNativeString(), ex.msg));

		enforce(info.type != Json.Type.undefined, format("Missing package description for package at %s", root.toNativeString()));

		this(info, root, parent, versionOverride);
	}

	this(Json packageInfo, Path root = Path(), Package parent = null, string versionOverride = "")
	{
		m_parentPackage = parent;
		m_path = root;
		m_path.endsWithSlash = true;

		// force the package name to be lower case
		packageInfo.name = packageInfo.name.get!string.toLower();

		// check for default string import folders
		foreach(defvf; ["views"]){
			auto p = m_path ~ defvf;
			if( existsFile(p) )
				m_info.buildSettings.stringImportPaths[""] ~= defvf;
		}

		string app_main_file;
		auto pkg_name = packageInfo.name.get!string();

		// check for default source folders
		foreach(defsf; ["source/", "src/"]){
			auto p = m_path ~ defsf;
			if( existsFile(p) ){
				m_info.buildSettings.sourcePaths[""] ~= defsf;
				m_info.buildSettings.importPaths[""] ~= defsf;
				foreach (fil; ["app.d", "main.d", pkg_name ~ "/main.d", pkg_name ~ "/" ~ "app.d"])
					if (existsFile(p ~ fil)) {
						app_main_file = Path(defsf ~ fil).toNativeString();
						break;
					}
			}
		}

		// parse the JSON description
		{
			scope(failure) logError("Failed to parse package description in %s", root.toNativeString());
			m_info.parseJson(packageInfo, parent ? parent.name : null);

			if (!versionOverride.empty)
				m_info.version_ = versionOverride;

			// try to run git to determine the version of the package if no explicit version was given
			if (m_info.version_.length == 0 && !parent) {
				try m_info.version_ = determineVersionFromSCM(root);
				catch (Exception e) logDebug("Failed to determine version by SCM: %s", e.msg);

				if (m_info.version_.length == 0) {
					logDiagnostic("Note: Failed to determine version of package %s at %s. Assuming ~master.", m_info.name, this.path.toNativeString());
					// TODO: Assume unknown version here?
					// m_info.version_ = Version.UNKNOWN.toString();
					m_info.version_ = Version.MASTER.toString();
				} else logDiagnostic("Determined package version using GIT: %s %s", m_info.name, m_info.version_);
			}
		}

		// generate default configurations if none are defined
		if (m_info.configurations.length == 0) {
			if (m_info.buildSettings.targetType == TargetType.executable) {
				BuildSettingsTemplate app_settings;
				app_settings.targetType = TargetType.executable;
				if (m_info.buildSettings.mainSourceFile.empty) app_settings.mainSourceFile = app_main_file;
				m_info.configurations ~= ConfigurationInfo("application", app_settings);
			} else if (m_info.buildSettings.targetType != TargetType.none) {
				BuildSettingsTemplate lib_settings;
				lib_settings.targetType = m_info.buildSettings.targetType == TargetType.autodetect ? TargetType.library : m_info.buildSettings.targetType;

				if (m_info.buildSettings.targetType == TargetType.autodetect) {
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

		// load all sub packages defined in the package description
		foreach (sub; packageInfo.subPackages.opt!(Json[])) {
			enforce(!m_parentPackage, format("'subPackages' found in '%s'. This is only supported in the main package file for '%s'.", name, m_parentPackage.name));

			if (sub.type == Json.Type.string)  {
				auto p = Path(sub.get!string);
				p.normalize();
				enforce(!p.absolute, "Sub package paths must not be absolute: " ~ sub.get!string);
				enforce(!p.startsWith(Path("..")), "Sub packages must be in a sub directory, not " ~ sub.get!string);
				m_exportedPackages ~= p;
				if (!path.empty) m_subPackages ~= new Package(path ~ p, this, this.vers);
			} else {
				m_subPackages ~= new Package(sub, root, this);
			}
		}

		simpleLint();
	}

	@property string name()
	const {
		if (m_parentPackage) return m_parentPackage.name ~ ":" ~ m_info.name;
		else return m_info.name;
	}
	@property string vers() const { return m_parentPackage ? m_parentPackage.vers : m_info.version_; }
	@property Version ver() const { return Version(this.vers); }
	@property void ver(Version ver) { assert(m_parentPackage is null); m_info.version_ = ver.toString(); }
	@property ref inout(PackageInfo) info() inout { return m_info; }
	@property Path path() const { return m_path; }
	@property Path packageInfoFile() const { return m_infoFile; }
	@property const(Dependency[string]) dependencies() const { return m_info.dependencies; }
	@property inout(Package) basePackage() inout { return m_parentPackage ? m_parentPackage.basePackage : this; }
	@property inout(Package) parentPackage() inout { return m_parentPackage; }
	@property inout(Package)[] subPackages() inout { return m_subPackages; }
	@property inout(Path[]) exportedPackages() inout { return m_exportedPackages; }

	@property string[] configurations()
	const {
		auto ret = appender!(string[])();
		foreach( ref config; m_info.configurations )
			ret.put(config.name);
		return ret.data;
	}

	const(Dependency[string]) getDependencies(string config)
	const {
		Dependency[string] ret;
		foreach (k, v; m_info.buildSettings.dependencies)
			ret[k] = v;
		foreach (ref conf; m_info.configurations)
			if (conf.name == config) {
				foreach (k, v; conf.buildSettings.dependencies)
					ret[k] = v;
				break;
			}
		return ret;
	}

	/** Overwrites the packge description file using the default filename with the current information.
	*/
	void storeInfo()
	{
		enforce(!ver.isUnknown, "Trying to store a package with an 'unknown' version, this is not supported.");
		auto filename = m_path ~ defaultPackageFilename();
		auto dstFile = openFile(filename.toNativeString(), FileMode.CreateTrunc);
		scope(exit) dstFile.close();
		dstFile.writePrettyJsonString(m_info.toJson());
		m_infoFile = filename;
	}

	inout(Package) getSubPackage(string name, bool silent_fail = false)
	inout {
		foreach (p; m_subPackages)
			if (p.name == this.name ~ ":" ~ name)
				return p;
		enforce(silent_fail, format("Unknown sub package: %s:%s", this.name, name));
		return null;
	}

	void warnOnSpecialCompilerFlags()
	{
		// warn about use of special flags
		m_info.buildSettings.warnOnSpecialCompilerFlags(m_info.name, null);
		foreach (ref config; m_info.configurations)
			config.buildSettings.warnOnSpecialCompilerFlags(m_info.name, config.name);
	}

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

	/// Returns all BuildSettings for the given platform and config.
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
		dub.compilers.dmd.DmdCompiler.extractBuildOptions_(ret);

		return ret;
	}

	/// Returns the combination of all build settings for all configurations and platforms
	BuildSettings getCombinedBuildSettings()
	const {
		BuildSettings ret;
		m_info.buildSettings.getPlatformSettings(ret, BuildPlatform.any, this.path);
		foreach(ref conf; m_info.configurations)
			conf.buildSettings.getPlatformSettings(ret, BuildPlatform.any, this.path);

		// construct default target name based on package name
		if (ret.targetName.empty) ret.targetName = this.name.replace(":", "_");

		// special support for DMD style flags
		dub.compilers.dmd.DmdCompiler.extractBuildOptions_(ret);

		return ret;
	}

	void addBuildTypeSettings(ref BuildSettings settings, in BuildPlatform platform, string build_type)
	const {
		if (build_type == "$DFLAGS") {
			import std.process;
			string dflags = environment.get("DFLAGS");
			settings.addDFlags(dflags.split());
			return;
		}

		if (auto pbt = build_type in m_info.buildTypes) {
			logDiagnostic("Using custom build type '%s'.", build_type);
			pbt.getPlatformSettings(settings, platform, this.path);
		} else {
			with(BuildOptions) switch (build_type) {
				default: throw new Exception(format("Unknown build type for %s: '%s'", this.name, build_type));
				case "plain": break;
				case "debug": settings.addOptions(debugMode, debugInfo); break;
				case "release": settings.addOptions(releaseMode, optimize, inline); break;
				case "release-nobounds": settings.addOptions(releaseMode, optimize, inline, noBoundsCheck); break;
				case "unittest": settings.addOptions(unittests, debugMode, debugInfo); break;
				case "docs": settings.addOptions(syntaxOnly); settings.addDFlags("-c", "-Dddocs"); break;
				case "ddox": settings.addOptions(syntaxOnly); settings.addDFlags("-c", "-Df__dummy.html", "-Xfdocs.json"); break;
				case "profile": settings.addOptions(profile, optimize, inline, debugInfo); break;
				case "cov": settings.addOptions(coverage, debugInfo); break;
				case "unittest-cov": settings.addOptions(unittests, coverage, debugMode, debugInfo); break;
			}
		}
	}

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

	/// Returns the default configuration to build for the given platform
	string getDefaultConfiguration(in BuildPlatform platform, bool allow_non_library = false)
	const {
		foreach (ref conf; m_info.configurations) {
			if (!conf.matchesPlatform(platform)) continue;
			if (!allow_non_library && conf.buildSettings.targetType == TargetType.executable) continue;
			return conf.name;
		}
		return null;
	}

	/// Returns a list of configurations suitable for the given platform
	string[] getPlatformConfigurations(in BuildPlatform platform, bool is_main_package = false)
	const {
		auto ret = appender!(string[]);
		foreach(ref conf; m_info.configurations){
			if (!conf.matchesPlatform(platform)) continue;
			if (!is_main_package && conf.buildSettings.targetType == TargetType.executable) continue;
			ret ~= conf.name;
		}
		if (ret.data.length == 0) ret.put(null);
		return ret.data;
	}

	/// Human readable information of this package and its dependencies.
	string generateInfoString() const {
		string s;
		s ~= m_info.name ~ ", version '" ~ m_info.version_ ~ "'";
		s ~= "\n  Dependencies:";
		foreach(string p, ref const Dependency v; m_info.dependencies)
			s ~= "\n    " ~ p ~ ", version '" ~ v.toString() ~ "'";
		return s;
	}

	bool hasDependency(string depname, string config)
	const {
		if (depname in m_info.buildSettings.dependencies) return true;
		foreach (ref c; m_info.configurations)
			if ((config.empty || c.name == config) && depname in c.buildSettings.dependencies)
				return true;
		return false;
	}

	void describe(ref Json dst, BuildPlatform platform, string config)
	{
		dst.path = m_path.toNativeString();
		dst.name = this.name;
		dst["version"] = this.vers;
		dst.description = m_info.description;
		dst.homepage = m_info.homepage;
		dst.authors = m_info.authors.serializeToJson();
		dst.copyright = m_info.copyright;
		dst.license = m_info.license;
		dst.dependencies = m_info.dependencies.keys.serializeToJson();

		// save build settings
		BuildSettings bs = getBuildSettings(platform, config);
		BuildSettings allbs = getCombinedBuildSettings();

		foreach (string k, v; bs.serializeToJson()) dst[k] = v;
		dst.remove("requirements");
		dst.remove("sourceFiles");
		dst.remove("importFiles");
		dst.remove("stringImportFiles");
		dst.targetType = bs.targetType.to!string();
		if (dst.targetType != TargetType.none)
			dst.targetFileName = getTargetFileName(bs, platform);

		// prettify build requirements output
		Json[] breqs;
		for (int i = 1; i <= BuildRequirements.max; i <<= 1)
			if (bs.requirements & i)
				breqs ~= Json(to!string(cast(BuildRequirements)i));
		dst.buildRequirements = breqs;

		// prettify options output
		Json[] bopts;
		for (int i = 1; i <= BuildOptions.max; i <<= 1)
			if (bs.options & i)
				bopts ~= Json(to!string(cast(BuildOptions)i));
		dst.options = bopts;

		// collect all possible source files and determine their types
		string[string] sourceFileTypes;
		foreach (f; allbs.stringImportFiles) sourceFileTypes[f] = "unusedStringImport";
		foreach (f; allbs.importFiles) sourceFileTypes[f] = "unusedImport";
		foreach (f; allbs.sourceFiles) sourceFileTypes[f] = "unusedSource";
		foreach (f; bs.stringImportFiles) sourceFileTypes[f] = "stringImport";
		foreach (f; bs.importFiles) sourceFileTypes[f] = "import";
		foreach (f; bs.sourceFiles) sourceFileTypes[f] = "source";
		Json[] files;
		foreach (f; sourceFileTypes.byKey.array.sort) {
			auto jf = Json.emptyObject;
			jf["path"] = f;
			jf["type"] = sourceFileTypes[f];
			files ~= jf;
		}
		dst.files = Json(files);
	}

	private void simpleLint() const {
		if (m_parentPackage) {
			if (m_parentPackage.path != path) {
				if (info.license.length && info.license != m_parentPackage.info.license)
					logWarn("License in subpackage %s is different than it's parent package, this is discouraged.", name);
			}
		}
		if (name.empty()) logWarn("The package in %s has no name.", path);
	}
}

/// Specifying package information without any connection to a certain
/// retrived package, like Package class is doing.
struct PackageInfo {
	string name;
	string version_;
	string description;
	string homepage;
	string[] authors;
	string copyright;
	string license;
	string[] ddoxFilterArgs;
	BuildSettingsTemplate buildSettings;
	ConfigurationInfo[] configurations;
	BuildSettingsTemplate[string] buildTypes;
	Json subPackages;

	@property const(Dependency)[string] dependencies()
	const {
		const(Dependency)[string] ret;
		foreach (n, d; this.buildSettings.dependencies)
			ret[n] = d;
		foreach (ref c; configurations)
			foreach (n, d; c.buildSettings.dependencies)
				ret[n] = d;
		return ret;
	}

	inout(ConfigurationInfo) getConfiguration(string name)
	inout {
		foreach (c; configurations)
			if (c.name == name)
				return c;
		throw new Exception("Unknown configuration: "~name);
	}

	void parseJson(Json json, string parent_name)
	{
		foreach( string field, value; json ){
			switch(field){
				default: break;
				case "name": this.name = value.get!string; break;
				case "version": this.version_ = value.get!string; break;
				case "description": this.description = value.get!string; break;
				case "homepage": this.homepage = value.get!string; break;
				case "authors": this.authors = deserializeJson!(string[])(value); break;
				case "copyright": this.copyright = value.get!string; break;
				case "license": this.license = value.get!string; break;
				case "subPackages": subPackages = value; break;
				case "configurations": break; // handled below, after the global settings have been parsed
				case "buildTypes":
					foreach (string name, settings; value) {
						BuildSettingsTemplate bs;
						bs.parseJson(settings, null);
						buildTypes[name] = bs;
					}
					break;
				case "-ddoxFilterArgs": this.ddoxFilterArgs = deserializeJson!(string[])(value); break;
			}
		}

		enforce(this.name.length > 0, "The package \"name\" field is missing or empty.");

		// parse build settings
		this.buildSettings.parseJson(json, parent_name.length ? parent_name ~ ":" ~ this.name : this.name);

		if (auto pv = "configurations" in json) {
			TargetType deftargettp = TargetType.library;
			if (this.buildSettings.targetType != TargetType.autodetect)
				deftargettp = this.buildSettings.targetType;

			foreach (settings; *pv) {
				ConfigurationInfo ci;
				ci.parseJson(settings, this.name, deftargettp);
				this.configurations ~= ci;
			}
		}
	}

	Json toJson()
	const {
		auto ret = buildSettings.toJson();
		ret.name = this.name;
		if( !this.version_.empty ) ret["version"] = this.version_;
		if( !this.description.empty ) ret.description = this.description;
		if( !this.homepage.empty ) ret.homepage = this.homepage;
		if( !this.authors.empty ) ret.authors = serializeToJson(this.authors);
		if( !this.copyright.empty ) ret.copyright = this.copyright;
		if( !this.license.empty ) ret.license = this.license;
		if( this.subPackages.type != Json.Type.undefined ) {
			auto copy = this.subPackages.toString();
			ret.subPackages = dub.internal.vibecompat.data.json.parseJson(copy);
		}
		if( this.configurations ){
			Json[] configs;
			foreach(config; this.configurations)
				configs ~= config.toJson();
			ret.configurations = configs;
		}
		if( this.buildTypes.length ) {
			Json[string] types;
			foreach(name, settings; this.buildTypes)
				types[name] = settings.toJson();
		}
		if( !this.ddoxFilterArgs.empty ) ret["-ddoxFilterArgs"] = this.ddoxFilterArgs.serializeToJson();
		return ret;
	}
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

	void parseJson(Json json, string package_name, TargetType default_target_type = TargetType.library)
	{
		this.buildSettings.targetType = default_target_type;

		foreach(string name, value; json){
			switch(name){
				default: break;
				case "name":
					this.name = value.get!string();
					enforce(!this.name.empty, "Configurations must have a non-empty name.");
					break;
				case "platforms": this.platforms = deserializeJson!(string[])(value); break;
			}
		}

		enforce(!this.name.empty, "Configuration is missing a name.");

		BuildSettingsTemplate bs;
		this.buildSettings.parseJson(json, package_name);
	}

	Json toJson()
	const {
		auto ret = buildSettings.toJson();
		ret.name = name;
		if( this.platforms.length ) ret.platforms = serializeToJson(platforms);
		return ret;
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
	BuildRequirements[string] buildRequirements;
	BuildOptions[string] buildOptions;

	void parseJson(Json json, string package_name)
	{
		foreach(string name, value; json)
		{
			auto idx = std.string.indexOf(name, "-");
			string basename, suffix;
			if( idx >= 0 ) basename = name[0 .. idx], suffix = name[idx .. $];
			else basename = name;
			switch(basename){
				default: break;
				case "dependencies":
					foreach (string pkg, verspec; value) {
						if (pkg.startsWith(":")) {
							enforce(!package_name.canFind(':'), format("Short-hand packages syntax not allowed within sub packages: %s -> %s", package_name, pkg));
							pkg = package_name ~ pkg;
						}
						enforce(pkg !in this.dependencies, "The dependency '"~pkg~"' is specified more than once." );
						this.dependencies[pkg] = deserializeJson!Dependency(verspec);
					}
					break;
				case "systemDependencies":
					this.systemDependencies = value.get!string;
					break;
				case "targetType":
					enforce(suffix.empty, "targetType does not support platform customization.");
					targetType = value.get!string().to!TargetType();
					break;
				case "targetPath":
					enforce(suffix.empty, "targetPath does not support platform customization.");
					this.targetPath = value.get!string;
					break;
				case "targetName":
					enforce(suffix.empty, "targetName does not support platform customization.");
					this.targetName = value.get!string;
					break;
				case "workingDirectory":
					enforce(suffix.empty, "workingDirectory does not support platform customization.");
					this.workingDirectory = value.get!string;
					break;
				case "mainSourceFile":
					enforce(suffix.empty, "mainSourceFile does not support platform customization.");
					this.mainSourceFile = value.get!string;
					break;
				case "subConfigurations":
					enforce(suffix.empty, "subConfigurations does not support platform customization.");
					this.subConfigurations = deserializeJson!(string[string])(value);
					break;
				case "dflags": this.dflags[suffix] = deserializeJson!(string[])(value); break;
				case "lflags": this.lflags[suffix] = deserializeJson!(string[])(value); break;
				case "libs": this.libs[suffix] = deserializeJson!(string[])(value); break;
				case "files":
				case "sourceFiles": this.sourceFiles[suffix] = deserializeJson!(string[])(value); break;
				case "sourcePaths": this.sourcePaths[suffix] = deserializeJson!(string[])(value); break;
				case "sourcePath": this.sourcePaths[suffix] ~= [value.get!string()]; break; // deprecated
				case "excludedSourceFiles": this.excludedSourceFiles[suffix] = deserializeJson!(string[])(value); break;
				case "copyFiles": this.copyFiles[suffix] = deserializeJson!(string[])(value); break;
				case "versions": this.versions[suffix] = deserializeJson!(string[])(value); break;
				case "debugVersions": this.debugVersions[suffix] = deserializeJson!(string[])(value); break;
				case "importPaths": this.importPaths[suffix] = deserializeJson!(string[])(value); break;
				case "stringImportPaths": this.stringImportPaths[suffix] = deserializeJson!(string[])(value); break;
				case "preGenerateCommands": this.preGenerateCommands[suffix] = deserializeJson!(string[])(value); break;
				case "postGenerateCommands": this.postGenerateCommands[suffix] = deserializeJson!(string[])(value); break;
				case "preBuildCommands": this.preBuildCommands[suffix] = deserializeJson!(string[])(value); break;
				case "postBuildCommands": this.postBuildCommands[suffix] = deserializeJson!(string[])(value); break;
				case "buildRequirements":
					BuildRequirements reqs;
					foreach (req; deserializeJson!(string[])(value))
						reqs |= to!BuildRequirements(req);
					this.buildRequirements[suffix] = reqs;
					break;
				case "buildOptions":
					BuildOptions options;
					foreach (opt; deserializeJson!(string[])(value))
						options |= to!BuildOptions(opt);
					this.buildOptions[suffix] = options;
					break;
			}
		}
	}

	Json toJson()
	const {
		auto ret = Json.emptyObject;
		if( this.dependencies !is null ){
			auto deps = Json.emptyObject;
			foreach( pack, d; this.dependencies )
				deps[pack] = serializeToJson(d);
			ret.dependencies = deps;
		}
		if (this.systemDependencies !is null) ret.systemDependencies = this.systemDependencies;
		if (targetType != TargetType.autodetect) ret["targetType"] = targetType.to!string();
		if (!targetPath.empty) ret["targetPath"] = targetPath;
		if (!targetName.empty) ret["targetName"] = targetName;
		if (!workingDirectory.empty) ret["workingDirectory"] = workingDirectory;
		if (!mainSourceFile.empty) ret["mainSourceFile"] = mainSourceFile;
		foreach (suffix, arr; dflags) ret["dflags"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; lflags) ret["lflags"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; libs) ret["libs"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; sourceFiles) ret["sourceFiles"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; sourcePaths) ret["sourcePaths"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; excludedSourceFiles) ret["excludedSourceFiles"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; copyFiles) ret["copyFiles"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; versions) ret["versions"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; debugVersions) ret["debugVersions"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; importPaths) ret["importPaths"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; stringImportPaths) ret["stringImportPaths"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; preGenerateCommands) ret["preGenerateCommands"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; postGenerateCommands) ret["postGenerateCommands"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; preBuildCommands) ret["preBuildCommands"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; postBuildCommands) ret["postBuildCommands"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; buildRequirements) {
			string[] val;
			foreach (i; [EnumMembers!BuildRequirements])
				if (arr & i) val ~= to!string(i);
			ret["buildRequirements"~suffix] = serializeToJson(val);
		}
		foreach (suffix, arr; buildOptions) {
			string[] val;
			foreach (i; [EnumMembers!BuildOptions])
				if (arr & i) val ~= to!string(i);
			ret["buildOptions"~suffix] = serializeToJson(val);
		}
		return ret;
	}

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
						if (isDir(d.name)) continue;
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
			if (req & BuildRequirements.noDefaultFlags) nodef = true;
			if (req & BuildRequirements.relaxProperties) noprop = true;
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

/// Returns all package names, starting with the root package in [0].
string[] getSubPackagePath(string package_name)
{
	return package_name.split(":");
}

/// Returns the name of the base package in the case of some sub package or the
/// package itself, if it is already a full package.
string getBasePackageName(string package_name)
{
	return package_name.getSubPackagePath()[0];
}

string getSubPackageName(string package_name)
{
	return getSubPackagePath(package_name)[1 .. $].join(":");
}

private string determineVersionFromSCM(Path path)
{
	import std.process;
	import dub.semver;

	auto git_dir = path ~ ".git";
	if (!existsFile(git_dir) || !isDir(git_dir.toNativeString)) return null;
	auto git_dir_param = "--git-dir=" ~ git_dir.toNativeString();

	static string exec(scope string[] params...) {
		auto ret = executeShell(escapeShellCommand(params));
		if (ret.status == 0) return ret.output.strip;
		logDebug("'%s' failed with exit code %s: %s", params.join(" "), ret.status, ret.output.strip);
		return null;
	}

	if (auto tag = exec("git", git_dir_param, "describe", "--long", "--tags")) {
		auto parts = tag.split("-");
		auto commit = parts[$-1];
		auto num = parts[$-2].to!int;
		tag = parts[0 .. $-2].join("-");
		if (tag.startsWith("v") && isValidVersion(tag[1 .. $])) {
			if (num == 0) return tag[1 .. $];
			else if (tag.canFind("+")) return format("%s.commit.%s.%s", tag[1 .. $], num, commit);
			else return format("%s+commit.%s.%s", tag[1 .. $], num, commit);
		}
	}

	if (auto branch = exec("git", git_dir_param, "rev-parse", "--abbrev-ref", "HEAD")) {
		if (branch != "HEAD") return "~" ~ branch;
	}

	return null;
}
