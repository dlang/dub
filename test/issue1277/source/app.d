import common;

import std.process;
import std.file;
import std.path;

void main () {
	auto p = spawnProcess(
		[dub, "--root=" ~ getcwd().buildPath("sample"), "build"], null, Config.none, "../issue1003-check-empty-ld-flags");
	if (p.wait == 0)
		die("Dub should have failed");
}
