/+ dub.sdl:
   name "issue_2051_running_unittests_from_dub_single_file_packages_fails"
 +/

import std.algorithm : any;
import std.conv : text;
import std.file : tempDir;
import std.stdio : File, writeln;
import std.string : lineSplitter;
import std.path : buildPath;
import std.process : environment, executeShell;

auto executeCommand(string command)
{
	import std.exception : enforce;

	auto dub = executeShell(command);
	writeln("--- dub output:");
	foreach(line; dub.output.lineSplitter)
		writeln("\t", line);
	writeln("--- end of dub output");

	enforce(dub.status == 0, "couldn't build the project, see above");

	return dub.output;
}

/// check dub output to determine rebuild has not been triggered
auto checkUnittestsResult(string output)
{
	if (output.lineSplitter.any!(a=> a == "All unit tests have been run successfully."))
	{
		writeln("\nOk. Unittest passed.");
		return 0;
	}
	else
	{
		writeln("\nError. Unittests failed.");
		return 1;
	}
}

int main()
{
	auto dub = environment.get("DUB");
	if (!dub.length)
		dub = buildPath(".", "bin", "dub");

	string filename;
	// check if the single file package with dependency compiles and runs
	{
		filename = tempDir.buildPath("issue2051_success.d");
		auto f = File(filename, "w");
		f.write(
`#!/usr/bin/env dub
/+ dub.sdl:
	name "issue2051"
+/

version(unittest) {}
else void main()
{
}

unittest
{
	auto input = [1721];
	assert(input[0] == 1721);
}
`		);
	}

	return text(dub, " test --single ", filename)
		.executeCommand
		.checkUnittestsResult;
}