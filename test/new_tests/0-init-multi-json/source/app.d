import std.file : exists, readText, rmdirRecurse;
import std.path : buildPath;
import std.process : environment, spawnProcess, wait;

import common;

void main()
{
	enum packname = "test-package";
	immutable deps = ["openssl", "logger"];
	enum type = "vibe.d";

	if(packname.exists) rmdirRecurse(packname);
	spawnProcess([dub, "init", "-n", packname ] ~  deps ~ [ "--type", type, "-f", "json"]).wait;

	const filepath = buildPath(packname, "dub.json");
	if (!filepath.exists)
		die("dub.json not created");

	immutable got = readText(filepath);
	foreach (dep; deps ~ type) {
		import std.algorithm;
		if (got.count(dep) != 1) {
			die(dep, " not in " ~ filepath);
		}
	}
}
