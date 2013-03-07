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
import std.exception;
import vibecompat.data.json;
import vibecompat.inet.path;


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

	BuildPlatform determinePlatform(ref BuildSettings settings, string compiler_binary, string arch_override = null);

	/// Replaces high level fields with low level fields and converts
	/// dmd flags to compiler-specific flags
	void prepareBuildSettings(ref BuildSettings settings, BuildSetting supported_fields = BuildSetting.all);

	/// Adds the appropriate flag to set a target path
	void setTarget(ref BuildSettings settings, Path binary_path);
}


/// BuildPlatform specific settings, like needed libraries or additional
/// include paths.
struct BuildSettings {
	TargetType targetType;
	string[] dflags;
	string[] lflags;
	string[] libs;
	string[] sourceFiles;
	string[] copyFiles;
	string[] versions;
	string[] importPaths;
	string[] stringImportPaths;
	string[] preGenerateCommands;
	string[] postGenerateCommands;
	string[] preBuildCommands;
	string[] postBuildCommands;

	void addDFlags(in string[] value...) { add(dflags, value); }
	void addLFlags(in string[] value...) { add(lflags, value); }
	void addLibs(in string[] value...) { add(libs, value); }
	void addSourceFiles(in string[] value...) { add(sourceFiles, value); }
	void addCopyFiles(in string[] value...) { add(copyFiles, value); }
	void addVersions(in string[] value...) { add(versions, value); }
	void addImportPaths(in string[] value...) { add(importPaths, value); }
	void addStringImportPaths(in string[] value...) { add(stringImportPaths, value); }
	void addPreGenerateCommands(in string[] value...) { add(preGenerateCommands, value, false); }
	void addPostGenerateCommands(in string[] value...) { add(postGenerateCommands, value, false); }
	void addPreBuildCommands(in string[] value...) { add(preBuildCommands, value, false); }
	void addPostBuildCommands(in string[] value...) { add(postBuildCommands, value, false); }

	// Adds vals to arr without adding duplicates.
	private void add(ref string[] arr, in string[] vals, bool no_duplicates = true)
	{
		if( !no_duplicates ){
			arr ~= vals;
			return;
		}

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
	sourceFiles       = 1<<3,
	copyFiles         = 1<<4,
	versions          = 1<<5,
	importPaths       = 1<<6,
	stringImportPaths = 1<<7,
	none = 0,
	commandLine = dflags|copyFiles,
	commandLineSeparate = commandLine|lflags,
	all = dflags|lflags|libs|sourceFiles|copyFiles|versions|importPaths|stringImportPaths
}

enum TargetType {
	autodetect,
	executable,
	library,
	sourceLibrary,
	dynamicLibrary,
	staticLibrary
}


private {
	Compiler[] s_compilers;
}
