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
import vibe.data.json;
import vibe.inet.path;
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
			"folders": targets.byValue.map!(f => targetFolderJson(f)).array.Json,
			"build_systems": buildSystems(settings.platform),
			"settings": [ "include_paths": buildSettings.importPaths.map!Json.array.Json ].Json,
		]);

		auto jsonString = appender!string();
		writePrettyJsonString(jsonString, root);

		string projectPath = m_project.name ~ ".sublime-project";

		write(projectPath, jsonString.data);

		logInfo("Project '%s' generated.", projectPath);
	}
}


private Json targetFolderJson(in ProjectGenerator.TargetInfo target)
{
	return [
		"name": target.pack.basePackage.name.Json,
		"path": target.pack.basePackage.path.toNativeString.Json,
		"follow_symlinks": true.Json,
		"folder_exclude_patterns": [".dub"].map!Json.array.Json,
	].Json;
}


private Json buildSystems(BuildPlatform buildPlatform, string workingDiretory = getcwd())
{
	static immutable BUILD_TYPES = [
		//"plain",
		"debug",
		"release",
		"release-debug",
		"release-nobounds",
		//"unittest",
		"docs",
		"ddox",
		"profile",
		"profile-gc",
		"cov",
		"unittest-cov",
		"syntax"
		];

	string fileRegex;

	if (buildPlatform.frontendVersion >= 2066 && buildPlatform.compiler == "dmd")
		fileRegex = r"^(.+)\(([0-9]+)\,([0-9]+)\)\: (.*)$";
	else
		fileRegex = r"^(.+)\(([0-9]+)\)\:() (.*)$";

	auto arch = buildPlatform.architecture[0];

	Json makeBuildSystem(string buildType)
	{
		return Json([
			"name": "DUB build " ~ buildType.Json,
			"cmd": ["dub", "build", "--build=" ~ buildType, "--arch=" ~ arch, "--compiler="~buildPlatform.compilerBinary].map!Json.array.Json,
			"file_regex": fileRegex.Json,
			"working_dir": workingDiretory.Json,
			"variants": [
				[
					"name": "Run".Json,
					"cmd": ["dub", "run", "--build=" ~ buildType, "--arch=" ~ arch, "--compiler="~buildPlatform.compilerBinary].map!Json.array.Json,
				].Json
			].array.Json,
		]);
	}

	auto buildSystems = BUILD_TYPES.map!makeBuildSystem.array;

	buildSystems ~= 	[
		"name": "DUB test".Json,
		"cmd": ["dub", "test", "--arch=" ~ arch, "--compiler="~buildPlatform.compilerBinary].map!Json.array.Json,
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
