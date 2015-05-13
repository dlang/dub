/**
	Pseudo generator to output build descriptions.

	Copyright: © 2015 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.generators.targetdescription;

import dub.description;
import dub.generators.generator;
import dub.project;

class TargetDescriptionGenerator : ProjectGenerator {
	TargetDescription[] targetDescriptions;

	this(Project project)
	{
		super(project);
	}

	protected override void generateTargets(GeneratorSettings settings, in TargetInfo[string] targets)
	{
		targetDescriptions.length = targets.length;
		size_t i = 0;
		foreach (t; targets) {
			TargetDescription d;
			d.rootPackage = t.pack.name;
			d.packages = t.packages.map!(p => p.name).array;
			d.rootConfiguration = t.config;
			d.buildSettings = t.buildSettings.dup;
			d.dependencies = t.dependencies.dup;
			d.linkDependencies = t.linkDependencies.dup;
			targetDescriptions[i++] = d;
		}
	}
}
