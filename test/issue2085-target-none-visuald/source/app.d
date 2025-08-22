import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	if (spawnProcess([dub, "generate", "visuald"], null, Config.none, "sample").wait != 0)
		die("Dub generate failed");

	if (readText("sample/.dub/root.visualdproj").canFind(`</Config>`))
		die("Regression of issue #2085.");
}
