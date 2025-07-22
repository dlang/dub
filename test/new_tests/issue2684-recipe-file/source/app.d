import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.stdio;

void main () {
	chdir("sample");

	auto p = teeProcess([dub]);
	if (p.wait != 0)
		die("Plain dub invocation failed");
	if (!p.stdout.canFind("This was built using dub.json"))
		die("The executable was not built with dub.json");

	p = teeProcess([dub, "--recipe=dubWithAnotherSource.json"]);
	if (p.wait != 0)
		die("dub with custom recipe faile");
	if (!p.stdout.canFind("This was built using dubWithAnotherSource.json"))
		die("The executable was not built with dubWithAnotherSource.json");
}
