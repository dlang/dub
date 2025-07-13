import std.file : exists, readText, rmdirRecurse;
import std.path : buildPath;
import std.process : environment, spawnProcess, wait;

import common;

void main()
{
	enum packname = "test-package";

	if(packname.exists) rmdirRecurse(packname);
	spawnProcess([dub, "init", "-n", packname, "--format", "sdl"]).wait;

	const filepath = buildPath(packname, "dub.sdl");
	if (!filepath.exists)
		die("dub.sdl not created");
}
