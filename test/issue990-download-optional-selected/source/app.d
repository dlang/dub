import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample");

	if (spawnProcess([dub, "clean"]).wait != 0)
		die("dub clean failed");
	spawnProcess([dub, "remove", "gitcompatibledubpackage", "-n"]).wait;
	if (spawnProcess([dub, "run"]).wait != 0)
		die("dub run failed");
}
