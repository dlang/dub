import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample");

	auto e = execute([dub, "describe", "--single", "no_ut.d", "--config=unittest"]);
	if (!e.output.canFind(`"targetName": "no_ut-test-library"`)) die("bad target name for no_ut");
	if (spawnProcess([dub, "build", "--single", "no_ut.d", "--config=unittest", "--build=unittest"]).wait != 0)
		die("dub build no_ut failed");
	if (spawnProcess("./no_ut-test-library").wait != 0)
		die("no_ut failed to run");

	e = execute([dub, "describe", "--single", "partial_ut.d", "--config=unittest"]);
	if (!e.output.canFind(`"targetName": "partial_ut-test-unittest"`))
		die("bad target name for partial_ut");
	if (spawnProcess([dub, "build", "--single", "partial_ut.d", "--config=unittest", "--build=unittest"]).wait != 0)
		die("dub build partial_ut failed");
	if (spawnProcess("./bin/partial_ut-test-unittest").wait != 0)
		die("partial_ut failed to run");

	e = execute([dub, "describe", "--single", "partial_ut2.d", "--config=unittest"]);
	if (!e.output.canFind(`"targetName": "ut"`))
		die("bad target name for partial_ut2");
	if (spawnProcess([dub, "build", "--single", "partial_ut2.d", "--config=unittest", "--build=unittest"]).wait != 0)
		die("dub build partial_ut2 failed");
	if (spawnProcess("./bin/ut").wait != 0)
		die("partial_ut2 failed to run");

	e = execute([dub, "describe", "--single", "full_ut.d", "--config=unittest"]);
	if (!e.output.canFind(`"targetName": "full_ut"`))
		die("bad target name for full_ut");
	if (spawnProcess([dub, "build", "--single", "full_ut.d", "--config=unittest", "--build=unittest"]).wait != 0)
		die("dub build full_ut failed");
	if (spawnProcess("bin/full_ut").wait != 0)
		die("full_ut failed to run");
}
