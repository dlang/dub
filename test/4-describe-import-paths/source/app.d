import std.array;
import std.algorithm;
import std.path;
import std.file;
import std.stdio;
import std.process;

import describe_test_utils;
import common;

void main()
{
	immutable describeDir = buildNormalizedPath(getcwd(), "../extra/4-describe");
	auto pipes = pipeProcess([dub, "describe", "--import-paths"],
							 Redirect.all, null, Config.none,
							 describeDir.buildPath("project"));
	if (pipes.pid.wait() != 0)
		die("Printing import paths failed");

	immutable expected = [
		describeDir.myBuildPath("project", "src", ""),
		describeDir.myBuildPath("dependency-1", "source", ""),
		describeDir.myBuildPath("dependency-2", "some-path", ""),
		describeDir.myBuildPath("dependency-3", "dep3-source", ""),
	];

	const got = pipes.stdout.byLineCopy.map!fixWindowsCR.array;
	if (equal(got, expected)) return;

	printDifference(got, expected);
	die("The import paths did not match the expected output!");
}
