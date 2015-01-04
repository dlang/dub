/**
	Stuff with dependencies.

	Copyright: © 2012-2013 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.package_;

public import dub.recipe.packagerecipe;

import dub.compilers.compiler;
import dub.dependency;
import dub.recipe.json;
import dub.recipe.sdl;

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



enum PackageFormat { json, sdl }
struct FilenameAndFormat
{
	string filename;
	PackageFormat format;
}
struct PathAndFormat
{
	Path path;
	PackageFormat format;
	@property bool empty() { return path.empty; }
	string toString() { return path.toString(); }
}

// Supported package descriptions in decreasing order of preference.
static immutable FilenameAndFormat[] packageInfoFiles = [
	{"dub.json", PackageFormat.json},
	/*{"dub.sdl",PackageFormat.sdl},*/
	{"package.json", PackageFormat.json}
];

@property string[] packageInfoFilenames() { return packageInfoFiles.map!(f => cast(string)f.filename).array; }

@property string defaultPackageFilename() { return packageInfoFiles[0].filename; }


/**
	Represents a package, including its sub packages

	Documentation of the dub.json can be found at
	http://registry.vibed.org/package-format
*/
class Package {
	private {
		Path m_path;
		PathAndFormat m_infoFile;
		PackageRecipe m_info;
		Package m_parentPackage;
	}

	static PathAndFormat findPackageFile(Path path)
	{
		foreach(file; packageInfoFiles) {
			auto filename = path ~ file.filename;
			if(existsFile(filename)) return PathAndFormat(filename, file.format);
		}
		return PathAndFormat(Path());
	}

	this(Path root, PathAndFormat infoFile = PathAndFormat(), Package parent = null, string versionOverride = "")
	{
		RawPackage raw_package;
		m_infoFile = infoFile;

		try {
			if(m_infoFile.empty) {
				m_infoFile = findPackageFile(root);
				if(m_infoFile.empty) throw new Exception("no package file was found, expected one of the following: "~to!string(packageInfoFiles));
			}
			raw_package = rawPackageFromFile(m_infoFile);
		} catch (Exception ex) throw ex;//throw new Exception(format("Failed to load package %s: %s", m_infoFile.toNativeString(), ex.msg));

		enforce(raw_package !is null, format("Missing package description for package at %s", root.toNativeString()));
		this(raw_package, root, parent, versionOverride);
	}

	this(Json package_info, Path root = Path(), Package parent = null, string versionOverride = "")
	{
		this(new JsonPackage(package_info), root, parent, versionOverride);
	}

	this(RawPackage raw_package, Path root = Path(), Package parent = null, string versionOverride = "")
	{
		PackageRecipe recipe;

		// parse the Package description
		if(raw_package !is null)
		{
			scope(failure) logError("Failed to parse package description for %s %s in %s.",
				raw_package.package_name, versionOverride.length ? versionOverride : raw_package.version_,
				root.length ? root.toNativeString() : "remote location");
			raw_package.parseInto(recipe, parent ? parent.name : null);

			if (!versionOverride.empty)
				recipe.version_ = versionOverride;

			// try to run git to determine the version of the package if no explicit version was given
			if (recipe.version_.length == 0 && !parent) {
				try recipe.version_ = determineVersionFromSCM(root);
				catch (Exception e) logDebug("Failed to determine version by SCM: %s", e.msg);

				if (recipe.version_.length == 0) {
					logDiagnostic("Note: Failed to determine version of package %s at %s. Assuming ~master.", recipe.name, this.path.toNativeString());
					// TODO: Assume unknown version here?
					// recipe.version_ = Version.UNKNOWN.toString();
					recipe.version_ = Version.MASTER.toString();
				} else logDiagnostic("Determined package version using GIT: %s %s", recipe.name, recipe.version_);
			}
		}

		this(recipe, root, parent);
	}

	this(PackageRecipe recipe, Path root = Path(), Package parent = null)
	{
		m_parentPackage = parent;
		m_path = root;
		m_path.endsWithSlash = true;

		// use the given recipe as the basis
		m_info = recipe;

		fillWithDefaults();
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
	@property ref inout(PackageRecipe) info() inout { return m_info; }
	@property Path path() const { return m_path; }
	@property Path packageInfoFilename() const { return m_infoFile.path; }
	@property const(Dependency[string]) dependencies() const { return m_info.dependencies; }
	@property inout(Package) basePackage() inout { return m_parentPackage ? m_parentPackage.basePackage : this; }
	@property inout(Package) parentPackage() inout { return m_parentPackage; }
	@property inout(SubPackage)[] subPackages() inout { return m_info.subPackages; }

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
		auto filename = m_path ~ defaultPackageFilename;
		auto dstFile = openFile(filename.toNativeString(), FileMode.CreateTrunc);
		scope(exit) dstFile.close();
		dstFile.writePrettyJsonString(m_info.toJson());
		m_infoFile = PathAndFormat(filename);
	}

	/*inout(Package) getSubPackage(string name, bool silent_fail = false)
	inout {
		foreach (p; m_info.subPackages)
			if (p.package_ !is null && p.package_.name == this.name ~ ":" ~ name)
				return p.package_;
		enforce(silent_fail, format("Unknown sub package: %s:%s", this.name, name));
		return null;
	}*/

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
		getCompiler("dmd").extractBuildOptions(ret);

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
		getCompiler("dmd").extractBuildOptions(ret);

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
		foreach (f; sourceFileTypes.byKey.array.sort()) {
			auto jf = Json.emptyObject;
			jf["path"] = f;
			jf["type"] = sourceFileTypes[f];
			files ~= jf;
		}
		dst.files = Json(files);
	}

	private void fillWithDefaults() {
		auto bs = &m_info.buildSettings;

		// check for default string import folders
		if (!bs.stringImportPaths.get("", null).length) {
			foreach(defvf; ["views"]){
				if( existsFile(m_path ~ defvf) )
					bs.stringImportPaths[""] ~= defvf;
			}
		}

		// check for default source folders
		immutable hasSP = !!bs.sourcePaths.get("", null).length;
		immutable hasIP = !!bs.importPaths.get("", null).length;
		if (!hasSP || !hasIP) {
			foreach(defsf; ["source/", "src/"]){
				if( existsFile(m_path ~ defsf) ){
					if (!hasSP) bs.sourcePaths[""] ~= defsf;
					if (!hasIP) bs.importPaths[""] ~= defsf;
				}
			}
		}

		// check for default app_main
		string app_main_file;
		auto pkg_name = m_info.name.length ? m_info.name : "unknown";
		foreach(sf; bs.sourcePaths.get("", null)){
			auto p = m_path ~ sf;
			if( !existsFile(p) ) continue;
			foreach(fil; ["app.d", "main.d", pkg_name ~ "/main.d", pkg_name ~ "/" ~ "app.d"]){
				if( existsFile(p ~ fil) ) {
					app_main_file = Path(sf ~ fil).toNativeString();
					break;
				}
			}
		}

		// generate default configurations if none are defined
		if (m_info.configurations.length == 0) {
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

	private void simpleLint() const {
		if (m_parentPackage) {
			if (m_parentPackage.path != path) {
				if (info.license.length && info.license != m_parentPackage.info.license)
					logWarn("License in subpackage %s is different than it's parent package, this is discouraged.", name);
			}
		}
		if (name.empty) logWarn("The package in %s has no name.", path);
	}

	private static RawPackage rawPackageFromFile(PathAndFormat file, bool silent_fail = false) {
		if( silent_fail && !existsFile(file.path) ) return null;

		string text;

		{
			auto f = openFile(file.path.toNativeString(), FileMode.Read);
			scope(exit) f.close();
			text = stripUTF8Bom(cast(string)f.readAll());
		}

		final switch(file.format) {
			case PackageFormat.json:
				return new JsonPackage(parseJsonString(text, file.path.toNativeString()));
			case PackageFormat.sdl:
				if(silent_fail) return null; throw new Exception("SDL not implemented");
		}
	}

	static abstract class RawPackage
	{
		string package_name; // Should already be lower case
		string version_;
		abstract void parseInto(ref PackageRecipe package_, string parent_name);
	}
	private static class JsonPackage : RawPackage
	{
		Json json;
		this(Json json) {
			this.json = json;

			string nameLower;
			if(json.type == Json.Type.string) {
				nameLower = json.get!string.toLower();
				this.json = nameLower;
			} else {
				nameLower = json.name.get!string.toLower();
				this.json.name = nameLower;
				this.package_name = nameLower;

				Json versionJson = json["version"];
				this.version_ = (versionJson.type == Json.Type.undefined) ? null : versionJson.get!string;
			}

			this.package_name = nameLower;
		}
		override void parseInto(ref PackageRecipe recipe, string parent_name)
		{
			recipe.parseJson(json, parent_name);
		}
	}
	private static class SdlPackage : RawPackage
	{
		override void parseInto(ref PackageRecipe package_, string parent_name)
		{
			throw new Exception("SDL packages not implemented yet");
		}
	}
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
