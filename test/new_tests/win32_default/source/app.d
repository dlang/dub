import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.stdio;

void main()
{
	const file = buildPath(getcwd, "sample.d");

	const dmd = environment.get("DC");

	int exitCode;

	void runTest(scope const string[] cmd)
	{
		const result = execute(cmd);

		if (result.status || result.output.canFind("Failed"))
		{
			writefln("\n> %-(%s %)", cmd);
			writeln("===========================================================");
			writeln(result.output);
			writeln("===========================================================");
			writeln("Last command failed with exit code ", result.status, '\n');
			exitCode = 1;
		}
	}

	// Test without --arch
	runTest([
		dub, "build",
			"--config", "MsCoff64",
			"--single", file,
	]);

	// Test with different --arch
	const string[2][] tests = [
		[ "x86",        "Default"	],
		[ "x86_omf",    "MsCoff"	],
		[ "x86_mscoff", "MsCoff"	],
		[ "x86_64",		"MsCoff64"	],
	];

	foreach (string[2] test; tests)
	{
		const arch = test[0];
		const config = test[1];

		runTest([
			dub, "build",
				"--arch", arch,
				"--config", config,
				"--single", file,
		]);
	}

	if (exitCode)
		die("some tests failed");
}
