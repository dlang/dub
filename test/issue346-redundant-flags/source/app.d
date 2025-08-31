import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.stdio;

void main () {
	chdir("sample");
	auto p = teeProcess([dub, "build", "--bare", "--force", "-a", "x86_64", "-v", "main"], Redirect.stdout | Redirect.stderrToStdout);
	p.wait;

	if (p.stdout.canFind("-m64 -m64"))
		die("Arch switch appeared twice");

	if (p.wait != 0)
		die("Dub build failed");
}
