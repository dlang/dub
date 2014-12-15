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
	enum BUILD_TYPES = [
		//"plain",
		"debug",
		"release",
		//"unittest",
		"docs",
		"ddox",
		"profile",
		"cov",
		"unittest-cov",
		];

	auto arch = buildPlatform.architecture[0];

	Json makeBuildSystem(string buildType)
	{
		return Json([
			"name": "DUB Build " ~ buildType.capitalize ~ " " ~ arch.Json,
			"cmd": ["dub", "build", "--build=" ~ buildType, "--arch=" ~ arch].map!Json.array.Json,
			"file_regex": r"^(.+)\(([0-9]+)\)\:() (.*)$".Json,
			"working_dir": workingDiretory.Json,
			"variants": [
				[
					"name": "Run".Json,
					"cmd": ["dub", "run", "--build=" ~ buildType, "--arch=" ~ arch].map!Json.array.Json,		
				].Json
			].array.Json,
		]);
	}

	auto buildSystems = BUILD_TYPES.map!makeBuildSystem.array;

	buildSystems ~= 	[
		"name": "DUB Test " ~ arch.Json,
		"cmd": ["dub", "test", "--arch=" ~ arch].map!Json.array.Json,
		"file_regex": r"^(.+)\(([0-9]+)\)\:() (.*)$".Json,
		"working_dir": workingDiretory.Json,
	].Json;

	return buildSystems.array.Json;
}

unittest
{
	auto buildPlatform = BuildPlatform();
	buildPlatform.architecture ~= "x86_64";

	auto result = buildPlatform.buildSystems.toString;
}
