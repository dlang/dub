/+ dub.sdl:
   name "issue1474-generate-source"
+/

module issue1474_generate_source;

import std.process;
import std.stdio;
import std.algorithm;
import std.path;

int main()
{
	const dub = environment.get("DUB", buildPath(__FILE_FULL_PATH__.dirName.dirName, "bin", "dub"));
	const curr_dir = environment.get("CURR_DIR", buildPath(__FILE_FULL_PATH__.dirName));
	const dc = environment.get("DC", "dmd");
	const cmd = [dub, "build", "--compiler", dc];
	const result = execute(cmd, null, Config.none, size_t.max, curr_dir.buildPath("issue1474"));
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
