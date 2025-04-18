/+ dub.sdl:
	name "0-init-fail-json"
	dependency "common" path="./common"
 +/

module _0_init_fail_json;

import std.file : exists, remove;
import std.path : buildPath;
import std.process : environment, spawnProcess, wait;

import common;

int main()
{
	enum packname = "0-init-fail-pack";
	enum deps = "logger PACKAGE_DONT_EXIST"; // would be very unlucky if it does exist...

	auto dub = environment.get("DUB");
	if (!dub.length)
		die(`Environment variable "DUB" must be defined to run the tests.`);

	//** if $$DUB init -n $packname $deps -f json 2>/dev/null; then
	if (!spawnProcess([dub, "init", "-n", packname, deps, "-f", "json"]).wait)
		die("Init with unknown non-existing dependency expected to fail");

	//** if [ -e $packname/dub.json ]; then # package is there, it should have failed
	const filepath = buildPath(packname, "dub.json");
	if (filepath.exists)
	{
		remove(packname);
		die(filepath ~ " was not created");
	}

	return 0;
}
