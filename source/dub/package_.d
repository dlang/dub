/**
	Stuff with dependencies.

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.package_;

import dub.dependency;
import dub.utils;

import std.array;
import std.conv;
import std.exception;
import std.file;
import vibe.core.file;
import vibe.data.json;
import vibe.inet.url;

enum PackageJsonFilename = "package.json";

/// Represents a platform a package can be build upon.
struct BuildPlatform {
	/// e.g. ["posix", "windows"]
	string[] platform;
	/// e.g. ["x86", "x64"]
	string[] architecture;
	/// e.g. "dmd"
	string compiler;
}

/// BuildPlatform specific settings, like needed libraries or additional
/// include paths.
struct BuildSettings {
	string[] dflags;
	string[] lflags;
	string[] libs;
	string[] files;
	string[] copyFiles;
	string[] versions;
	string[] importPaths;
	string[] stringImportPaths;

	void parse(in Json root, BuildPlatform platform)
	{
		addDFlags(getPlatformField(root, "dflags", platform));
		addLFlags(getPlatformField(root, "lflags", platform));
		addLibs(getPlatformField(root, "libs", platform));
		addFiles(getPlatformField(root, "files", platform));
		addCopyFiles(getPlatformField(root, "copyFiles", platform));
		addVersions(getPlatformField(root, "versions", platform));
		addImportDirs(getPlatformField(root, "importPaths", platform));
		addStringImportDirs(getPlatformField(root, "stringImportPaths", platform));
	}

	void addDFlags(string[] value) { add(dflags, value); }
	void addLFlags(string[] value) { add(lflags, value); }
	void addLibs(string[] value) { add(libs, value); }
	void addFiles(string[] value) { add(files, value); }
	void addCopyFiles(string[] value) { add(copyFiles, value); }
	void addVersions(string[] value) { add(versions, value); }
	void addImportDirs(string[] value) { add(importPaths, value); }
	void addStringImportDirs(string[] value) { add(stringImportPaths, value); }

	// Adds vals to arr without adding duplicates.
	private void add(ref string[] arr, string[] vals)
	{
		foreach( v; vals ){
			bool found = false;
			foreach( i; 0 .. arr.length )
				if( arr[i] == v ){
					found = true;
					break;
				}
			if( !found ) arr ~= v;
		}
	}

	// Parses json and returns the values of the corresponding field 
	// by the platform.
	private string[] getPlatformField(in Json json, string name, BuildPlatform platform)
	const {
		auto ret = appender!(string[])();
		foreach( suffix; getPlatformSuffixIterator(platform) ){
			foreach( j; json[name~suffix].opt!(Json[]) )
				ret.put(j.get!string);
		}
		return ret.data;
	}
}

/// Based on the BuildPlatform, creates an iterator with all suffixes.
///
/// Suffixes are build upon the following scheme, where each component
/// is optional (indicated by []), but the order is obligatory.
/// "[-platform][-architecture][-compiler]"
///
/// So the following strings are valid suffixes:
/// "-windows-x86-dmd"
/// "-dmd"
/// "-arm"
///
int delegate(scope int delegate(ref string)) getPlatformSuffixIterator(BuildPlatform platform)
{
	int iterator(scope int delegate(ref string s) del)
	{
		auto c = platform.compiler;
		int delwrap(string s) { return del(s); }
		if( auto ret = delwrap(null) ) return ret;
		if( auto ret = delwrap("-"~c) ) return ret;
		foreach( p; platform.platform ){
			if( auto ret = delwrap("-"~p) ) return ret;
			if( auto ret = delwrap("-"~p~"-"~c) ) return ret;
			foreach( a; platform.architecture ){
				if( auto ret = delwrap("-"~p~"-"~a) ) return ret;
				if( auto ret = delwrap("-"~p~"-"~a~"-"~c) ) return ret;
			}
		}
		foreach( a; platform.architecture ){
			if( auto ret = delwrap("-"~a) ) return ret;
			if( auto ret = delwrap("-"~a~"-"~c) ) return ret;
		}
		return 0;
	}
	return &iterator;
}

/// Indicates where a package has been or should be installed to.
enum InstallLocation {
	Local,
	ProjectLocal,
	UserWide,
	SystemWide
}

/// Representing an installed package, usually constructed from a json object.
/// 
/// Json file example:
/// {
/// 		"name": "MetalCollection",
/// 		"author": "VariousArtists",
/// 		"version": "1.0.0",
///		"url": "https://github.org/...",
///		"keywords": "a,b,c",
///		"category": "music.best",
/// 		"dependencies": {
/// 			"black-sabbath": ">=1.0.0",
/// 			"CowboysFromHell": "<1.0.0",
/// 			"BeneathTheRemains": {"version": "0.4.1", "path": "./beneath-0.4.1"}
/// 		}
///		"licenses": {
///			...
///		}
///		"configurations": {
// TODO: what and how?
///		}
// TODO: plain like this or packed together?
///			"
///			"dflags-X"
///			"lflags-X"
///			"libs-X"
///			"files-X"
///			"copyFiles-X"
///			"versions-X"
///			"importPaths-X"
///			"stringImportPaths-X"	
///
/// 	}
///	}
///
/// TODO: explain configurations
class Package {
	static struct LocalPackageDef { string name; Version version_; Path path; }

	private {
		InstallLocation m_location;
		Path m_path;
		Json m_meta;
		Dependency[string] m_dependencies;
		LocalPackageDef[] m_localPackageDefs;
	}

	this(InstallLocation location, Path root)
	{
		this(jsonFromFile(root ~ PackageJsonFilename), location, root);
	}

	this(Json packageInfo, InstallLocation location = InstallLocation.Local, Path root = Path())
	{
		m_location = location;
		m_path = root;
		m_meta = packageInfo;

		// extract dependencies and local package definitions
		if( auto pd = "dependencies" in packageInfo ){
			foreach( string pkg, verspec; *pd ) {
				enforce(pkg !in m_dependencies, "The dependency '"~pkg~"' is specified more than once." );
				if( verspec.type == Json.Type.Object ){
					// full blown specifier
					auto ver = verspec["version"].get!string;
					m_dependencies[pkg] = new Dependency("==", ver);
					m_localPackageDefs ~= LocalPackageDef(pkg, Version(ver), Path(verspec.path.get!string()));
				} else {
					// canonical "package-id": "version"
					m_dependencies[pkg] = new Dependency(verspec.get!string());
				}
			}
		}
	}
	
	@property string name() const { return cast(string)m_meta["name"]; }
	@property string vers() const { return cast(string)m_meta["version"]; }
	@property Version ver() const { return Version(m_meta["version"].get!string); }
	@property installLocation() const { return m_location; }
	@property Path path() const { return m_path; }
	@property const(Url) url() const { return Url.parse(cast(string)m_meta["url"]); }
	@property const(Dependency[string]) dependencies() const { return m_dependencies; }
	@property const(LocalPackageDef)[] localPackageDefs() const { return m_localPackageDefs; }
	@property string binaryPath() const { return m_meta["binaryPath"].opt!string; }
	
	@property string[] configurations()
	const {
		auto pv = "configurations" in m_meta;
		if( !pv ) return null;
		auto ret = appender!(string[])();
		foreach( string k, _; *pv )
			ret.put(k);
		return ret.data;
	}

	/// Returns all BuildSettings for the given platform and config.
	BuildSettings getBuildSettings(BuildPlatform platform, string config)
	const {
		BuildSettings ret;
		ret.parse(m_meta, platform);
		if( config.length ){
			auto pcs = "configurations" in m_meta;
			if( !pcs ) return ret;
			auto pc = config in *pcs;
			if( !pc ) return ret;
			ret.parse(*pc, platform);
		}
		return ret;
	}
	
	/// Returns all sources as absolute paths.
	@property const(Path[]) sources() const {
		Path[] allSources;
		foreach(d; dirEntries((m_path ~ Path("source")).toNativeString(), "*.d", SpanMode.depth))
			allSources ~= Path(d.name);
		return allSources;
	}
	
	/// TODO: what is the defaul configuration?
	string getDefaultConfiguration(BuildPlatform platform)
	const {
		string ret;
		auto cfgs = m_meta["configurations"].opt!(Json[string]);
		foreach( suffix; getPlatformSuffixIterator(platform) )
			if( auto pv = ("default"~suffix) in cfgs )
				ret = pv.get!string();
		return ret;
	}

	/// Humanly readible information of this package and its dependencies.
	string info() const {
		string s;
		s ~= cast(string)m_meta["name"] ~ ", version '" ~ cast(string)m_meta["version"] ~ "'";
		s ~= "\n  Dependencies:";
		foreach(string p, ref const Dependency v; m_dependencies)
			s ~= "\n    " ~ p ~ ", version '" ~ to!string(v) ~ "'";
		return s;
	}
	
	/// direct access to the json of this package
	@property ref Json json() { return m_meta; }
	
	/// Writes the json file back to the filesystem
	void writeJson(Path path) {
		auto dstFile = openFile((path~PackageJsonFilename).toString(), FileMode.CreateTrunc);
		scope(exit) dstFile.close();
		Appender!string js;
		toPrettyJson(js, m_meta);
		dstFile.write( js.data );
	}
}
