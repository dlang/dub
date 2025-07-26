import common;

import std.algorithm;
import std.conv;
import std.file;
import std.path;
import std.process;
import std.range;
import std.string;

void main () {
	if (spawnProcess([dub, "add-local", getcwd.buildPath("sample", "newfoo")]).wait != 0)
		die("dub add-local newfoo failed");
	if (spawnProcess([dub, "add-local", getcwd.buildPath("sample", "oldfoo")]).wait != 0)
		die("dub add-local oldfoo failed");

	string[] getLines(string[] args) {
		log("Running ", text(dub ~ args), " ...");
		immutable p = execute(dub ~ args);
		if (p.status != 0) {
			log("Dub output:");
			log(p.output);
			die("failed to run ", text(dub ~ args));
		}
		return p.output.splitLines;
	}

	void tc(string[] args, string delegate(const string[]) mapper, string needle) {
		const lines = getLines(args);
		immutable targetLine = mapper(lines);

		if (!targetLine.canFind(needle)) {
			log("Dub output:");
			foreach (line; lines)
				log(line);
			log("The found line: ", targetLine);
			log("needle: ", needle);
			die("failed ", text(args));
		}
	}

	void findOnPathLine(string[] args, string needle) {
		tc(args, a => a.find!`a.canFind("path")`.front, needle);
	}

	immutable newFooDir = dirSeparator ~ "newfoo" ~ dirSeparator;
	immutable oldFooDir = dirSeparator ~ "oldfoo" ~ dirSeparator;

	findOnPathLine(["describe", "foo"], newFooDir);
	findOnPathLine(["describe", "foo@1.0.0"], newFooDir);
	findOnPathLine(["describe", "foo@0.1.0"], oldFooDir);
	findOnPathLine(["describe", "foo@<1.0.0"], oldFooDir);
	findOnPathLine(["describe", "foo@>0.1.0"], newFooDir);
	findOnPathLine(["describe", "foo@>0.2.0"], newFooDir);
	findOnPathLine(["describe", "foo@<=0.2.0"], oldFooDir);
	findOnPathLine(["describe", "foo@*"], newFooDir);
	findOnPathLine(["describe", "foo@>0.0.1 <2.0.0"], newFooDir);

	void findOnFirstLine(string[] args, string needle) {
		tc(args, a => a[0], needle);
	}

	findOnFirstLine(["test", "foo"], newFooDir);
	findOnFirstLine(["test", "foo@1.0.0"], newFooDir);
	findOnFirstLine(["test", "foo@0.1.0"], oldFooDir);

	log("The lint tests can take longer on the first run");
	findOnFirstLine(["lint", "foo"], newFooDir);
	findOnFirstLine(["lint", "foo@1.0.0"], newFooDir);
	findOnFirstLine(["lint", "foo@0.1.0"], oldFooDir);

	findOnFirstLine(["generate", "cmake", "foo"], newFooDir);
	findOnFirstLine(["generate", "cmake", "foo@1.0.0"], newFooDir);
	findOnFirstLine(["generate", "cmake", "foo@0.1.0"], oldFooDir);

	findOnFirstLine(["build", "-n", "foo"], newFooDir);
	findOnFirstLine(["build", "-n", "foo@1.0.0"], newFooDir);
	findOnFirstLine(["build", "-n", "foo@0.1.0"], oldFooDir);

	void findOnLastLine(string[] args, string needle) {
		tc(args, a => a[$ - 1], needle);
	}

	findOnLastLine(["run", "-n", "foo"], "new-foo");
	findOnLastLine(["run", "-n", "foo@1.0.0"], "new-foo");
	findOnLastLine(["run", "-n", "foo@0.1.0"], "old-foo");

	void countLines(string[] args, int expected) {
		const lines = getLines(args);
		if (lines.length != expected)
			die(text(args), " didn't produce ", text(expected), " lines");
	}
	countLines(["list", "foo"], 4);
	countLines(["list", "foo@0.1.0"], 3);
	tc(["list", "foo@>0.1.0"], a => a[1], newFooDir);


	if (spawnProcess([dub, "remove-local", "sample/newfoo"]).wait != 0)
		die("dub remove-local newfoo failed");
	if (spawnProcess([dub, "remove-local", "sample/oldfoo"]).wait != 0)
		die("dub remove-local oldfoo failed");

	void assertIsDir(string path) {
		if (!exists(path))
			die(path, " doesn't exist");
		if (!isDir(path))
			die(path, " exists but it's a directory");
	}

	immutable dubPkgPath = dubHome.buildPath("packages", "dub");
	if (spawnProcess([dub, "fetch", "dub@1.9.0"]).wait != 0)
		die("dub fetch dub@1.9.0 failed");
	assertIsDir(dubPkgPath.buildPath("1.9.0", "dub"));

	if (spawnProcess([dub, "fetch", "dub=1.10.0"]).wait != 0)
		die("dub fetch dub=1.10.0 failed");
	assertIsDir(dubPkgPath.buildPath("1.10.0", "dub"));


	if (spawnProcess([dub, "remove", "dub@1.9.0"]).wait != 0)
		die("dub remove dub@1.9.0 failed");
	if (spawnProcess([dub, "remove", "dub=1.10.0"]).wait != 0)
		die("dub remove dub=1.10.0 failed");

	bool existsDir(string path) {
		return exists(path) && isDir(path);
	}
	if (existsDir(dubPkgPath.buildPath("dub", "1.9.0")))
		die("Failed to remove dub@1.9.0");
	if (existsDir(dubPkgPath.buildPath("dub", "1.10.0")))
		die("Failed to remove dub=1.10.0");
}

// ""
