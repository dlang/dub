import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	foreach (pkg; ["fs-json-dubpackage", "fs-sdl-dubpackage"])
		execute([dub, "remove", pkg, "--non-interactive"]);

	immutable registryArgs = [ "--skip-registry=all", "--registry=file://" ~ getcwd() ~ "/sample" ];

	log("Trying to get fs-sdl-dubpackage (1.0.5)");
	if (spawnProcess([dub, "fetch", "fs-sdl-dubpackage", "--version=1.0.5"] ~ registryArgs).wait != 0)
        die("dub fetch failed");
	if (spawnProcess([dub, "remove", "fs-sdl-dubpackage@1.0.5"]).wait != 0)
		die("DUB did not install package from file system.");

	log("Trying to get fs-sdl-dubpackage (latest)");
	if (spawnProcess([dub, "fetch", "fs-sdl-dubpackage"] ~ registryArgs).wait != 0)
        die("dub fetch failed");
	if (spawnProcess([dub, "remove", "fs-sdl-dubpackage@1.0.6"]).wait != 0)
		die("DUB did not install latest package from file system.");

	log("Trying to get fs-json-dubpackage (1.0.7)");
	if (spawnProcess([dub, "fetch", "fs-json-dubpackage@1.0.7"] ~ registryArgs).wait != 0)
        die("dub fetch failed");
	if (spawnProcess([dub, "remove", "fs-json-dubpackage@1.0.7"]).wait != 0)
		die("DUB did not install package from file system.");
}
