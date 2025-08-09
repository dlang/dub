import common;

import std.algorithm;
import std.process;
import std.file;

void main () {
	chdir("sample");
	write("main/dub.selections.json", `
{
	"fileVersion": 1,
	"versions": {
		"a": "1.0.0",
		"b": "1.0.0"
	}
}`);

	auto p = spawnProcess([dub, "upgrade", "--bare", "--root=main", "a"]);
	if (p.wait != 0)
		die("Dub upgrade failed");

	immutable selections = readText("main/dub.selections.json");
	if (!selections.canFind(`"a": "1.0.1"`))
		die("Specified dependency was not upgraded.");
	if (selections.canFind(`"b": "1.0.1"`))
		die("Non-specified dependency got upgraded.");
}
