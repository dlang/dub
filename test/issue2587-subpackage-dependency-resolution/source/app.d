import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample/a");
	if (exists("dub.selections.json")) remove("dub.selections.json");

	if (spawnProcess([dub, "upgrade", "-v"]).wait != 0)
		die("Dub upgrade failed");

	if (spawnProcess([dub, "run"]).wait != 0)
		die("Dub run after generating dub.selections.json failed");

	remove("dub.selections.json");

	if (spawnProcess([dub, "run"]).wait != 0)
		die("Dub run without dub.selections.json failed");
}
