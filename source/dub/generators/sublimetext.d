/**
Generator for SublimeText project files

Copyright: © 2014 Nicholas Londey
License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
Authors: Nicholas Londey
*/
module dub.generators.sublimetext;

import dub.compilers.compiler;
import dub.generators.generator;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.data.json;
import dub.packagemanager;
import dub.project;

import std.algorithm;
import std.array;
import std.compiler;
import std.file;
import std.path;
import std.range;
import std.string;


class SublimeTextGenerator : ProjectGenerator {

	this(Project project)
	{
		super(project);
	}

	override void generateTargets(GeneratorSettings settings, in TargetInfo[string] targets)
	{
		auto buildSettings = targets[m_project.name].buildSettings;
		logDebug("About to generate sublime project for %s.", m_project.rootPackage.name);
		
		auto root = Json([
			"folders": targets.byValue.map!sourceFolderJson.joiner.array.Json,
			"build_systems": buildSystems(settings.platform),
		]);

		auto jsonString = appender!string();
		writePrettyJsonString(jsonString, root);

		write(m_project.name ~ ".sublime-project", jsonString.data);

		logInfo("SublimeText project generated.");
	}
}


Json[] sourceFolderJson(in ProjectGenerator.TargetInfo target)
{
	Json createFolderPath(string path)
	{
		return Json([
			"path": path.Json,
			"name": (target.pack.name ~ "/" ~ path.baseName).Json,
			"follow_symlinks": true.Json,
		]);
	}

	auto allImportPaths = chain(target.buildSettings.importPaths, target.buildSettings.stringImportPaths);
	return allImportPaths.map!createFolderPath.array;
}


Json buildSystems(BuildPlatform buildPlatform, string workingDiretory = getcwd())
{
	Json makeBuildSystem(string operation)
	{
		auto arch = buildPlatform.architecture[0];
		return Json([
			"name": "DUB " ~ operation.capitalize ~ " " ~ arch.Json,
			"cmd": ["dub", operation.toLower, "--arch=" ~ arch].map!Json.array.Json,
			"working_dir": workingDiretory.Json,
		]);
	}

	return ["run", "build", "test"].map!makeBuildSystem.array.Json;
}

unittest
{
	auto buildPlatform = BuildPlatform();
	buildPlatform.architecture ~= "x86_64";

	auto result = buildPlatform.buildSystems.toString;
}
