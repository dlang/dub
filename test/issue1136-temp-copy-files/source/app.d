import common;

import std.algorithm;
import std.process;
import std.file;

void main () {
	if (spawnProcess([dub, "app.d"], null, Config.none, "sample").wait != 0)
        die("dub failed");
}
