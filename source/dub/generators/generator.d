/**
	Generator for project files
	
	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.generators.generator;

import dub.compilers.compiler;
import dub.generators.build;
import dub.generators.monod;
import dub.generators.rdmd;
import dub.generators.visuald;
import dub.package_;
import dub.packagemanager;
import dub.project;

import std.exception;
import std.file;
import std.string;
import vibecompat.core.file;
import vibecompat.core.log;
import vibecompat.inet.path;


/**
	Common interface for project generators/builders.
*/
interface ProjectGenerator
{
	void generateProject(GeneratorSettings settings);
}


struct GeneratorSettings {
	BuildPlatform platform;
	string config;
	Compiler compiler;
	string compilerBinary; // compiler executable name
	BuildSettings buildSettings;

	// only used for generator "rdmd"
	bool run;
	string[] runArgs;
	string buildType;
}


/**
	Creates a project generator of the given type for the specified project.
*/
ProjectGenerator createProjectGenerator(string generator_type, Project app, PackageManager mgr)
{
	assert(app !is null && mgr !is null, "Project and package manager needed to create a generator.");

	generator_type = generator_type.toLower();
	switch(generator_type) {
		default:
			throw new Exception("Unknown project generator: "~generator_type);
		case "build":
			logTrace("Creating build generator.");
			return new BuildGenerator(app, mgr);
		case "rdmd":
			logTrace("Creating rdmd generator.");
			return new RdmdGenerator(app, mgr);
		case "mono-d":
			logTrace("Creating MonoD generator.");
			return new MonoDGenerator(app, mgr);
		case "visuald": 
			logTrace("Creating VisualD generator.");
			return new VisualDGenerator(app, mgr);
	}
}

void addBuildTypeFlags(ref BuildSettings dst, string build_type)
{
	switch(build_type){
		default: throw new Exception("Unknown build type: "~build_type);
		case "plain": break;
		case "debug": dst.addDFlags("-g", "-debug"); break;
		case "release": dst.addDFlags("-release", "-O", "-inline"); break;
		case "unittest": dst.addDFlags("-g", "-unittest"); break;
		case "docs": dst.addDFlags("-c", "-o-", "-D", "-Dddocs"); break;
		case "ddox": dst.addDFlags("-c", "-o-", "-D", "-Df__dummy.html", "-Xfdocs.json"); break;
		case "profile": dst.addDFlags("-g", "-O", "-inline", "-profile"); break;
		case "cov": dst.addDFlags("-g", "-cov"); break;
		case "unittest-cov": dst.addDFlags("-g", "-unittest", "-cov"); break;
	}
}


/**
	Runs pre-build commands and performs an other required setup before project files are generated.
*/
void prepareGeneration(BuildSettings buildsettings)
{
	if( buildsettings.preGenerateCommands.length ){
		logInfo("Running pre-generate commands...");
		runBuildCommands(buildsettings.preGenerateCommands, buildsettings);
	}
}

/**
	Runs post-build commands and copies required files to the binary directory.
*/
void finalizeGeneration(BuildSettings buildsettings, bool generate_binary)
{
	if (buildsettings.postGenerateCommands.length) {
		logInfo("Running post-generate commands...");
		runBuildCommands(buildsettings.postGenerateCommands, buildsettings);
	}

	if (generate_binary && buildsettings.copyFiles.length) {
		logInfo("Copying files...");
		if (!exists(buildsettings.targetPath))
			mkdirRecurse(buildsettings.targetPath);
		foreach (f; buildsettings.copyFiles) {
			auto src = Path(f);
			auto dst = Path(buildsettings.targetPath) ~ Path(f).head;
			logDebug("  %s to %s", src.toNativeString(), dst.toNativeString());
			try {
				copyFile(src, dst, true);
			} catch logWarn("Failed to copy to %s", dst.toNativeString());
		}
	}
}

void runBuildCommands(string[] commands, in BuildSettings build_settings)
{
	import stdx.process;
	import dub.utils;

	string[string] env = environment.toAA();
	// TODO: do more elaborate things here
	// TODO: escape/quote individual items appropriately
	env["DFLAGS"] = join(cast(string[])build_settings.dflags, " ");
	env["LFLAGS"] = join(cast(string[])build_settings.lflags," ");
	env["VERSIONS"] = join(cast(string[])build_settings.versions," ");
	env["LIBS"] = join(cast(string[])build_settings.libs," ");
	env["IMPORT_PATHS"] = join(cast(string[])build_settings.importPaths," ");
	env["STRING_IMPORT_PATHS"] = join(cast(string[])build_settings.stringImportPaths," ");
	runCommands(commands, env);
}
