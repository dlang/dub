#!/usr/bin/env dub
/+dub.sdl:
	name: run_unittest_old
	targetName: run-unittest
+/
module run_unittest;

import std.file;
import std.path;
import std.process;

int main(string[] args)
{
	immutable dubRoot = environment.get("DUB", __FILE_FULL_PATH__.dirName.dirName);
	immutable dub = dubRoot.buildPath("bin", "dub");
	immutable testRoot = dubRoot.buildPath("test");
	immutable runUnittestRoot = testRoot.buildPath("run_unittest");

	import std.stdio;
	writefln("This script is deprecated. Call `dub --root %s` instead", runUnittestRoot);
	import core.thread.osthread;
	import core.time;
	Thread.sleep(1.seconds);

	const cmd = [
		dub,
		"run",
		"--root=run_unittest",
		"--",
		"-j1",
	]
		~ args[1 .. $];

	chdir(testRoot);
	return spawnProcess(cmd).wait;
}
