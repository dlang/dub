import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;
import core.thread.osthread;
import core.time;


void main () {
	immutable dub = environment["DUB"];

	if (exists("test")) rmdirRecurse("test");
	mkdir("test");
	chdir("test");

	immutable cmd = [dub, "fetch", "--cache=local", "bloom"];
	auto p1 = spawnProcess(cmd);
	Thread.sleep(500.msecs);
	auto p2 = spawnProcess(cmd);

	wait(p1);
	wait(p2);

	if (!exists(".dub/packages/bloom"))
		die("test/.dub/packages/bloom has not been created");
}
