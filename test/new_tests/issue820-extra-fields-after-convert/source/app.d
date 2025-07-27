import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample");

	auto p = teeProcess([dub, "convert", "-s", "-f", "sdl"]);
	if (p.wait != 0)
		die("dub convert failed");
	if (p.stdout.canFind("version", "sourcePaths", "importPaths", "configuration")) {
		die("Conversion added extra fields");
	}
}
