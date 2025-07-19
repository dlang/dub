import common;

import std.algorithm;
import std.process;
import std.file;

void main () {
	immutable dub = environment["DUB"];
	chdir("sample");

	if (spawnProcess([dub, "clean"]).wait != 0)
		die("Dub clean failed");

	auto p = teeProcess([dub, "build"], Redirect.stdout | Redirect.stderrToStdout);
	p.wait;
	if (!p.stdout.canFind("building configuration"))
		die("Dub didn't build the package");

	p = teeProcess([dub, "build"], Redirect.stdout | Redirect.stderrToStdout);
	p.wait;
	if (p.stdout.canFind("building configuration"))
		die("Dub rebuilt the package");
}
