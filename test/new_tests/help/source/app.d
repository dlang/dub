import common;

import std.process;
import std.file;
import std.path;
import std.stdio;

void main () {
	// It shows the general help message
	runTestCase(
		["help"],
		"Manages the DUB project in the current directory.",
		"DUB did not print the default help message, with the `help` command.",
	);

	runTestCase(
		["-h"],
		"Manages the DUB project in the current directory.",
		"DUB did not print the default help message, with the `-h` argument.",
	);
	runTestCase(
		["--help"],
		"Manages the DUB project in the current directory.",
		"DUB did not print the default help message, with the `--help` argument.",
	);

	// It shows the build command help
	runTestCase(
		["build", "-h"],
		"Builds a package",
		"DUB did not print the build help message, with the `-h` argument.",
	);
	runTestCase(
		["build", "--help"],
		"Builds a package",
		"DUB did not print the build help message, with the `--help` argument.",
	);
}

void runTestCase(string[] args, string needle, string error) {
	auto p = execute(dub ~ args);
	if (p.status != 0)
		die("Dub failed to run");

	import std.algorithm.searching;
    if (!p.output.canFind(needle))
		die(error);
}
