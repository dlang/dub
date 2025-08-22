import common;

import std.algorithm;
import std.process;
import std.file;
import std.regex;

void main () {
	auto p = teeProcess([dub, "build", "--root=sample"], Redirect.stdout | Redirect.stderrToStdout);
	p.wait;
	// make sure the proper errors occur in the output
	assert(p.stdout.canFind(`sub configuration directive "bar" -> [baz] references a package that is not specified as a dependency`));
	assert(p.stdout.canFind(`sub configuration directive "staticlib-simple" -> [foo] references a configuration that does not exist`));
	assert(!p.stdout.canFind(`sub configuration directive "sourcelib-simple" -> [library] references a package that is not specified as a dependency`));
	assert(!p.stdout.canFind(`sub configuration directive "sourcelib-simple" -> [library] references a configuration that does not exist`));

	// make sure no bogus warnings are issued for packages with no sub configuration directives
	p = teeProcess([dub, "build", "--root=../1-exec-simple"], Redirect.stdout | Redirect.stderrToStdout);
	if (p.wait != 0)
		die("dub build 1-exec-simple failed");
	if (p.stdout.matchFirst(`sub configuration directive.*references`))
		die("didn't find the correct line in output");
}
