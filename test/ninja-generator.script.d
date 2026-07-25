/+ dub.sdl:
   name "ninja-generator-regen"
+/

module ninja_generator_regen;

import std.process;
import std.stdio;
import std.path;
import std.file;
import std.datetime : Clock;
import std.algorithm : canFind;
import core.thread : Thread;
import core.time : seconds;

int main()
{
	const dub = environment.get("DUB", buildPath(__FILE_FULL_PATH__.dirName.dirName, "bin", "dub"));
	const dc = environment.get("DC", "dmd");
	const curr_dir = environment.get("CURR_DIR", buildPath(__FILE_FULL_PATH__.dirName));
	const projDir = buildPath(curr_dir, "ninja-generator");

	int fail(string msg)
	{
		writeln("FAIL: ", msg);
		return 1;
	}

	bool regenerated(string touchedFile)
	{
		Thread.sleep(1.seconds);
		std.file.setTimes(buildPath(projDir, touchedFile), Clock.currTime, Clock.currTime);
		const result = execute(["ninja"], null, Config.none, size_t.max, projDir);
		return result.output.canFind("Regenerating build.ninja");
	}

	if (execute([dub, "generate", "ninja", "--compiler", dc], null, Config.none, size_t.max, projDir).status)
		return fail("dub generate ninja failed");

	execute(["ninja", "-t", "clean"], null, Config.none, size_t.max, projDir);
	const initBuild = execute(["ninja"], null, Config.none, size_t.max, projDir);
	if (initBuild.status)
	{
		writeln("DEBUG initBuild.output=", initBuild.output);
		return fail("initial ninja build failed");
	}

	if (!regenerated("dub.json"))
		return fail("no regen after touching dub.json");

	const sdlProjDir = buildPath(curr_dir, "ninja-generator-sdl");

	if (execute([dub, "generate", "ninja", "--compiler", dc], null, Config.none, size_t.max, sdlProjDir).status)
		return fail("dub generate ninja failed for dub.sdl project");

	const sdlBuildNinja = buildPath(sdlProjDir, "build.ninja");
	if (!readText(sdlBuildNinja).canFind("regen") || !readText(sdlBuildNinja).canFind("dub.sdl"))
		return fail("build.ninja regen edge missing dub.sdl dependency");

	execute(["ninja", "-t", "clean"], null, Config.none, size_t.max, sdlProjDir);
	if (execute(["ninja"], null, Config.none, size_t.max, sdlProjDir).status)
		return fail("initial ninja build failed for dub.sdl project");

	Thread.sleep(1.seconds);
	std.file.setTimes(buildPath(sdlProjDir, "dub.sdl"), Clock.currTime, Clock.currTime);
	const sdlResult = execute(["ninja"], null, Config.none, size_t.max, sdlProjDir);
	if (!sdlResult.output.canFind("Regenerating build.ninja"))
		return fail("no regen after touching dub.sdl");

	execute(["ninja", "-t", "clean"], null, Config.none, size_t.max, sdlProjDir);
	remove(sdlBuildNinja);

	writeln("PASS");
	return 0;
}
