import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.regex;
import std.stdio;

void main () {
	execute([dub, "remove", "gitcompatibledubpackage@*"]);

	// check whether the interactive run mode works
	{
		auto p = teeProcess([dub, "run", "gitcompatibledubpackage"],
							Redirect.stdin | Redirect.stdout);
		p.stdin.writeln("y");
		p.stdin.close();
		if (p.wait != 0)
			die("dub run failed");
		if (!p.stdout.canFind("Hello DUB"))
			die("Didn't find 'Hello DUB' in output");
		if (spawnProcess([dub, "remove", "gitcompatibledubpackage"]).wait != 0)
			die("Couldn't remove gitcompatibledubpackage");
	}

	{
		auto p = teeProcess([dub, "run", "gitcompatibledubpackage"],
							Redirect.stdin | Redirect.stdout);
		p.stdin.writeln("n");
		p.stdin.close();
		if (p.wait == 0)
			die("dub run succeeded");
		if (p.stdout.canFind("Hello DUB"))
			die("Found 'Hello DUB' in output");
		if (spawnProcess([dub, "remove", "gitcompatibledubpackage"]).wait == 0)
			die("gitcompatibledubpackage should not have been installed");
	}

	// check --yes
	{
		auto p = teeProcess([dub, "run", "--yes", "gitcompatibledubpackage"],
							Redirect.stdout);
		if (p.wait != 0)
			die("dub run failed");
		if (!p.stdout.canFind("Hello DUB"))
			die("Didn't find 'Hello DUB' in output");
		if (spawnProcess([dub, "remove", "gitcompatibledubpackage"]).wait != 0)
			die("Couldn't remove gitcompatibledubpackage");
	}

	// check -y
	{
		auto p = teeProcess([dub, "run", "-y", "gitcompatibledubpackage"],
							Redirect.stdout);
		if (p.wait != 0)
			die("dub run failed");
		if (!p.stdout.canFind("Hello DUB"))
			die("Didn't find 'Hello DUB' in output");
		if (spawnProcess([dub, "remove", "gitcompatibledubpackage"]).wait != 0)
			die("Couldn't remove gitcompatibledubpackage");
	}

	{
		auto p = teeProcess([dub, "run", "--non-interactive", "gitcompatibledubpackage"],
							Redirect.stdout | Redirect.stderrToStdout);
		if (p.wait == 0)
			die("dub run shouldn't have succeeded");
		if (!p.stdout.matchFirst(`Failed to find.*gitcompatibledubpackage.*locally`))
			die("Didn't find expected line in output");
	}

	// check supplying versions directly
	{
		auto p = teeProcess([dub, "run", "gitcompatibledubpackage@1.0.3"],
							Redirect.stdout);
		if (p.wait != 0)
			die("dub run failed");

		if (!p.stdout.canFind("Hello DUB"))
			die("Didn't find 'Hello DUB' in output");
		if (!p.stdout.matchFirst(`Fetching.*1.0.3`))
			die("Didn't find Fetching line in output");
		if (spawnProcess([dub, "remove", "gitcompatibledubpackage"]).wait != 0)
			die("Couldn't remove gitcompatibledubpackage");
	}

	// check supplying an invalid version
	{
		auto p = teeProcess([dub, "run", "gitcompatibledubpackage@0.42.43"],
							Redirect.stdout | Redirect.stderrToStdout);
		if (p.pid.wait == 0)
			die("dub run succeeded");

		if (!p.stdout.canFind("No package gitcompatibledubpackage was found matching the dependency 0.42.43"))
			die("Didn't find expected line in output");
		if (spawnProcess([dub, "remove", "gitcompatibledubpackage"]).wait == 0)
			die("gitcompatibledubpackage should not have been installed");
	}
}
