import common;

import std.process;
import std.file;
import std.path;

void main () {
	// Ignore errors
	execute([dub, "remove", "fs-json-dubpackage", "--non-interactive"]);

	log("Trying to get fs-json-dubpackage (1.0.7)");
	{
		auto p = spawnProcess(
			[dub, "fetch",  "fs-json-dubpackage@1.0.7", "--skip-registry=all", "--registry=file://" ~ getcwd.buildPath("file-registry")]
		);
		if (p.wait != 0)
			die("Dub fetch failed");
	}

	{
		auto p = execute([dub, "remove", "fs-json-dubpackage@1.0.7"]);
		if (p.status != 0)
			die("Dub did not install package from file system.");
	}
}
