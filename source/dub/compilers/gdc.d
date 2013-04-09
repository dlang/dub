/**
	GDC compiler support.

	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.gdc;

import dub.compilers.compiler;
import dub.platform;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import stdx.process;
import vibecompat.core.log;
import vibecompat.inet.path;


class GdcCompiler : Compiler {
	@property string name() const { return "gdc"; }

	BuildPlatform determinePlatform(ref BuildSettings settings, string compiler_binary, string arch_override)
	{
		// TODO: determine platform by invoking the compiler instead
		BuildPlatform build_platform;
		build_platform.platform = .determinePlatform();
		build_platform.architecture = .determineArchitecture();
		build_platform.compiler = this.name;

		enforce(arch_override.length == 0, "Architecture override not implemented for GDC.");
		return build_platform;
	}

	void prepareBuildSettings(ref BuildSettings settings, BuildSetting fields = BuildSetting.all)
	{
		// convert common DMD flags to the corresponding GDC flags
		string[] newdflags;
		foreach(f; settings.dflags){
			switch(f){
				default: newdflags ~= f; break;
				case "-cov": newdflags ~= ["-fprofile-arcs", "-ftest-coverage"]; break;
				case "-D": newdflags ~= "-fdoc"; break;
				//case "-Dd[dir]": newdflags ~= ""; break;
				//case "-Df[file]": newdflags ~= ""; break;
				case "-d": newdflags ~= "-fdeprecated"; break;
				case "-dw": break;
				case "-de": break;
				case "-debug": newdflags ~= "-fdebug"; break;
				//case "-debug=[level/ident]": newdflags ~= ""; break;
				//case "-debuglib=[ident]": newdflags ~= ""; break;
				//case "-defaultlib=[ident]": newdflags ~= ""; break;
				//case "-deps=[file]": newdflags ~= ""; break;
				case "-fPIC": newdflags ~= ""; break;
				case "-g": newdflags ~= "-g"; break;
				case "-gc": newdflags ~= ["-g" ~ "-fdebug-c"]; break;
				case "-gs": break;
				case "-H": newdflags ~= "-fintfc"; break;
				//case "-Hd[dir]": newdflags ~= ""; break;
				//case "-Hf[file]": newdflags ~= ""; break;
				case "-ignore": newdflags ~= "-fignore-unknown-pragmas"; break;
				case "-inline": newdflags ~= "-finline-functions"; break;
				//case "-lib": newdflags ~= ""; break;
				//case "-m32": newdflags ~= ""; break;
				//case "-m64": newdflags ~= ""; break;
				case "-noboundscheck": newdflags ~= "-fno-bounds-check"; break;
				case "-O": newdflags ~= "-O3"; break;
				case "-o-": newdflags ~= "-fsyntax-only"; break;
				//case "-od[dir]": newdflags ~= ""; break;
				//case "-of[file]": newdflags ~= ""; break;
				//case "-op": newdflags ~= ""; break;
				//case "-profile": newdflags ~= "-pg"; break;
				case "-property": newdflags ~= "-fproperty"; break;
				//case "-quiet": newdflags ~= ""; break;
				case "-release": newdflags ~= "-frelease"; break;
				case "-shared": newdflags ~= "-shared"; break;
				case "-unittest": newdflags ~= "-funittest"; break;
				case "-v": newdflags ~= "-fd-verbose"; break;
				//case "-version=[level/ident]": newdflags ~= ""; break;
				case "-vtls": newdflags ~= "-fd-vtls"; break;
				case "-w": newdflags ~= "-Werror"; break;
				case "-wi": newdflags ~= "-Wall"; break;
				//case "-X": newdflags ~= ""; break;
				//case "-Xf[file]": newdflags ~= ""; break;
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
			settings.addDFlags(settings.versions.map!(s => "-fversion="~s)().array());
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
			foreach( f; settings.lflags )
				settings.addDFlags(["-Xlinker", f]);
			settings.lflags = null;
		}

		if (settings.requirements & BuildRequirements.allowWarnings) { settings.removeDFlags("-Werror"); settings.addDFlags("-Wall"); }
		if (settings.requirements & BuildRequirements.silenceWarnings) { settings.removeDFlags("-Werror", "-Wall"); }
		if (settings.requirements & BuildRequirements.disallowDeprecations) { settings.addDFlags("-fdeprecated"); }
		if (settings.requirements & BuildRequirements.silenceDeprecations) { settings.addDFlags("-fdeprecated"); }
		if (settings.requirements & BuildRequirements.disallowInlining) { settings.removeDFlags("-finline-functions"); }
		if (settings.requirements & BuildRequirements.disallowOptimization) { settings.removeDFlags("-O3"); }
		if (settings.requirements & BuildRequirements.requireBoundsCheck) { settings.removeDFlags("-fno-bounds-check"); }
		if (settings.requirements & BuildRequirements.requireContracts) { settings.removeDFlags("-frelease"); }
		if (settings.requirements & BuildRequirements.relaxProperties) { settings.removeDFlags("-fproperty"); }

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
				settings.addDFlags("-c");
				break;
			case TargetType.dynamicLibrary:
				settings.addDFlags("-shared", "-fPIC");
				break;
		}

		auto tpath = Path(settings.targetPath) ~ getTargetFileName(settings, platform);
		settings.addDFlags("-o", tpath.toNativeString());
	}

	void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects)
	{
		assert(false, "Separate linking not implemented for GDC");
	}
}
