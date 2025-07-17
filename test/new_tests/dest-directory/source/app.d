import common;

import std.file;
import std.path;
import std.process;

void rmrf(string path) {
	if (exists(path)) rmdirRecurse(path);
}

void main () {
	chdir("sample");

	rmrf(".dub");
	rmrf("testout");

	auto p = spawnProcess([dub, "build", "--dest=testout"]);
	if (p.wait != 0)
		die("Dub build failed");

	immutable expected = "testout";
	if (!exists(expected))
		die("Dub didn't create the directory ", expected);
	if (!isDir(expected))
		die("Dub created ", expected, " but it isn't a directory");
}
