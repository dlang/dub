import common;

import std.process;

void main () {
	auto p = spawnProcess([dub, "--root=custom-root"]);
	if (p.wait != 0)
		die("dub --root=custom-root failed");

	p = spawnProcess([dub, "--root=custom-root-2"]);
	if (p.wait != 0)
		die("dub --root=custom-root-2 failed");
}
