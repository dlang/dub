import common;

import std.algorithm;
import std.array;
import std.file;
import std.format;
import std.process;
import std.path;
import std.string;
import std.stdio;

void main () {
	chdir("sample");

	auto p = teeProcess([dub, "upgrade"]);
	if (p.pid.wait == 0)
		die("Dub upgrade should have failed");

	immutable expected = [
		`Error Unresolvable dependencies to package gitcompatibledubpackage:`,
		`  b @%s depends on gitcompatibledubpackage ~>1.0.2`.format(getcwd.buildPath("b")),
		`  issue1037-better-dependency-messages ~master depends on gitcompatibledubpackage 1.0.1`,
	];

	const got = p.stderrLines;

	if (!equal(got, expected))
		die("output not containting conflict information");
}
