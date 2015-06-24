/**
	Pseudo generator to output build descriptions.

	Copyright: © 2015 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.generators.targetdescription;

import dub.compilers.buildsettings;
import dub.compilers.compiler;
import dub.description;
import dub.generators.generator;
import dub.internal.vibecompat.inet.path;
import dub.project;

class TargetDescriptionGenerator : ProjectGenerator {
	TargetDescription[] targetDescriptions;
	size_t[string] targetDescriptionLookup;

	this(Project project)
	{
		super(project);
	}

	protected override void generateTargets(GeneratorSettings settings, in TargetInfo[string] targets)
	{
		auto configs = m_project.getPackageConfigs(settings.platform, settings.config);
		targetDescriptions.length = targets.length;
		size_t i = 0;
		size_t rootIndex;
		foreach (t; targets) {
			if (t.pack.name == m_project.rootPackage.name)
				rootIndex = i;

			TargetDescription d;
			d.rootPackage = t.pack.name;
			d.packages = t.packages.map!(p => p.name).array;
			d.rootConfiguration = t.config;
			d.buildSettings = t.buildSettings.dup;
			d.dependencies = t.dependencies.dup;
			d.linkDependencies = t.linkDependencies.dup;

			targetDescriptionLookup[d.rootPackage] = i;
			targetDescriptions[i++] = d;
		}

		// Add static library dependencies
		auto bs = targetDescriptions[rootIndex].buildSettings;
		foreach (ref desc; targetDescriptions) {
			foreach (linkDepName; desc.linkDependencies) {
				auto linkDepTarget = targetDescriptions[ targetDescriptionLookup[linkDepName] ];
				auto dbs = linkDepTarget.buildSettings;
				if (bs.targetType != TargetType.staticLibrary) {
					auto linkerFile = (Path(dbs.targetPath) ~ getTargetFileName(dbs, settings.platform)).toNativeString();
					bs.addLinkerFiles(linkerFile);
					bs.addSourceFiles(linkerFile); // To be removed from sourceFiles in the future
				}
			}
		}
		targetDescriptions[rootIndex].buildSettings = bs;
	}
}
