import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	// FIXME: DFLAGS disable unittests: https://github.com/dlang/dub/pull/3060
	environment.remove("DFLAGS");

	auto p = teeProcess([dub, "test"], Redirect.stdout, null, Config.none, "sample");
	p.wait;
	if (!p.stdout.canFind("TEST_WAS_RUN"))
		die("Tests weren't run");
}
