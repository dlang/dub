import std.algorithm;
import std.array;
import std.file;
import std.json;
import std.path;
import std.process;

import common;

void main()
{
	immutable describeDir = buildNormalizedPath(getcwd(), "../extra/4-describe");
	auto p = execute(
		[dub, "describe"], null, Config.stderrPassThrough, ulong.max, describeDir.buildPath("project"));

	if (p.status != 0)
		die("Printing describe JSON failed");

	const got = p.output;
	try {
		parseJSON(got);
	} catch (JSONException e) {
		write("dub-output.txt", got);
		die("Dub output was not in JSON format. Check dub-output.txt");
	}
}
