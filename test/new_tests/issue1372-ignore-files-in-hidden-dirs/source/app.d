import common;

import std.algorithm;
import std.process;
import std.file;

void main () {
	log("Compile and ignore hidden directories");
	auto p = teeProcess([dub, "run", "--root=sample", "--config=normal", "--force"]);
	if (p.wait != 0) die("Dub run normal failed");
	if (!p.stdout.canFind("no hidden file compiled"))
		die("Normal compilation failed");

	log("compile and explicitly include file in hidden directories");
	p = teeProcess([dub, "run", "--root=sample", "--config=hiddenfile", "--force"]);
	if (p.wait != 0) die("Dub run hiddenfile failed");
	if (!p.stdout.canFind("hidden file compiled"))
		die("Hidden file compilation failed");

	log("Compile and explcitly include extra hidden directories");
	p = teeProcess([dub, "run", "--root=sample", "--config=hiddendir", "--force"]);
	if (p.wait != 0) die("Dub run hiddendir failed");
	if (!p.stdout.canFind("hidden dir compiled"))
		die("Hidden directory compilation failed");
}
