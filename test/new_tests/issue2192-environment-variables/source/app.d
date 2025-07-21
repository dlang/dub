import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.string;

void main () {
	environment.remove("DUB_PACKAGE");
	immutable expectedPath = "sample/package.txt";
	if (exists(expectedPath)) remove(expectedPath);

	if (spawnProcess([dub, "build", "--force", "--root=sample", "--skip-registry=all"]).wait != 0)
		die("Failed to build package with built-in environment variables.");

	if (!exists(expectedPath))
		die("Expected generated package.txt file is missing.");
	if (readText(expectedPath).length == 0)
		die("Expected generated package.txt file is empty.");

	auto p = teeProcess([dub, "describe", "--root=sample", "--skip-registry=all", "--data=pre-build-commands", "--data-list"]);
	p.wait;
	if (p.stdout.chomp != `echo 'issue2192-environment-variables' > package.txt`)
		die("describe did not contain subtituted values or the correct package name");
}
