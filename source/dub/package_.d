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

	string[] getPlatformField(string name, BuildPlatform platform)
	const {
		auto c = platform.compiler;

		auto ret = appender!(string[])();
		// TODO: turn these loops around and iterate over m_metas fields instead for efficiency reason
		foreach( j; m_meta[name].opt!(Json[]) ) ret.put(j.get!string);
		foreach( j; m_meta[name~"-"~c].opt!(Json[]) ) ret.put(j.get!string);
		foreach( p; platform.platform ){
			foreach( j; m_meta[name~"-"~p].opt!(Json[]) ) ret.put(j.get!string);
			foreach( j; m_meta[name~"-"~p~"-"~c].opt!(Json[]) ) ret.put(j.get!string);
			foreach( a; platform.architecture ){
				foreach( j; m_meta[name~"-"~p~"-"~a].opt!(Json[]) ) ret.put(j.get!string);
				foreach( j; m_meta[name~"-"~p~"-"~a~"-"~c].opt!(Json[]) ) ret.put(j.get!string);
			}
		}
		return ret.data;

	}

	string[] getDflags(BuildPlatform platform) const { return getPlatformField("dflags", platform); }
	string[] getLibs(BuildPlatform platform) const { return getPlatformField("libs", platform); }
	
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
