/+ dub.sdl:
	name "issue2241-minimum-version"
	dependency "common" path="./common"
	dependency "dub" path=".."
	description "Look for holes in dub.Dub.getMinimalVersion()."
+/

module _issue2241_minimum_version;

import std.algorithm.iteration : filter;
import std.algorithm.searching : any, canFind;
import std.array : join;
import std.process : environment, execute;
import std.string : lineSplitter;

import common;
import dub.dub;

int main()
{
	auto dub = environment.get("DUB");
	if (!dub.length)
		die(`Environment variable "DUB" must be defined to run the tests.`);

	foreach (tool; ["dscanner", "ddox"])
	{
		const toolVersion = Dub.getMinimalVersion(tool, __VERSION__);
		const toBuild = toolVersion == "0.0.0" ? tool : tool ~ "@" ~ toolVersion;
		log("Looking for deprecations in ", toBuild, " using frontend ", __VERSION__, "...");
		const result = execute([dub, "build", toBuild, "--force"]);
		if (result.status || result.output.lineSplitter.any!(a => a.canFind("Deprecation")))
			logError("Please review dub.Dub.getMinimalVersion() to prevent deprecations:\n",
				result.output.lineSplitter.filter!(a => a.canFind("Deprecation")).join("\n"));
	}

	return any_errors;
}
