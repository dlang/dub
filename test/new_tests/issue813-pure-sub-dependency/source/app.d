import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample");

	if (spawnProcess([dub, "build", "--bare", "main"]).wait != 0)
		die("dub build failed");
}
