import common;

import std.algorithm;
import std.process;
import std.file;

void main () {
	chdir("sample");

	if (spawnProcess([dub, "clean"]).wait != 0)
		die("Dub clean failed");

	auto p = teeProcess([dub, "build"], Redirect.stdout | Redirect.stderrToStdout);
	p.wait;
	if (!p.stdout.canFind("building configuration"))
		die("Build was not executed.");

	p = teeProcess([dub, "build"], Redirect.stdout | Redirect.stderrToStdout);
	p.wait;
	if (!p.stdout.canFind("is up to date"))
		die("Build was executed.");

	write("dependency.txt", "");

	p = teeProcess([dub, "build"], Redirect.stdout | Redirect.stderrToStdout);
	p.wait;
	if (!p.stdout.canFind("building configuration"))
		die("Build was not executed.");
}
