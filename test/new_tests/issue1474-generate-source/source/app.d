import common;

import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample");

	immutable generatedFile = "ext/fortytwo.d";
	if (exists(generatedFile))
		remove(generatedFile);

	if (spawnProcess([dub, "build"]).wait != 0)
        die("Dub failed to build with generated sources");
}
