import common;

import std.file;
import std.process;
import std.path;
import std.stdio;

void main () {
	chdir("sample");
	environment.remove("DUB_HOME");

	immutable dpath = getcwd().buildPath("dpath");
	if (dpath.exists) dpath.rmdirRecurse;

	auto p = spawnProcess([dub, "upgrade"], ["DPATH": dpath]);
	if (p.wait != 0)
		die("Dub upgrade failed");

	if (!exists(dpath.buildPath("dub/packages/gitcompatibledubpackage/1.0.1/gitcompatibledubpackage/dub.json")))
		die("Did not get dependencies installed into $DPATH");

	import std.json;
	immutable jsonPath = JSONValue(dpath.buildPath("dub2"));
	File("dub.settings.json", "w").writefln(`{ "dubHome": %s }`, jsonPath);

	p = spawnProcess([dub, "upgrade"]);
	if (p.wait != 0)
		die("Dub upgrade failed");

	if (!exists(dpath.buildPath("dub2/packages/gitcompatibledubpackage/1.0.1/gitcompatibledubpackage/dub.json")))
		die("Did not get dependencies installed into dubHome (set from config)");
}
