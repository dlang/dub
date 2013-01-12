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
import vibe.core.file;
import vibe.data.json;
import vibe.inet.url;

struct BuildPlatform {
	string[] platform;
	string[] architecture;
	string compiler;
}

struct BuildSettings {
	string[] dflags;
	string[] lflags;
	string[] libs;
	string[] versions;
	string[] importPath;
	string[] stringImportPath;

	void parse(in Json root, BuildPlatform platform)
	{
		addDFlags(getPlatformField(root, "dflags", platform));
		addLFlags(getPlatformField(root, "lflags", platform));
		addLibs(getPlatformField(root, "libs", platform));
		addVersions(getPlatformField(root, "versions", platform));
		addImportDirs(getPlatformField(root, "importPath", platform));
		addStringImportDirs(getPlatformField(root, "stringImportPath", platform));
	}

	void addDFlags(string[] value) { add(dflags, value); }
	void addLFlags(string[] value) { add(lflags, value); }
	void addLibs(string[] value) { add(libs, value); }
	void addVersions(string[] value) { add(versions, value); }
	void addImportDirs(string[] value) { add(importPath, value); }
	void addStringImportDirs(string[] value) { add(stringImportPath, value); }

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

	private string[] getPlatformField(in Json json, string name, BuildPlatform platform)
	const {
		auto c = platform.compiler;

		auto ret = appender!(string[])();
		// TODO: turn these loops around and iterate over m_metas fields instead for efficiency reason
		foreach( j; json[name].opt!(Json[]) ) ret.put(j.get!string);
		foreach( j; json[name~"-"~c].opt!(Json[]) ) ret.put(j.get!string);
		foreach( p; platform.platform ){
			foreach( j; json[name~"-"~p].opt!(Json[]) ) ret.put(j.get!string);
			foreach( j; json[name~"-"~p~"-"~c].opt!(Json[]) ) ret.put(j.get!string);
			foreach( a; platform.architecture ){
				foreach( j; json[name~"-"~p~"-"~a].opt!(Json[]) ) ret.put(j.get!string);
				foreach( j; json[name~"-"~p~"-"~a~"-"~c].opt!(Json[]) ) ret.put(j.get!string);
			}
		}
		return ret.data;

	}
}

/// Representing an installed package
// Json file example:
// {
// 		"name": "MetalCollection",
// 		"author": "VariousArtists",
// 		"version": "1.0.0",
//		"url": "https://github.org/...",
//		"keywords": "a,b,c",
//		"category": "music.best",
// 		"dependencies": {
// 			"black-sabbath": ">=1.0.0",
// 			"CowboysFromHell": "<1.0.0",
// 			"BeneathTheRemains": ">=1.0.3"
// 		}
//		"licenses": {
//			...
//		}
// }
class Package {
	private {
		Json m_meta;
		Dependency[string] m_dependencies;
	}
	
	this(Path root) {
		m_meta = jsonFromFile(root ~ "package.json");
		m_dependencies = .dependencies(m_meta);
	}
	this(Json json) {
		m_meta = json;
		m_dependencies = .dependencies(m_meta);
	}
	
	@property string name() const { return cast(string)m_meta["name"]; }
	@property string vers() const { return cast(string)m_meta["version"]; }
	@property const(Url) url() const { return Url.parse(cast(string)m_meta["url"]); }
	@property const(Dependency[string]) dependencies() const { return m_dependencies; }
	@property string[] configurations()
	const {
		auto pv = "configurations" in m_meta;
		if( !pv ) return null;
		auto ret = appender!(string[])();
		foreach( string k, _; *pv )
			ret.put(k);
		return ret.data;
	}

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
		auto dstFile = openFile((path~"package.json").toString(), FileMode.CreateTrunc);
		scope(exit) dstFile.close();
		Appender!string js;
		toPrettyJson(js, m_meta);
		dstFile.write( js.data );
	}
}
