import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.stdio;

void main () {
	auto p = teeProcess(
		[dub, "build", "--bare", "--force", "-a", "x86_64", "-v", "main"],
		Redirect.stdout | Redirect.stderrToStdout,
		null,
		Config.none,
		"sample",
	);
	if (p.wait != 0)
		die("dub build failed");
	if (p.stdout.canFind("-m64 -m64"))
		die("-m64 appeared twice in output");
}
