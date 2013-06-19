/**
	LDC compiler support.

	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.ldc;

import dub.compilers.compiler;
import dub.internal.std.process;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.inet.path;
import dub.platform;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;


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
				case "-debug": newdflags ~= "-d-debug"; break;
			}
		}
		settings.dflags = newdflags;

		// since LDC always outputs multiple object files, avoid conflicts by default
		settings.addDFlags("-oq", "-od=.dub/obj");
	
		if (!(fields & BuildSetting.libs))
			resolveLibs(settings);

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
			settings.addDFlags(settings.lflags.map!(s => "-L="~s)().array());
			settings.lflags = null;
		}

		if (settings.requirements & BuildRequirements.allowWarnings) { settings.removeDFlags("-w"); settings.addDFlags("-wi"); }
		if (settings.requirements & BuildRequirements.silenceWarnings) { settings.removeDFlags("-w", "-wi"); }
		if (settings.requirements & BuildRequirements.disallowDeprecations) { settings.removeDFlags("-dw", "-d"); settings.addDFlags("-de"); }
		if (settings.requirements & BuildRequirements.silenceDeprecations) { settings.removeDFlags("-dw", "-de"); settings.addDFlags("-d"); }
		if (settings.requirements & BuildRequirements.disallowInlining) { settings.removeDFlags("-inline"); }
		if (settings.requirements & BuildRequirements.disallowOptimization) { settings.removeDFlags("-O"); }
		if (settings.requirements & BuildRequirements.requireBoundsCheck) { settings.removeDFlags("-noboundscheck"); }
		if (settings.requirements & BuildRequirements.requireContracts) { settings.removeDFlags("-release"); }
		if (settings.requirements & BuildRequirements.relaxProperties) { settings.removeDFlags("-property"); }

		assert(fields & BuildSetting.dflags);
		assert(fields & BuildSetting.copyFiles);
	}

	void setTarget(ref BuildSettings settings, in BuildPlatform platform)
	{
		final switch(settings.targetType){
			case TargetType.autodetect: assert(false, "Invalid target type: autodetect");
			case TargetType.none: assert(false, "Invalid target type: none");
			case TargetType.sourceLibrary: assert(false, "Invalid target type: sourceLibrary");
			case TargetType.executable: break;
			case TargetType.library:
			case TargetType.staticLibrary:
				assert(false, "No LDC static libraries supported");
			case TargetType.dynamicLibrary:
				assert(false, "No LDC dynamic libraries supported");
		}

		auto tpath = Path(settings.targetPath) ~ getTargetFileName(settings, platform);
		settings.addDFlags("-of"~tpath.toNativeString());
	}

	void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects)
	{
		assert(false, "Separate linking not implemented for GDC");
	}
}
