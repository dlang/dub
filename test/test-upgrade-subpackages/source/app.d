import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample");

	// make sure that there are no left-over selections files
	foreach (file; ["dub.selections.json", "subpack/dub.selections.json"])
		if (exists(file)) remove(file);

	// first upgrade only the root package
	if (spawnProcess([dub, "upgrade"]).wait != 0)
		die("The upgrade command failed.");

	if (!exists("dub.selections.json") || exists("subpack/dub.selections.json"))
		die("The upgrade command did not generate the right set of dub.selections.json files.");

	remove("dub.selections.json");

	// now upgrade with all sub packages
	if (spawnProcess([dub, "upgrade", "-s"]).wait != 0)
		die("The upgrade command failed with -s.");

	if (!exists("dub.selections.json") || !exists("subpack/dub.selections.json"))
		die("The upgrade command did not generate all dub.selections.json files.");
}
