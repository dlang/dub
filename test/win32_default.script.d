/+ dub.json: {
   "name": "win32_default_test"
} +/

module win32_default.script;

int main()
{
	import std.stdio;

	version (Windows)
	{
		version (DigitalMars)
			enum disabled = null;
		else
			enum disabled = "DMD as the host compiler";
	}
	else
		enum disabled = "Windows";

	static if (disabled)
	{
		writeln("Test `win32_default` requires " ~ disabled);
		return 0;
	}
	else
	{
		import std.algorithm;
		import std.path;
		import std.process;

		const dir = __FILE_FULL_PATH__.dirName();
		const file = buildPath(dir, "win32_default.d");

		const dub = environment.get("DUB", buildPath(dirName(dir), "bin", "dub.exe"));
		const dmd = environment.get("DMD", "dmd");

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
				"--compiler", dmd,
				"--config", "MsCoff64",
				"--single", file,
		]);

		// Test with different --arch
		const string[2][] tests = [
			[ "x86",        "Default"	],
			[ "x86_omf",    "OMF"		],
			[ "x86_mscoff", "MsCoff"	],
			[ "x86_64",		"MsCoff64"	],
		];

		foreach (string[2] test; tests)
		{
			const arch = test[0];
			const config = test[1];

			runTest([
				dub, "build",
					"--compiler", dmd,
					"--arch", arch,
					"--config", config,
					"--single", file,
			]);
		}



		return exitCode;
	}
}
