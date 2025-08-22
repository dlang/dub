import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample/main");
	if (exists("dub.selections.json")) remove("dub.selections.json");

	if (spawnProcess([dub, "build"]).wait != 0)
		die("dub build failed");
}
