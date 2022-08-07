/+ dub.sdl:
   name "issue2051_running_unittests_from_dub_single_file_packages_fails"
 +/

import std.algorithm : any;
import std.conv : text;
import std.file : tempDir;
import std.stdio : File, writeln;
import std.string : lineSplitter;
import std.path : buildPath, buildNormalizedPath;
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

    string destinationDirectory = tempDir;
    // remove any ending slahes (which can for some reason be added at the end by tempDir, which fails on OSX) https://issues.dlang.org/show_bug.cgi?id=22738
    destinationDirectory = buildNormalizedPath(destinationDirectory);

	const filename1 = destinationDirectory.buildPath("issue2051_success.d");
	// check if the single file package with dependency compiles and runs
	{
		auto f = File(filename1, "w");
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

	const rc1 = text(dub, " test --single \"", filename1, "\"").executeCommand;
	if (rc1)
		writeln("\nError. Unittests failed.");
	else
		writeln("\nOk. Unittest passed.");

	// Check if dub `test` command runs unittests for single file package
    const filename2 = destinationDirectory.buildPath("issue2051_fail.d");
	{
		auto f = File(filename2, "w");
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
	assert(0);
}
`		);
	}

	const rc2 = text(dub, " test --single \"", filename2, "\"").executeCommand;
	if (rc2)
		writeln("\nOk. Unittests failed.");
	else
		writeln("\nError. Unittest passed.");

	return rc1 | !rc2;
}
