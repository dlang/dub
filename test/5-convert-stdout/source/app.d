import common;

import std.algorithm;
import std.array;
import std.file;
import std.process;
import std.stdio : File;
import std.string;

void main()
{
	chdir("sample");

	auto pipes = teeProcess([dub, "convert", "-s", "-f", "sdl"], Redirect.stdout);
	if (pipes.wait != 0)
		die("Dub failed to run");

	if (!exists("dub.json"))
		die("Package recipe got modified!");
	if (exists("dub.sdl"))
		die("An SDL recipe got written");

	immutable expected = [
		`name "sample-test"`,
		`targetType "executable"`,
	];
	const got = pipes.stdoutLines;

	if (!equal(got, expected))
		die("Unexpected SDLang output");
}
