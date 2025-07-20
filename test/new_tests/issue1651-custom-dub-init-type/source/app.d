import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	execute([dub, "remove", "custom-dub-init-dubpackage", "--non-interactive"]);

	if (exists("test")) rmdirRecurse("test");

	{
		auto p = spawnProcess([
			dub,
			"init",
			"-n",
			"test",
			"--format=sdl",
			"-t", "custom-dub-init-dubpackage",
			"--skip-registry=all",
			"--registry=file://" ~ getcwd().buildPath("sample"),
			"--",
			"--foo=bar",
		]);
		if (p.wait != 0)
			die("dub init -t failed");
	}

	if (!exists("test/dub.sdl"))
		die("No dub.sdl file has been generated");

	{
		auto p = teeProcess([dub], Redirect.stdout, null, Config.none, "test");
		p.wait;
		if (!p.stdout.canFind("--foo=bar"))
			die("Custom init type failed");
	}
}
