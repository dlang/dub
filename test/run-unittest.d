#!/usr/bin/env dub
/+dub.sdl:
	name: run_unittest_old
	targetName: run-unittest
+/
module run_unittest;

int main(string[] args)
{
	import std.stdio;
	writeln("This script is deprecated. Call `dub --root run_unittest` instead");
	import core.thread.osthread;
	import core.time;
	Thread.sleep(1.seconds);

	import std.path;
	import std.process;

	immutable dub = environment.get("DUB", __FILE_FULL_PATH__.dirName.dirName.buildPath("bin", "dub"));
	const cmd = [
		dub,
		"run",
		"--root=run_unittest",
		"--",
		"-j1",
	]
		~ args[1 .. $];

	return spawnProcess(cmd).wait;
}
