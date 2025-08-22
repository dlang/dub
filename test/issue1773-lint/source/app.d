import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.stdio : stdout;

void main () {
	chdir("sample");
	if (exists("report.json")) remove("report.json");

	auto p = teeProcess([dub, "lint"], Redirect.stdout);
	p.wait;
	if (!p.stdout.canFind("Parameter args is never used."))
		die("DUB lint did not find expected warning.");

	if (spawnProcess([dub, "lint", "--report-file", "report.json"]).wait != 0)
		die("Dub lint --report-file failed");

	if (!readText("report.json").canFind("Parameter args is never used."))
		die("Linter report did not contain expected warning.");
}
