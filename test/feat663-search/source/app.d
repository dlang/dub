import common;

import std.algorithm;
import std.array;
import std.file;
import std.path;
import std.process;
import std.stdio;

void main () {
	{
		auto p = execute([dub, "search"]);
		if (p.status == 0)
			die("`dub search` succeeded");
	}

	{
		auto p = execute([dub, "search", "nonexistent123456789package"]);
		if (p.status == 0)
			die("`dub search nonexistent123456789package` succeeded");
	}

	{
		auto p = pipeProcess([dub, "search", `"dub-registry"`], Redirect.stdout | Redirect.stderrToStdout);
		const output = p.stdout.byLineCopy.array;

		if (p.pid.wait != 0) {
			immutable error = q"(`dub search "dub-registry"` failed)";
			writeln(error);
			writeln("Output:");
			foreach (line; output)
				writeln(line);
			die(error);
		}

		import std.regex;
		auto r = regex(`^\s\sdub-registry \(.*\)\s`);
		if (!output.any!(line => line.matchFirst(r))) {
			immutable error = q"(`dub search "dub-registry"` did not contain the desired line)";
			writeln(error);
			writeln("Output:");
			foreach (line; output)
				writeln(line);
			die(error);
		}
	}
}
