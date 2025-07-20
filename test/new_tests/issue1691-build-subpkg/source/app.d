import common;

import std.process;

void main () {
	if (spawnProcess([dub, "build", "--root=sample", ":subpkg"]).wait != 0)
        die("dub build subpackage failed");
}
