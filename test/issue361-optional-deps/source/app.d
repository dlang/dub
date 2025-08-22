import common;

import std.algorithm;
import std.conv;
import std.file;
import std.path;
import std.process;
import std.range;
import std.stdio : File;
import std.string;

void main () {
	chdir("sample");

	foreach (dir; ["a/.dub", "a/b/.dub", "main1/.dub", "main2/.dub"])
		if (exists(dir)) rmdirRecurse(dir);
	if (exists("main1/dub.selections.json"))
		remove("main1/dub.selections.json");

	if (spawnProcess([dub, "build", "--bare", "main1"]).wait != 0)
		die("dub build main1 failed");
	immutable exp1 = [
		`{`,
		"\t\"fileVersion\": 1,",
		"\t\"versions\": {",
		"\t\t\"b\": \"~master\"",
		"\t}",
		"}",
	];
	foreach (got, exp; lockstep(File("main1/dub.selections.json").byLine, exp1)) {
		got = got.chomp;
		if (got != exp)
			die("main1 test: got ", text([got]), " but expected ", text([exp]));
	}


	if (spawnProcess([dub, "build", "--bare", "main2"]).wait != 0)
		die("dub build main2 failed");
	immutable exp2 = [
		`{`,
		"\t\"fileVersion\": 1,",
		"\t\"versions\": {",
		"\t\t\"a\": \"~master\"",
		"\t}",
		"}",
	];
	foreach (got, exp; lockstep(File("main2/dub.selections.json").byLine, exp2)) {
		got = got.chomp;
		if (got != exp)
			die("main2 test: got ", text([got]), " but expected ", text([exp]));
	}
}
