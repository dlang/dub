import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample");
	if (exists("main/dub.selections.json")) remove("main/dub.selections.json");

	if (spawnProcess([dub, "build", "--bare", "main"]).wait != 0)
		die("dub build failed");

	if (!readText("main/dub.selections.json").canFind(`"b"`))
		die("Dependency b not resolved.");
}
