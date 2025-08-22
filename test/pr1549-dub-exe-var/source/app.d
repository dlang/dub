import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.string;

void main () {
	if (spawnProcess([dub, "build", "--root", "sample"]).wait != 0)
		die("dub build failed");

	auto p = teeProcess(["sample/test-application"]);
	if (p.wait != 0)
		die("failed running the built application");

	if (p.stdout.chomp != "modified code")
		die("$DUB build variable was (likely) not evaluated correctly");
}
