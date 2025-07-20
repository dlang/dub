import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	auto p = teeProcess([dub, "build", "--force", "--root=sample"],
						Redirect.stdout | Redirect.stderrToStdout,
						["MY_VARIABLE": "teststrings"]);
	if (p.wait != 0)
		die("Dub build failed");

    if (!p.stdout.canFind("env_variables_work"))
        die("couldn't find `env_variables_work` in dub build output");
    if (p.stdout.canFind("Invalid source"))
        die("found `Invalid source` in dub build output");

}
