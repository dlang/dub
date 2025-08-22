import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	auto p = teeProcess([dub, "upfrade"], Redirect.stdout | Redirect.stderrToStdout);
	if (p.wait == 0)
		die(`"dub upfrade" should not succeed`);

	if (!p.stdout.canFind("Unknown command: upfrade"))
		die("Missing Unknown command line");

	if (!p.stdout.canFind("Did you mean 'upgrade'?"))
		die("Missing upgrade suggestion");

	if (p.stdout.canFind("build"))
		die("Did not expect to see build as a suggestion and did not want a full list of commands");
}
