import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	immutable expectedPath = "single-file-sdl-default-name-sample" ~ DotExe;
	if (exists(expectedPath)) remove(expectedPath);

	if (spawnProcess([dub, "run", "--single", "single-file-sdl-default-name-sample.d"]).wait != 0)
		die("dub run failed");

	if (!exists(expectedPath)) {
		logError("Expected to find file: ", expectedPath);
		die("Normal invocation did not produce a binary in the current directory");
	}
}
