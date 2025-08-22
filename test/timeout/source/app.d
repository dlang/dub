import common;

import core.thread.osthread;
import core.time;
import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.stdio;

void main () {
	immutable port = getRandomPort();
	immutable cmd = [
		dub,
		"fetch",
		"dub",
		"--skip-registry=all",
		// a port that shouldn't be occupied
		"--registry=http://localhost:" ~ port,
	];

	// FIXME windows waits the full 8 seconds before stopping
	version(Posix) {{
		log("Testing unconnectable registry");
		auto p = spawnProcess(cmd);
		scope(exit) p.stop;

		Thread.sleep(4.seconds);
		if (!p.tryWait.terminated)
			die("Fetching from unconnectable registry should fail immediately.");
		if (p.wait == 0)
			die("Fetching from unconnectable registry should fail.");
	}}

	try {
		execute("nc");
	} catch (ProcessException) {
		log("Skipping the rests of these tests as they require `nc`");
		return;
	}

	{
		log("Testing non-responding registry");
		auto nc = pipeProcess(["nc", "-l", port]);
		scope(exit) stop(nc.pid);
		nc.stdin.close();

		auto p = spawnProcess(cmd);
		scope(exit) p.stop;

		Thread.sleep(10.seconds);

		if (!p.tryWait.terminated)
			die("Fetching from non-responding registry should fail.");
		if (p.wait == 0)
			die("Fetching from non-responding registry should fail.");
	}

	{
		log("Testing too slow registry");
		auto nc = pipeProcess(["nc", "-l", port]);
		scope(exit) stop(nc.pid);

		nc.stdin.write("HTTP/1.1 200 OK\r\n");
		nc.stdin.write("Server: dummy\r\n");
		nc.stdin.write("Content-Type: application/json\r\n");
		nc.stdin.write("Content-Length: 2\r\n");
		nc.stdin.write("\r\n");
		// Simulate slow response
		//nc.stdin.write("{}");

		// SEGV without this ??
		nc.stdin.flush();

		auto p = spawnProcess(cmd);
		scope(exit) p.stop;

		Thread.sleep(10.seconds);

		if (!p.tryWait.terminated)
			die("Fetching from too slow registry should time-out within 8s.");
		if (p.wait == 0)
			die("Fetching from non-responding registry should fail.");
	}
}

string getRandomPort() {
	auto result = cast(ushort)(thisProcessID % ushort.max);
	if (result < 1024)
		result += 1025;
	import std.conv;
	return text(result);
}

void stop(Pid pid) {
	scope(exit) pid.wait;
	try {
		pid.kill;
	} catch (Exception) {}
}
