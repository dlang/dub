import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	auto p = teeProcess([dub, "--version"], Redirect.stdout);
	if (p.pid.wait != 0)
		die("dub --version failed");
	if (!p.stdout.canFind("DUB version"))
		die("dub --version did not contain 'DUB version'");
}
