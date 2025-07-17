import common;

import std.file;
import std.path;
import std.process;

void main () {
	auto p = spawnProcess([dub, "build", "--d-version=FromCli1", "--d-version=FromCli2"], null, Config.none, "sample");
	if (p.wait != 0)
		die("dub build failed");
}
