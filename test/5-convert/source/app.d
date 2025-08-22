import common;

import std.algorithm;
import std.array;
import std.file;
import std.process;
import std.stdio : File;
import std.string;

void main()
{
	chdir("sample");
	copy("dub.sdl", "dub.sdl.ref");
	scope(exit) rename("dub.sdl.ref", "dub.sdl");

	spawnProcess([dub, "convert", "-f", "json"]).wait;

	if (exists("dub.sdl"))
		die("Old recipe file not removed");
	if (!exists("dub.json"))
		die("New recipe file not created");

	spawnProcess([dub, "convert", "-f", "sdl"]).wait;

	if (exists("dub.json"))
		die("Old recipe file not removed");
	if (!exists("dub.sdl"))
		die("New recipe file not created");

	auto orig = File("dub.sdl.ref");
	auto ne = File("dub.sdl");

	const got = orig.byLineCopy.map!chomp.array;
	const expected = ne.byLineCopy.map!chomp.array;

	if (!equal(got, expected)) {
		copy("dub.sdl.ref", "dub.sdl.expected");
		copy("dub.sdl", "dub.sdl.got");
		die("The project data did not match the expected output! Check dub.sdl.*");
	}
}
