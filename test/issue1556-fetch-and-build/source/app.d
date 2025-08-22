import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	execute([dub, "remove", "main-package", "--non-interactive"]);
	execute([dub, "remove", "dependency-package", "--non-interactive"]);

	immutable registryArgs = [
		"--skip-registry=all",
		"--registry=file://" ~ getcwd().buildPath("sample"),
	];

	log("Trying to fetch main-package");
	auto p = spawnProcess([dub, "--cache=local", "fetch", "main-package"] ~ registryArgs);
	if (p.wait != 0)
		die("Dub fetch failed");

	log("Trying to build it (should fetch dependency-package)");
	p = spawnProcess([dub, "--cache=local", "build", "main-package"] ~ registryArgs);
	if (p.wait != 0)
		die("Dub fetch failed");
}
