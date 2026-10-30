/+ dub.sdl:
   name "ninja-generator-regen"
   dependency "common" path="./common"
 +/

module ninja_generator_regen;

import std.process : environment, execute, Config;
import std.path : buildPath, dirName;
import std.file : readText, remove, mkdirRecurse, rmdirRecurse, write;
import std.algorithm : canFind;
import core.thread : Thread;
import core.time : seconds;

import common;

bool regenUpdatesImportPath(string projDir, string recipePath, string origRecipe, string newRecipe)
{
	const buildNinjaPath = buildPath(projDir, "build.ninja");
	const importDir = buildPath(projDir, "extra-imports");

	mkdirRecurse(importDir);
	scope(exit) rmdirRecurse(importDir);

	Thread.sleep(1.seconds);
	write(recipePath, newRecipe);
	scope(exit) write(recipePath, origRecipe);

	const result = execute(["ninja"], null, Config.none, size_t.max, projDir);
	if (result.status != 0)
	{
		log("`ninja` failed with status ", result.status, ":\n", result.output);
		return false;
	}
	if (!result.output.canFind("Regenerating build.ninja"))
	{
		log("build.ninja was not regenerated after touching the recipe, `ninja` output:\n", result.output);
		return false;
	}
	if (!readText(buildNinjaPath).canFind("extra-imports"))
	{
		log("regenerated build.ninja does not contain the new import path:\n", readText(buildNinjaPath));
		return false;
	}

	return true;
}

int main()
{
	const dub = environment.get("DUB", buildPath(__FILE_FULL_PATH__.dirName.dirName, "bin", "dub"));
	const dc = environment.get("DC", "dmd");
	const curr_dir = environment.get("CURR_DIR", buildPath(__FILE_FULL_PATH__.dirName));
	const projDir = buildPath(curr_dir, "ninja-generator");

	{
		const result = execute([dub, "generate", "ninja", "--compiler", dc], null, Config.none, size_t.max, projDir);
		if (result.status)
		{
			log("`dub generate ninja` failed with status ", result.status, ":\n", result.output);
			die("dub generate ninja failed");
		}
	}

	execute(["ninja", "-t", "clean"], null, Config.none, size_t.max, projDir);
	{
		const result = execute(["ninja"], null, Config.none, size_t.max, projDir);
		if (result.status)
		{
			log("Initial `ninja` invocation failed with status ", result.status, ":\n", result.output);
			die("initial ninja build failed");
		}
	}

	const jsonRecipePath = buildPath(projDir, "dub.json");
	const origJson = readText(jsonRecipePath);
	const newJson = `{
    "name": "ninja-generator",
    "targetType": "executable",
    "importPaths": ["extra-imports"]
}`;

	if (!regenUpdatesImportPath(projDir, jsonRecipePath, origJson, newJson))
		die("build.ninja was not actually regenerated with the new import path after touching dub.json");

	const sdlProjDir = buildPath(curr_dir, "ninja-generator-sdl");

	{
		const result = execute([dub, "generate", "ninja", "--compiler", dc], null, Config.none, size_t.max, sdlProjDir);
		if (result.status)
		{
			log("`dub generate ninja` failed with status ", result.status, ":\n", result.output);
			die("dub generate ninja failed for dub.sdl project");
		}
	}

	const sdlBuildNinja = buildPath(sdlProjDir, "build.ninja");
	if (!readText(sdlBuildNinja).canFind("regen") || !readText(sdlBuildNinja).canFind("dub.sdl"))
		die("build.ninja regen edge missing dub.sdl dependency");

	execute(["ninja", "-t", "clean"], null, Config.none, size_t.max, sdlProjDir);
	{
		const result = execute(["ninja"], null, Config.none, size_t.max, sdlProjDir);
		if (result.status)
		{
			log("Initial `ninja` invocation failed with status ", result.status, ":\n", result.output);
			die("initial ninja build failed for dub.sdl project");
		}
	}

	const sdlRecipePath = buildPath(sdlProjDir, "dub.sdl");
	const origSdl = readText(sdlRecipePath);
	const newSdl = "name \"ninja-generator-sdl\"\ntargetType \"executable\"\nimportPaths \"extra-imports\"\n";

	if (!regenUpdatesImportPath(sdlProjDir, sdlRecipePath, origSdl, newSdl))
		die("build.ninja was not actually regenerated with the new import path after touching dub.sdl");

	execute(["ninja", "-t", "clean"], null, Config.none, size_t.max, sdlProjDir);
	remove(sdlBuildNinja);

	log("PASS");
	return 0;
}
