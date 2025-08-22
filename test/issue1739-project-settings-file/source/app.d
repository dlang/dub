import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample");
	write("dub.settings.json", `{"defaultArchitecture": "foo"}`);

	auto p = teeProcess([dub, "describe", "--single", "single.d"], Redirect.stdout | Redirect.stderrToStdout);
	p.wait;
	if (!p.stdout.canFind("Unsupported architecture: foo"))
		die("DUB did not find the project configuration with an adjacent architecture.");
}
