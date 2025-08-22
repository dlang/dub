import common;

import std.algorithm;
import std.path;
import std.file;
import std.process;

void main() {
	version(Windows) version(LDC) skip("ldc2 doesn't come with libcurl on windows");

	if (exists("test")) rmdirRecurse("test");
	mkdir("test");
	chdir("test");

	foreach (ver; ["1.27.0", "1.28.0", "1.29.0"])
		if (spawnProcess([dub, "fetch", "dub@" ~ ver, "--cache=local"]).wait != 0)
			die("Dub fetch failed");

	auto p = teeProcess([dub, "fetch", "dub@1.28.0"]);
	p.wait;
	if (p.stdout.canFind("Fetching"))
		die("Test for doubly fetch of the specified version has failed.");

	p = teeProcess([dub, "run", "dub", "-q", "--cache=local", "--", "--version"]);
	p.wait;
	if (!p.stdout.canFind("DUB version 1.29.0"))
		die("Test for selection of the latest fetched version has failed.");

	p = teeProcess([dub, "run", "dub@1.28.0", "-q", "--cache=local", "--", "--version"]);
	p.wait;
	if (!p.stdout.canFind("DUB version 1.28.0"))
		die("Test for selection of the specified version has failed.");
}
