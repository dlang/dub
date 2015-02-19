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
			"folders": targets.byValue.map!targetFolderJson.array.Json,
			"build_systems": buildSystems(settings.platform),
		]);

		auto jsonString = appender!string();
		writePrettyJsonString(jsonString, root);

		write(m_project.name ~ ".sublime-project", jsonString.data);

		logInfo("SublimeText project generated.");
	}
}


Json targetFolderJson(in ProjectGenerator.TargetInfo target)
{
	return [
		"name": target.pack.name.Json,
		"path": target.pack.path.toNativeString.Json,
		"follow_symlinks": true.Json,
		"folder_exclude_patterns": [".dub"].map!Json.array.Json,
	].Json;
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
			"name": "DUB build " ~ buildType.Json,
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
		"name": "DUB test".Json,
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
