import std.file : exists, remove;
import std.path : buildPath;
import std.process : environment, spawnProcess, wait;

import common;

void main()
{
	enum packname = "0-init-fail-pack";
	immutable deps = ["logger", "PACKAGE_DONT_EXIST"]; // would be very unlucky if it does exist...

	if (!spawnProcess([dub, "init", "-n", packname] ~ deps ~ [ "-f", "json"]).wait)
		die("Init with unknown non-existing dependency expected to fail");

	const filepath = buildPath(packname, "dub.json");
	if (filepath.exists)
	{
		remove(packname);
		die(filepath, " was not created");
	}
}
