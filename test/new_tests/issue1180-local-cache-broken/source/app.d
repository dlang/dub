import common;
import test_registry_helper;

import std.algorithm;
import std.path;
import std.process;
import std.file;
import std.stdio;

void main () {
	auto testRegistry = TestRegistry("../extra/issue1416-maven-repo-pkg-supplier");

	// Ignore errors
	execute([dub, "remove", "maven-dubpackage", "--root=sample", "--non-interactive"]);

	immutable mvnUrl = "mvn+http://localhost:" ~ testRegistry.port ~ "/maven/release/dubpackages";

	log("Trying to download maven-dubpackage (1.0.5)");
	auto p = spawnProcess([
			dub,
			"upgrade",
			"--root=sample",
			"--cache=local",
			"--skip-registry=all",
			"--registry=" ~ mvnUrl,
	]);
	if (p.wait != 0)
		die("Dub upgrade failed");

	if (spawnProcess([dub, "remove", "maven-dubpackage@1.0.5", "--root=sample", "--non-interactive"]).wait != 0)
        die("DUB did not install package from maven registry.");
}
