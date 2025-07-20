import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	immutable testDir = "../1-staticLib-simple";

	// If DFLAGS are not processed, dub for library would fail
	auto p = spawnProcess([dub, "build", "--build=plain"], ["DFLAGS": "-w"], Config.none, testDir);
	if (p.wait != 0)
		die("Dub build with sane DFLAGS failed");

	p = spawnProcess([dub, "build", "--build=plain"], ["DFLAGS": "-asfdsf"], Config.none, testDir);
	if (p.wait == 0)
		die("Dub build with insafe DFLAGS succeeded");

	p = spawnProcess([dub, "build", "--build=plain", "--build=plain"], null, Config.none, testDir);
	if (p.wait != 0)
		die("Dub build with multiple --build=plain failed");
}
