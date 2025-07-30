import common;

import std.algorithm;
import std.conv;
import std.file;
import std.path;
import std.process;
import std.range;
import std.stdio;

void main () {
	chdir("sample");

	foreach (dir; ["a-1.0.0/.dub", "a-1.1.0/.dub", "main/.dub"])
		if (exists(dir)) rmdirRecurse(dir);

	if (spawnProcess([dub, "build", "--bare", "main"]).wait != 0)
	    die("dub build failed");
}
