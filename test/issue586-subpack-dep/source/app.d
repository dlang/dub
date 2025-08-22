import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample");

	foreach (dir; ["a/.dub", "a/b/.dub", "main/.dub"])
		if (exists(dir)) rmdirRecurse(dir);

	if (spawnProcess([dub, "build", "--bare", "main"]).wait != 0)
		die("dub build failed");

	if (spawnProcess([dub, "run", "--bare", "main"]).wait != 0)
		die("dub run failed");
}
