import common;

import std.algorithm;
import std.process;
import std.file;

void main () {
	if ("sample/text.txt".exists) remove("sample/test.txt");

	if (spawnProcess(dub, null, Config.none, "sample").wait)
        die("Dub run failed");

	immutable got = readText("sample/test.txt");
	if (!got.canFind("pre-run"))
        die("pre run not executed.");
	if (!got.canFind("post-run-0"))
        die("post run not executed.");
}
