import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.stdio;

void main () {
	chdir("sample");

	copy("dub.selections.json-nofoo", "dub.selections.json");
	auto p = teeProcess([dub, "-f"], Redirect.stdout | Redirect.stderrToStdout);
	p.wait;
	if (!p.stdout.canFind("no-foo"))
		die("DUB didn't ignore the optional dependency when it wasn't present in dub.selections.json");

	copy("dub.selections.json-usefoo", "dub.selections.json");
	p = teeProcess([dub, "-f"], Redirect.stdout | Redirect.stderrToStdout);
	if (!p.stdout.canFind("use-foo"))
		die("DUB didn't ignore the optional dependency when it wasn't present in dub.selections.json");
}
