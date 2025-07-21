import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	if (!execute([dub, "build", "--root=sample", "-v", "-f"]).output.canFind(" -lowmem "))
		die("DUB build with lowmem did not find -lowmem option.");

	if (!execute([dub, "test", "--root=sample", "-v", "-f"]).output.canFind(" -lowmem "))
		die("DUB test with lowmem did not find -lowmem option.");

	if (!execute([dub, "run", "--root=sample", "-v", "-f"]).output.canFind(" -lowmem "))
		die("DUB test with lowmem did not find -lowmem option.");

	immutable describeCmd = [
		dub,
		"describe",
		"--root=sample",
		"--data=options",
		"--data-list",
		"--verror"
	];
	auto p = teeProcess(describeCmd);
	p.wait;
	if (!p.stdout.canFind("lowmem"))
		die("DUB describe --data=options --data-list with lowmem did not find lowmem option.");
}
