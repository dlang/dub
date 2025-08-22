import common;
import test_registry_helper;

import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.regex;

void main () {
	auto testRegistry = TestRegistry("../extra/issue1336-registry");
	immutable registryArgs = [
		"--skip-registry=all",
		"--registry=http://localhost:" ~ testRegistry.port,
	];

	if (exists("test")) rmdirRecurse("test");
	if (spawnProcess([dub, "init", "--non-interactive", "--format=json", "test"]).wait != 0)
		die("Dub init failed");
	chdir("test");

	write("source/app.d", q{import gitcompatibledubpackage.subdir.file; void main(){}});
	if (spawnProcess([dub, "add", "gitcompatibledubpackage"] ~ registryArgs).wait != 0)
		die("Dub add failed");
	if (!readText("dub.json").matchFirst(`"gitcompatibledubpackage"\s*:\s*"~>1\.0\.4"`))
		die("dub add did not modify dub.json to reflect the new dependency");

	{
		auto p = spawnProcess([
			dub, "add", "gitcompatibledubpackage=1.0.2", "non-existing-issue1574-pkg=~>9.8.7", "--skip-registry=all"]
		);
		if (p.wait != 0)
			die("Dub add with version failed");

		immutable dubJson = readText("dub.json");
		if (!dubJson.matchFirst(`"gitcompatibledubpackage"\s*:\s*"1\.0\.2"`))
			die("dub add did not modify gitcompatibledubpackage dependency");
		if (!dubJson.matchFirst(`"non-existing-issue1574-pkg"\s*:\s*"~>9\.8\.7"`))
			die("dub did not add a dependency on a non-existing package with --skip-registry=all");
	}

	{
		auto p = spawnProcess([dub, "add", "foo@1.2.3", "gitcompatibledubpackage=~>a.b.c", "--skip-registry=all"]);
		if (p.wait == 0)
			die("Adding non-semver spec should error");
		if (readText("dub.json").canFind(`"foo"`))
			die("Failing add command should not write recipe file");
	}

}
