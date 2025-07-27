import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample");
	write("dub.selections.json", `{
    "fileVersion": 1,
    "versions": {
        "dub": "1.5.0",
    }
}
`);

	if (spawnProcess([dub, "upgrade"]).wait != 0)
		die("dub upgrade failed");

	if (!readText("dub.selections.json").canFind(`"dub": "1.6.0"`))
		die("Dependency not upgraded");
}
