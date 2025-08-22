import common;

import core.thread.osthread;
import core.time;
import std.algorithm;
import std.file;
import std.path;
import std.range;
import std.process;

void main () {
	if (exists("test")) rmdirRecurse("test");
	mkdir("test");
	chdir("test");
	auto p = pipeProcess([dub, "init"], Redirect.stdin);
	scope(exit) p.pid.wait;

	Thread.sleep(1.seconds);
	p.pid.kill;
	p.stdin.close();

	immutable filesCount = dirEntries(".", SpanMode.shallow).walkLength;
	if (filesCount > 0)
		die("Aborted dub init left spurious files around.");
}
