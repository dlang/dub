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

	return dub.status;
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
	dependency "taggedalgebraic" version="~>0.11.0"
+/

version(unittest) {}
else void main()
{
}

unittest
{
	import taggedalgebraic;

	static union Base {
		int i;
		string str;
	}

	auto dummy = TaggedAlgebraic!Base(1721);
	assert(dummy == 1721);
}
`		);
	}

	const rc1 = text(dub, " test --single ", filename).executeCommand;
	if (rc1)
		writeln("\nError. Unittests failed.");
	else
		writeln("\nOk. Unittest passed.");

	return rc1;
}