import common;
import test_registry_helper;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	auto testRegistry = TestRegistry("sample");
	immutable registryArgs = [
		"--skip-registry=standard",
		"--registry=mvn+http://localhost:" ~ testRegistry.port ~ "/maven/release/dubpackages",
	];

	// ignore errors
	execute([dub, "remove", "maven-dubpackage-a", "--non-interactive"]);
	execute([dub, "remove", "maven-dubpackage-b", "--non-interactive"]);

	if (spawnProcess([dub, "upgrade", "--root=sample"] ~ registryArgs).wait != 0)
		die("Dub upgrade failed");

	if (spawnProcess([dub, "remove", "maven-dubpackage-a@1.0.5"]).wait != 0)
		die(`DUB did not install package "maven-dubpackage-a" from maven registry.`);

	if (spawnProcess([dub, "remove", "maven-dubpackage-b@1.0.6"]).wait != 0)
		die(`DUB did not install package "maven-dubpackage-b" from maven registry.`);
}
