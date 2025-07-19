import common;

import std.array;
import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.regex;
import std.string;
import std.stdio;

string pkgDir;

void main () {
	pkgDir = dubHome.buildPath("packages", "dub");

	// Nuke existing dir
	if (dubHome.exists) dubHome.rmdirRecurse();

	fetchDub("1.9.0");
	fetchDub("1.10.0");

	{
		auto p = pipeProcess([dub, "remove", "dub"]);
		scope(exit) p.pid.wait;
		p.stdin.writeln(1);
		p.stdin.close();

		const output = p.stdout.byLineCopy.join('\n');
		p.pid.wait;

		auto r = regex(`select.*1\.9\.0.*1\.10\.0`, "is");
		if (!output.matchFirst(r)) {
			writeln("Dub didn't print the menu correctly. Output:");
			writeln(output);
			die("unrecognized dub remove dialog");
		}

		if (existsDubDir("1.9.0"))
			die("Failed to remove dub-1.9.0");
	}

	{
		fetchDub("1.9.0");

		// EOF abort remove
		auto p = pipeProcess([dub, "remove", "dub"], Redirect.stdin);
		scope(exit) p.pid.wait;
		p.stdin.close();
		p.pid.wait;

		if (!existsDubDir("1.9.0") || !existsDubDir("1.10.0"))
			die("Aborted dub still removed a package");
	}

	{
		// validate input
		auto p = pipeProcess([dub, "remove", "dub"], Redirect.stdin);
		scope(exit) p.pid.wait;
		p.stdin.writeln("abc");
		p.stdin.writeln("4");
		p.stdin.writeln("-1");
		p.stdin.write("3");
		p.stdin.close();
		p.pid.wait;

		if (existsDubDir("1.9.0") || existsDubDir("1.10.0"))
			die("Failed to remove all version of dub");
	}

	fetchDub("1.9.0");
	fetchDub("1.10.0");
	{
		// is non-interactive with a <version-spec>
		foreach (ver; ["1.9.0", "1.10.0"])
			if (spawnProcess([dub, "remove", "dub@" ~ ver]).wait != 0)
				die("Dub failed to remove version ", ver);

		foreach (ver; ["1.9.0", "1.10.0"])
			if (existsDubDir(ver))
				die("Failed to non-interactively remove specified versions");
	}
}

bool existsDubDir(const(char)[] ver) {
	immutable path = pkgDir.buildPath(ver, "dub");
	return path.exists && path.isDir;
}

void fetchDub(string dubVer) {
		if (spawnProcess([dub, "fetch", "dub@" ~ dubVer]).wait != 0)
			die("Dub fetch failed");

		if (!existsDubDir(dubVer)) {
			writeln(pkgDir.buildPath(dubVer, "dub"));
			die("Dub did not create the expected ", dubVer, " dir");
		}
}
