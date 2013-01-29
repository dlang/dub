/**
	Generator for project files
	
	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.generators.generator;

import dub.project;
import dub.packagemanager;
import dub.generators.monod;
import dub.generators.visuald;
import vibe.core.log;
import std.exception;

/// A project generator generates projects :-/
interface ProjectGenerator
{
	void generateProject();
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