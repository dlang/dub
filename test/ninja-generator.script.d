/+ dub.sdl:
   name "ninja-generator-regen"
   dependency "common" path="./common"
 +/

module ninja_generator_regen;

import std.process : environment, execute, Config;
import std.path : buildPath, dirName;
import std.file : setTimes, readText, remove;
import std.datetime : Clock;
import std.algorithm : canFind;
import core.thread : Thread;
import core.time : seconds;

import common;

bool regenerated(string projDir, string touchedFile)
{
	Thread.sleep(1.seconds);
	setTimes(buildPath(projDir, touchedFile), Clock.currTime, Clock.currTime);
	const result = execute(["ninja"], null, Config.none, size_t.max, projDir);
	return result.status == 0 && result.output.canFind("Regenerating build.ninja");
}

int main()
{
	const dub = environment.get("DUB", buildPath(__FILE_FULL_PATH__.dirName.dirName, "bin", "dub"));
	const dc = environment.get("DC", "dmd");
	const curr_dir = environment.get("CURR_DIR", buildPath(__FILE_FULL_PATH__.dirName));
	const projDir = buildPath(curr_dir, "ninja-generator");

	if (execute([dub, "generate", "ninja", "--compiler", dc], null, Config.none, size_t.max, projDir).status)
		die("dub generate ninja failed");

	execute(["ninja", "-t", "clean"], null, Config.none, size_t.max, projDir);
	if (execute(["ninja"], null, Config.none, size_t.max, projDir).status)
		die("initial ninja build failed");

	if (!regenerated(projDir, "dub.json"))
		die("no regen after touching dub.json");

	const sdlProjDir = buildPath(curr_dir, "ninja-generator-sdl");

	if (execute([dub, "generate", "ninja", "--compiler", dc], null, Config.none, size_t.max, sdlProjDir).status)
		die("dub generate ninja failed for dub.sdl project");

	const sdlBuildNinja = buildPath(sdlProjDir, "build.ninja");
	if (!readText(sdlBuildNinja).canFind("regen") || !readText(sdlBuildNinja).canFind("dub.sdl"))
		die("build.ninja regen edge missing dub.sdl dependency");

	execute(["ninja", "-t", "clean"], null, Config.none, size_t.max, sdlProjDir);
	if (execute(["ninja"], null, Config.none, size_t.max, sdlProjDir).status)
		die("initial ninja build failed for dub.sdl project");

	if (!regenerated(sdlProjDir, "dub.sdl"))
		die("no regen after touching dub.sdl");

	execute(["ninja", "-t", "clean"], null, Config.none, size_t.max, sdlProjDir);
	remove(sdlBuildNinja);

	log("PASS");
	return 0;
}
