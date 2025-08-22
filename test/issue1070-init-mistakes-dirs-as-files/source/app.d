import common;

import std.algorithm;
import std.path;
import std.file;
import std.process;

void main() {
	chdir("sample");

	auto p = teeProcess([dub, "init"], Redirect.stdout | Redirect.stderrToStdout);
	p.wait;
	immutable expected = "The target directory already contains a 'source/' directory. Aborting.";
	if (!p.stdout.canFind(expected))
		die("Dub init dit not fail as expected");
}
