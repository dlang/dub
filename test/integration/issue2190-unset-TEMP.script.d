/+ dub.json: {
   "name": "issue2190_unset_TEMP"
} +/

module issue2190_unset_TEMP.script;

int main()
{
	import std.stdio;
	import std.algorithm;
	import std.path;
	import std.process;

	const dir = __FILE_FULL_PATH__.dirName();

	// doesn't matter, just pick something
	const file = buildPath(dir, "single-file-sdl-default-name.d");

	const dub = environment.get("DUB", buildPath(dirName(dir), "bin", "dub.exe"));

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

	environment.remove("TEMP");

	// only guaranteed to be there on Windows
	// See: runDubCommandLine in commandline
	version(Windows)
	{
		runTest([
			dub, "build",
			"--single", file,
		]);
	}

	return exitCode;
}
