/+ dub.sdl:
   name "ninja-makedeps-regen"
   dependency "common" path="./common"
 +/

module ninja_makedeps_regen;

import std.process : environment, execute, Config;
import std.path : buildPath, dirName;
import std.file : readText, write, timeLastModified, exists;
import std.algorithm : canFind;
import core.thread : Thread;
import core.time : seconds;

import common;

int main()
{
	const dub = environment.get("DUB", buildPath(__FILE_FULL_PATH__.dirName.dirName, "bin", "dub"));
	const dc = environment.get("DC", "dmd");
	const curr_dir = environment.get("CURR_DIR", buildPath(__FILE_FULL_PATH__.dirName));
	const projDir = buildPath(curr_dir, "ninja-makedeps");

	if (execute([dub, "generate", "ninja", "--compiler", dc], null, Config.none, size_t.max, projDir).status)
		die("dub generate ninja failed");

	const buildNinjaPath = buildPath(projDir, "build.ninja");
	if (!readText(buildNinjaPath).canFind("-makedeps"))
		die("build.ninja missing -makedeps flag on dc rule");
	if (!readText(buildNinjaPath).canFind("depfile ="))
		die("build.ninja missing depfile directive on dc rule");

	execute(["ninja", "-t", "clean"], null, Config.none, size_t.max, projDir);
	if (execute(["ninja"], null, Config.none, size_t.max, projDir).status)
		die("initial ninja build failed");

	// Locate the actual app.o produced, since the generator encodes the full
	// source path into the object filename.
	import std.file : dirEntries, SpanMode;
	string findObj(string moduleName)
	{
		foreach (entry; dirEntries(projDir, SpanMode.shallow))
			if (entry.name.canFind("_" ~ moduleName ~ ".o"))
				return entry.name;
		return "";
	}

	const objPath = findObj("app");
	if (!objPath.length || !exists(objPath))
		die("could not locate app.o after initial build");

	const mtimeBefore = timeLastModified(objPath);

	const helperPath = buildPath(projDir, "source", "helper.d");
	const origHelper = readText(helperPath);

	Thread.sleep(1.seconds);
	write(helperPath, origHelper ~ "\n// touched\n");
	scope(exit) write(helperPath, origHelper);

	if (execute(["ninja"], null, Config.none, size_t.max, projDir).status)
		die("rebuild after touching helper.d failed");

	const mtimeAfter = timeLastModified(objPath);

	if (mtimeAfter <= mtimeBefore)
		die("app.o was not recompiled after helper.d changed -- depfile is not tracking transitive imports");

	execute(["ninja", "-t", "clean"], null, Config.none, size_t.max, projDir);

	log("PASS");
	return 0;
}
