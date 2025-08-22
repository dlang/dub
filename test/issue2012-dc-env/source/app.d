import common;

import std.process;

void main () {
	immutable dc = environment["DC"];

	auto p = spawnProcess([dub, "app.d", dc], null, Config.none, "sample");
	if (p.wait != 0)
		die("Running the program failed");
}
