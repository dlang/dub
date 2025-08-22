import common;
import test_registry_helper;

import core.time;
import core.thread.osthread;
import std.array;
import std.conv;
import std.file;
import std.format;
import std.process;
import std.path;
import std.range;
import std.regex;
import std.stdio;

void main () {
	auto testRegistry = TestRegistry("../extra/issue1336-registry");
	immutable port = testRegistry.port;

	// ignore failure
	execute([dub, "remove", "gitcompatibledubpackage", "--non-interactive"]);

	immutable registryArgs = [
		"--skip-registry=all",
		"--registry=http://localhost:" ~ text(port),
	];

	log("Trying to download gitcompatibledubpackage (1.0.4)");
	{
		auto pid = spawnProcess([dub, "fetch", "gitcompatibledubpackage@1.0.4"] ~ registryArgs);
		scope(exit) pid.wait;

		// no waitTimeout function for non-windows :(
		Thread.sleep(timeoutDuration);
		auto r = pid.tryWait;
		if (!r.terminated)
			die("Fetching from responsive registry should not time-out.");
		if (r.status != 0)
			die("Dub fetch failed");

		if (spawnProcess([dub, "remove", "gitcompatibledubpackage@1.0.4"]).wait != 0)
			die("Dub remove failed");
	}

	log("Downloads should be retried when the zip is corrupted - gitcompatibledubpackage (1.0.3)");
    {
        auto p = teeProcess([dub, "fetch", "gitcompatibledubpackage@1.0.3"] ~ registryArgs,
							 Redirect.stdout | Redirect.stderrToStdout);
		scope(exit) p.pid.wait;

		Thread.sleep(timeoutDuration);
		auto r = p.pid.tryWait;
		if (!r.terminated)
			die("Dub timed out unexpectedly");

		const output = p.stdout;
		auto needle = regex(`Failed to extract zip archive`);
		auto matches = matchAll(output, needle);
		if (matches.walkLength < 3) {
			writeln("========== +Output was ==========");
			writeln(output);
			writeln("========== -Output was ==========");
			die("Dub should have retried to download the zip archive multiple times.");
		}

		if (execute([dub, "remove", "gitcompatibledubpackage", "--non-interactive"]).status == 0) {
			die("Dub should not have installed a broken package");
		}
	}

	log("HTTP status errors on downloads should be retried - gitcompatibledubpackage (1.0.2)");
	{
        auto p = teeProcess([dub, "fetch", "gitcompatibledubpackage@1.0.2", "--vverbose"] ~ registryArgs,
							 Redirect.stdout | Redirect.stderrToStdout);
		scope(exit) p.pid.wait;

		Thread.sleep(timeoutDuration);
		auto r = p.pid.tryWait;
		if (!r.terminated)
			die("Dub timed out unexpectedly");

		const output = p.stdout;
		auto needle = regex(`Bad Gateway`);
		auto matches = matchAll(output, needle);
		if (matches.walkLength < 3) {
			writeln("========== +Output was ==========");
			writeln(output);
			writeln("========== -Output was ==========");
			die("Dub should have retried to download the zip archive multiple times.");
		}

		if (execute([dub, "remove", "gitcompatibledubpackage", "--non-interactive"]).status == 0) {
			die("Dub should not have installed a broken package");
		}
	}

	version(Posix) {
		log("HTTP status errors on downloads should retry with fallback mirror - gitcompatibledubpackage (1.0.2)");
		{
			auto p = spawnProcess([
					dub, "fetch", "gitcompatibledubpackage@1.0.2", "--vverbose",
					"--skip-registry=all",
					format("--registry=http://localhost:%1$s http://localhost:%1$s/fallback", port),
			]);
			scope(exit) p.wait;

			Thread.sleep(timeoutDuration);
			auto r = p.tryWait;
			if (!r.terminated)
				die("Fetching from responsive registry should not time-out.");
			if (r.status != 0)
				die("Dub fetch should have succeeded");

			if (spawnProcess([dub, "remove", "gitcompatibledubpackage@1.0.2"]).wait != 0)
				die("Dub should have installed the package");
		}
	}

	log("Test success");
}

immutable timeoutDuration = 1.seconds;
