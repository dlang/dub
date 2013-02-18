/**
	LDC compiler support.

	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.ldc;

import dub.compilers.compiler;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import stdx.process;
import vibe.core.log;
import vibe.inet.path;


class LdcCompiler : Compiler {
	@property string name() const { return "ldc"; }

	void prepareBuildSettings(ref BuildSettings settings, BuildSetting fields = BuildSetting.all)
	{
		// convert common DMD flags to the corresponding GDC flags
		string[] newdflags;
		foreach(f; settings.dflags){
			switch(f){
				default: newdflags ~= f; break;
			}
		}
		settings.dflags = newdflags;
	
		if( !(fields & BuildSetting.libs) ){
			try {
				logDebug("Trying to use pkg-config to resolve library flags for %s.", settings.libs);
				auto libflags = execute("pkg-config", "--libs" ~ settings.libs.map!(l => "lib"~l)().array());
				enforce(libflags.status == 0, "pkg-config exited with error code "~to!string(libflags.status));
				settings.addLFlags(libflags.output.split());
			} catch( Exception e ){
				logDebug("pkg-config failed: %s", e.msg);
				logDebug("Falling back to direct -lxyz flags.");
				settings.addLFlags(settings.libs.map!(l => "-l"~l)().array());
			}
			settings.libs = null;
		}

		if( !(fields & BuildSetting.versions) ){
			settings.addDFlags(settings.versions.map!(s => "-d-version="~s)().array());
			settings.versions = null;
		}

		if( !(fields & BuildSetting.importPaths) ){
			settings.addDFlags(settings.importPaths.map!(s => "-I"~s)().array());
			settings.importPaths = null;
		}

		if( !(fields & BuildSetting.stringImportPaths) ){
			settings.addDFlags(settings.stringImportPaths.map!(s => "-J"~s)().array());
			settings.stringImportPaths = null;
		}

		if( !(fields & BuildSetting.files) ){
			settings.addDFlags(settings.files);
			settings.files = null;
		}

		if( !(fields & BuildSetting.lflags) ){
			settings.addDFlags(settings.stringImportPaths.map!(s => "-L="~s)().array());
			settings.lflags = null;
		}

		assert(fields & BuildSetting.dflags);
		assert(fields & BuildSetting.copyFiles);
	}

	void setTarget(ref BuildSettings settings, Path binary_path)
	{
		settings.addDFlags("-of"~binary_path.toNativeString());
	}
}
