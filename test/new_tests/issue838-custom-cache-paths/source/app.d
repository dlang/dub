import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.stdio;

void main () {
	chdir("sample");

	import std.json;
	immutable jsonPath = JSONValue(getcwd.buildPath("cache")).toString();

	File("dub.settings.json", "w").writefln(`{
"customCachePaths": [ %s ]
}`,
			jsonPath);

	if (spawnProcess([dub, "build", "--skip-registry=all"]).wait != 0)
		die("Failed to build package with custom cache path for dependencies.");
}
