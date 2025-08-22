import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample");

	foreach (subpkg; ["server", "client", "common"]) {
		if (spawnProcess([dub, "build", ":" ~ subpkg, "-v"]).wait != 0)
			die("dub build :", subpkg, " failed");
	}
}
