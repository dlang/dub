import common;

import std.array;
import std.algorithm;
import std.process;
import std.file;

void main () {
	immutable stdin = readText("stdin.d");
	auto p = teeProcess([dub, "-", "--value=v"]);
	p.stdin.write(stdin);
	p.stdin.close();
	if (p.pid.wait != 0)
		die("Dub run <stdin> failed");

	if (!p.stdout.canFind(`["--value=v"]`))
		die("Stdin for single files failed.");
}
