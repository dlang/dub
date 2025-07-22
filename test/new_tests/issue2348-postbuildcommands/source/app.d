import common;

import std.process;

void main () {
	if (spawnProcess([dub, "build", "--build=test", "--single", "single.d"]).wait != 0)
		die("Dub build failed");
}
