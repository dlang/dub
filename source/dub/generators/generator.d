/**
	Generator for project files
	
	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.generators.generator;

import dub.dub;
import dub.packagemanager;
import dub.generators.visuald;

/// A project generator generates projects :-/
interface ProjectGenerator
{
	void generateProject();
}

/// Creates a project generator.
ProjectGenerator createProjectGenerator(string projectType, Application app, PackageManager store) {
	switch(projectType) { 
		default: return null;
		case "VisualD": return new VisualDGenerator(app, store);
	}
}