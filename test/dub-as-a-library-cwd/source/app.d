import common;

import std.process;

void main () {
	if (spawnProcess([dub, "--root=sample"]).wait != 0)
		die("Dub --root failed");
}
