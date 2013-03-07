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
import std.string;
import vibecompat.core.log;


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
		case "profile": dst.addDFlags("-g", "-O", "-inline", "-profile"); break;
		case "docs": dst.addDFlags("-c", "-o-", "-D", "-Dddocs"); break;
		case "ddox": dst.addDFlags("-c", "-o-", "-D", "-Df__dummy.html", "-Xfdocs.json"); break;
	}
}
