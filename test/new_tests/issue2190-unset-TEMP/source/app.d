import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	environment.remove("TEMP");

	if (spawnProcess([dub, "build", "--single", "single.d"]).wait != 0)
		die("dub build with unset TEMP failed");
}
