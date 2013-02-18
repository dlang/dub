/**
	Compiler settings and abstraction.

	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.compiler;

import dub.compilers.dmd;
import dub.compilers.gdc;
import dub.compilers.ldc;

import std.algorithm;
import std.array;
import vibe.data.json;
import vibe.inet.path;


static this()
{
	registerCompiler(new DmdCompiler);
	registerCompiler(new GdcCompiler);
	registerCompiler(new LdcCompiler);
}


Compiler getCompiler(string name)
{
	foreach( c; s_compilers )
		if( c.name == name )
			return c;

	// try to match names like gdmd or gdc-2.61
	if( name.canFind("dmd") ) return getCompiler("dmd");
	if( name.canFind("gdc") ) return getCompiler("gdc");
	if( name.canFind("ldc") ) return getCompiler("ldc");
			
	throw new Exception("Unknown compiler: "~name);
}

void registerCompiler(Compiler c)
{
	s_compilers ~= c;
}


interface Compiler {
	@property string name() const;

	/// Replaces high level fields with low level fields and converts
	/// dmd flags to compiler-specific flags
	void prepareBuildSettings(ref BuildSettings settings, BuildSetting supported_fields = BuildSetting.all);

	/// Adds the appropriate flag to set a target path
	void setTarget(ref BuildSettings settings, Path binary_path);
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

	void addDFlags(string[] value...) { add(dflags, value); }
	void addLFlags(string[] value...) { add(lflags, value); }
	void addLibs(string[] value...) { add(libs, value); }
	void addFiles(string[] value...) { add(files, value); }
	void addCopyFiles(string[] value...) { add(copyFiles, value); }
	void addVersions(string[] value...) { add(versions, value); }
	void addImportDirs(string[] value...) { add(importPaths, value); }
	void addStringImportDirs(string[] value...) { add(stringImportPaths, value); }

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

/// Represents a platform a package can be build upon.
struct BuildPlatform {
	/// e.g. ["posix", "windows"]
	string[] platform;
	/// e.g. ["x86", "x64"]
	string[] architecture;
	/// e.g. "dmd"
	string compiler;
}

enum BuildSetting {
	dflags            = 1<<0,
	lflags            = 1<<1,
	libs              = 1<<2,
	files             = 1<<3,
	copyFiles         = 1<<4,
	versions          = 1<<5,
	importPaths       = 1<<6,
	stringImportPaths = 1<<7,
	none = 0,
	commandLine = dflags|copyFiles,
	commandLineSeparate = commandLine|lflags,
	all = dflags|lflags|libs|files|copyFiles|versions|importPaths|stringImportPaths
}

private {
	Compiler[] s_compilers;
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
