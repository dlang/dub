/**
	Generator for project files
	
	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.generators.generator;

import dub.compilers.compiler;
import dub.generators.monod;
import dub.generators.visuald;
import dub.package_;
import dub.packagemanager;
import dub.project;

import std.exception;
import vibe.core.log;


/// A project generator generates projects :-/
interface ProjectGenerator
{
	void generateProject(BuildPlatform build_platform);
}

/// Creates a project generator.
ProjectGenerator createProjectGenerator(string projectType, Project app, PackageManager mgr) {
	enforce(app !is null, "app==null, Need an application to work on!");
	enforce(mgr !is null, "mgr==null, Need a package manager to work on!");
	switch(projectType) {
		default: return null;
		case "MonoD":
			logTrace("Generating MonoD generator.");
			return new MonoDGenerator(app, mgr);
		case "VisualD": 
			logTrace("Generating VisualD generator.");
			return new VisualDGenerator(app, mgr);
	}
}