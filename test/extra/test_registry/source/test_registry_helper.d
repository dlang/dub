module test_registry_helper;

import std.process;
import std.stdio;

struct TestRegistry {
	immutable string port;

	this(string folder) {
		import std.path;
		import std.conv;

		immutable dir = __FILE_FULL_PATH__.dirName.dirName;
		immutable testRegistrySrc = dir.buildPath("test_registry.d");
		immutable testRegistryExe = dir.buildPath("test_registry");
		immutable dub = environment["DUB"];
		// A path independent of the current test's dubHome
		immutable newDubHome = dir.buildPath("dub");

		auto p = spawnProcess(
			[dub, "build", "--single", testRegistrySrc],
			["DUB_HOME": newDubHome]
		);
		if (p.wait != 0) {
			writeln("[FAIL]: dub build test_registry failed");
			throw new Exception("dub build test_registry failed");
		}

		this.port = text(getRandomPort);
		this.pid = spawnProcess([testRegistryExe, "--folder=" ~ folder, "--port=" ~ port]);

		import core.time;
		import core.thread.osthread;
		Thread.sleep(1.seconds);
	}

	~this() {
		scope(exit) wait(this.pid);
		try {
			writeln("--- The next few lines are test_registry shutting down, don't worry about them");
			stdout.flush();
			kill(this.pid);
		} catch (ProcessException) {}
	}

private:
	Pid pid;
	static ushort getRandomPort() {
		ushort result = cast(ushort)(thisProcessID % ushort.max);
		if (result < 1024)
			result += 1025;
		return result;
	}
}
