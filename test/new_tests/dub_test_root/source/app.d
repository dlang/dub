import common;

import std.file;
import std.path;
import std.process;

void main () {
	immutable dub = environment["DUB"];

	immutable tmpDir = "tmp";
	if (tmpDir.exists) tmpDir.rmdirRecurse();

	tmpDir.mkdir;
	chdir(tmpDir);
	"dub.sdl".write(`name "foo"`);

	"source".mkdir;
	"source/foo.d".write(q{import dub_test_root : allModules;});

	auto p = spawnProcess([dub, "test", "--build-mode=singleFile"]);
	if (p.wait != 0)
		die("Dub test failed");
}
