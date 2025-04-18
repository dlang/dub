/+ dub.sdl:
name "issue2348"
buildType "test" {
    buildOptions "syntaxOnly"
    postBuildCommands "echo xxx"
}
+/
module issue2348;

import std.process;
import std.stdio;
import std.algorithm;
import std.path;

int main()
{
	const dub = environment.get("DUB", buildPath(__FILE_FULL_PATH__.dirName.dirName, "bin", "dub.exe"));
	const cmd = [dub, "build", "--build=test", "--single", __FILE_FULL_PATH__];
	const result = execute(cmd, null, Config.none, size_t.max, __FILE_FULL_PATH__.dirName);
	if (result.status || result.output.canFind("Failed"))
	{
		writefln("\n> %-(%s %)", cmd);
		writeln("===========================================================");
		writeln(result.output);
		writeln("===========================================================");
		writeln("Last command failed with exit code ", result.status, '\n');
		return 1;
	}
	return 0;
}
