/**
	DMD compiler support.

	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.dmd;

import dub.compilers.compiler;
import dub.platform;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import stdx.process;
import vibecompat.core.log;
import vibecompat.inet.path;


class DmdCompiler : Compiler {
	@property string name() const { return "dmd"; }

	BuildPlatform determinePlatform(ref BuildSettings settings, string compiler_binary, string arch_override)
	{
		// TODO: determine platform by invoking the compiler instead
		BuildPlatform build_platform;
		build_platform.platform = .determinePlatform();
		build_platform.architecture = .determineArchitecture();
		build_platform.compiler = this.name;

		switch(arch_override){
			default: throw new Exception("Unsupported architecture: "~arch_override);
			case "": break;
			case "x86":
				build_platform.architecture = ["x86"];
				settings.addDFlags("-m32");
				break;
			case "x86_64":
				build_platform.architecture = ["x86_64"];
				settings.addDFlags("-m64");
				break;
		}
		return build_platform;
	}

	void prepareBuildSettings(ref BuildSettings settings, BuildSetting fields = BuildSetting.all)
	{
		if( !(fields & BuildSetting.libs) ){
			try {
				logDebug("Trying to use pkg-config to resolve library flags for %s.", settings.libs);
				auto libflags = execute(["pkg-config", "--libs"] ~ settings.libs.map!(l => "lib"~l)().array());
				enforce(libflags.status == 0, "pkg-config exited with error code "~to!string(libflags.status));
				settings.addLFlags(libflags.output.split());
			} catch( Exception e ){
				logDebug("pkg-config failed: %s", e.msg);
				logDebug("Falling back to direct -lxyz flags.");
				version(Windows) settings.addSourceFiles(settings.libs.map!(l => l~".lib")().array());
				else settings.addLFlags(settings.libs.map!(l => "-l"~l)().array());
			}
			settings.libs = null;
		}

		if( !(fields & BuildSetting.versions) ){
			settings.addDFlags(settings.versions.map!(s => "-version="~s)().array());
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
			settings.addDFlags(settings.lflags.map!(f => "-L"~f)().array());
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
				settings.addDFlags("-lib");
				break;
			case TargetType.dynamicLibrary:
				break;
		}

		auto tpath = Path(settings.targetPath) ~ getTargetFileName(settings, platform);
		settings.addDFlags("-of"~tpath.toNativeString());
	}
}
