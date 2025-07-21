import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	// DFLAGS disable unittests: https://github.com/dlang/dub/pull/3060
	environment.remove("DFLAGS");

	if (spawnProcess([dub, "test", "--single", "single_success.d"]).wait != 0)
		die("Unittest should have passed");

	if (spawnProcess([dub, "test", "--single", "single_failure.d"]).wait == 0)
		die("Unittest should have failed");
}
