import common;
import test_registry_helper;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	auto testRegistry = TestRegistry("../extra/issue1416-maven-repo-pkg-supplier");
	immutable registryArgs = [
		"--skip-registry=all",
		"--registry=mvn+http://localhost:" ~ testRegistry.port ~ "/maven/release/dubpackages",
	];

    execute([dub, "remove", "maven-dubpackage", "--non-interactive"]);

	log("Trying to download maven-dubpackage (1.0.5)");

	if (spawnProcess([dub, "fetch", "maven-dubpackage@1.0.5"] ~ registryArgs).wait != 0)
		die("Dub fetch failed");
	if (spawnProcess([dub, "remove", "maven-dubpackage@1.0.5"]).wait != 0)
        die("DUB did not install package from maven registry.");

    log("Trying to download maven-dubpackage (latest)");

	if (spawnProcess([dub, "fetch", "maven-dubpackage"] ~ registryArgs).wait != 0)
		die("Dub fetch failed");
	if (spawnProcess([dub, "remove", "maven-dubpackage@1.0.6"]).wait != 0)
        die("DUB fetch did not install latest package from maven registry.");

	log("Trying to search (exact) maven-dubpackage");
	auto p = teeProcess([dub, "search", "maven-dubpackage"] ~ registryArgs);
    if (p.wait != 0)
        die("DUB search failed");
    if (!p.stdout.canFind("maven-dubpackage (1.0.6)"))
        die("DUB search did not find the correct package");
}
