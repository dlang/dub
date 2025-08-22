import common;

import std.process;

void main () {
	auto p = spawnProcess(
		[dub, "build", "--bare", "main", "--override-config", "a/success"], null, Config.none, "sample");

	if (p.wait != 0)
        die("Dub build failed");
}
