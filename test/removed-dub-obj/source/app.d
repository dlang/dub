import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.range;

void main () {
	chdir("sample");

	immutable cachePath = dubHome.buildPath("cache", "removed-dub-obj");
	if (exists(cachePath)) rmdirRecurse(cachePath);

	if (spawnProcess([dub, "build"]).wait != 0)
		die("dub build failed");

	if (!exists(cachePath))
		die("The expected ", cachePath, " doesn't exist");
	if (!isDir(cachePath))
		die("The expected ", cachePath, " isn't a directory");

	immutable numObjecjtFiles = dirEntries(cachePath, "*.o*", SpanMode.depth)
		.walkLength;

	if (numObjecjtFiles != 0)
		die("Found left-over object files in ", cachePath);
}
