import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample");
	if (exists("nested")) rmdirRecurse("nested");
	mkdir("nested");
	copy("build.d", "nested/build.d");

	if (spawnProcess([dub, "build.d", getcwd().buildPath("build.d")]).wait != 0)
		die("Dub build from plain directory failed");

	{
		chdir("nested");
		scope(exit) chdir("..");

		if (spawnProcess([dub, "build.d", getcwd().buildPath("build.d")]).wait != 0)
			die("Dub build from nested directory failed");
	}
}
