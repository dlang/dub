/**
	Stuff with dependencies.

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.package_;

import dub.compilers.compiler;
import dub.dependency;
import dub.utils;

import std.array;
import std.conv;
import std.exception;
import std.file;
import vibecompat.core.log;
import vibecompat.core.file;
import vibecompat.data.json;
import vibecompat.inet.url;

enum PackageJsonFilename = "package.json";


/// Indicates where a package has been or should be installed to.
enum InstallLocation {
	local,
	projectLocal,
	userWide,
	systemWide
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
///			"sourcePath"
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

	this(Json packageInfo, InstallLocation location = InstallLocation.local, Path root = Path())
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
	
	/// Returns all sources as relative paths, prepend each with 
	/// path() to get the absolute one.
	@property const(Path[]) sources() const {
		Path[] allSources;
		auto sourcePath = Path("source");
		auto customSourcePath = "sourcePath" in m_meta;
		if(customSourcePath)
			sourcePath = Path(customSourcePath.get!string());
		logTrace("Parsing directory for sources: %s", m_path ~ sourcePath);
		foreach(d; dirEntries((m_path ~ sourcePath).toNativeString(), "*.d", SpanMode.depth)) {
			// direct assignment allSources ~= Path(d.name)[...] spawns internal compiler/linker error
			if(isDir(d.name)) continue;
			auto p = Path(d.name);
			allSources ~= p[m_path.length..$];
		}
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
		dstFile.writePrettyJsonString(m_meta);
	}

	/// Adds an dependency, if the package is already a dependency and it cannot be
	/// merged with the supplied dependency, an exception will be generated.
	void addDependency(string packageId, const Dependency dependency) {
		Dependency dep = new Dependency(dependency);
		if(packageId in m_dependencies) { 
			dep = dependency.merge(m_dependencies[packageId]);
			if(!dep.valid()) throw new Exception("Cannot merge with existing dependency.");
		}
		m_dependencies[packageId] = dep;
		Json[string] empty;
		if("dependencies" !in m_meta) m_meta["dependencies"] = empty;
		m_meta["dependencies"][packageId] = Json(to!string(dep));
	}

	/// Removes a dependecy.
	void removeDependency(string packageId) {
		if(packageId !in m_dependencies)
			return;
		m_dependencies.remove(packageId);
		m_meta.remove(packageId);
	}
} 