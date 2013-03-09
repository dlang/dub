/**
	LDC compiler support.

	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.ldc;

import dub.compilers.compiler;
import dub.platform;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import stdx.process;
import vibecompat.core.log;
import vibecompat.inet.path;


class LdcCompiler : Compiler {
	@property string name() const { return "ldc"; }

	BuildPlatform determinePlatform(ref BuildSettings settings, string compiler_binary, string arch_override)
	{
		// TODO: determine platform by invoking the compiler instead
		BuildPlatform build_platform;
		build_platform.platform = .determinePlatform();
		build_platform.architecture = .determineArchitecture();
		build_platform.compiler = this.name;

		enforce(arch_override.length == 0, "Architecture override not implemented for LDC.");
		return build_platform;
	}

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
				auto libflags = execute(["pkg-config", "--libs"] ~ settings.libs.map!(l => "lib"~l)().array());
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

		if( !(fields & BuildSetting.sourceFiles) ){
			settings.addDFlags(settings.sourceFiles);
			settings.sourceFiles = null;
		}

		if( !(fields & BuildSetting.lflags) ){
			settings.addDFlags(settings.stringImportPaths.map!(s => "-L="~s)().array());
			settings.lflags = null;
		}

		assert(fields & BuildSetting.dflags);
		assert(fields & BuildSetting.copyFiles);
	}

	void setTarget(ref BuildSettings settings, in BuildPlatform platform)
	{
		final switch(settings.targetType){
			case TargetType.autodetect: assert(false, "Invalid target type: autodetect");
			case TargetType.sourceLibrary: assert(false, "Invalid target type: sourceLibrary");
			case TargetType.executable: break;
			case TargetType.library:
			case TargetType.staticLibrary:
				assert(false, "No LDC static libraries supported");
				break;
			case TargetType.dynamicLibrary:
				assert(false, "No LDC dynamic libraries supported");
				break;
		}

		auto tpath = Path(settings.targetPath) ~ getTargetFileName(settings, platform);
		settings.addDFlags("-of"~tpath.toNativeString());
	}

	void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects)
	{
		assert(false, "Separate linking not implemented for GDC");
	}
}
