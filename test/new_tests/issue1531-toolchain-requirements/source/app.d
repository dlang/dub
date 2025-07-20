import common;

import std.algorithm;
import std.conv;
import std.file;
import std.path;
import std.process;

version (LDC)
	immutable dcName = "ldc";
else version (DigitalMars)
	immutable dcName = "dmd";
else version (GNU)
	immutable dcName = "gdc";
else static assert (false, "Unknown compiler");
string dcTestDubSdlPath;

void main () {
	testDub(">=1.7.0", true);
	testDub("~>0.9", false);
	testDub("~>999.0", false);

	if (exists("test"))
		rmdirRecurse("test");
	mkdirRecurse(buildPath("test", "source"));
	dcTestDubSdlPath = buildPath("test", "dub.sdl");
	write(buildPath("test", "source", "app.d"), q{
		module dubtest1531;
		void main () {}
	});

	immutable ver = getDcVer();

	Version nextMajor = ver;
	nextMajor.major += 1;

	testDc("==" ~ ver, true);
	testDc(">=" ~ ver, true);
	testDc(">" ~ ver, false);
	testDc("<=" ~ ver, true);
	testDc("<" ~ ver, false);
	testDc(">=" ~ ver ~ " <" ~ nextMajor, true);
	testDc("~>" ~ ver, true);
	testDc("~>" ~ nextMajor, false);
	testDc("no", false);
}

struct Version {
	uint major;
	uint minor;
	uint patch;
	string tail;

	string toString() const {
		return text(major, ".", minor, ".", patch, tail);
	}
	alias toString this;
}

Version getDcVer() {
	import std.regex;

	immutable dc = environment["DC"];
	immutable dcBase = baseName(dc);
	Regex!char r;

	if (dcBase.canFind("ldc") || dcBase.canFind("ldmd"))
		r = regex(`\((\d+)\.(\d+)\.(\d+)([A-Za-z0-9.+-]*)\)`);
	else if (dcBase.canFind("gdc"))
			die("Not implemented");
	else if (dcBase.canFind("gdmd"))
		// TODO is this a bug? Should dub be using the FE version instead of the gdc version?
		return Version(__VERSION__ / 1000, __VERSION__ % 1000, 0);
	else if (dcBase.canFind("dmd"))
		r = regex(`v(\d+)\.(\d+)\.(\d+)([A-Za-z0-9.+-]*)`);
	else
			die("Unknown DC: ", dcBase);

	immutable p = execute([dc, "--version"]);
	if (p.status != 0)
		die("Failed to execute `DC --version`");

	const m = p.output.matchFirst(r);
	if (!m)
		die("DC --version printed in unknown format");

	Version result;
	result.major = m[1].to!uint;
	result.minor = m[2].to!uint;
	result.patch = m[3].to!uint;
	result.tail = m[4];
	return result;

}

void testDub(string requirement, bool expectSuccess) {
	if (requirement !is null)
		requirement = `toolchainRequirements dub="` ~ requirement ~ `"`;

	auto p = pipeProcess([dub, "-"], Redirect.stdin);

	p.stdin.writefln(q{
			/+ dub.sdl:
			%s
			+/
			void main() {}
		},
		requirement);

	p.stdin.close();

	immutable gotSuccess = p.pid.wait == 0;
	if (gotSuccess != expectSuccess)
		die("Did not pass with: ", requirement);
}

void testDc(string requirement, bool expectSuccess) {
	import std.stdio;
	File(dcTestDubSdlPath, "w").writefln(`
name "dubtest1531"
toolchainRequirements %s="%s"`, dcName, requirement);

	writeln("Expecting ", expectSuccess ? "success" : "failure", " with ", dcName, " ", requirement);
	stdout.flush();
	immutable gotSuccess = spawnProcess([dub, "build", "-q", "--root=test"]).wait == 0;
	if (gotSuccess != expectSuccess) {
		immutable error = gotSuccess ? "Did not fail" : "Did not pass";
		die(error, " with ", dcName, `="`, requirement, `"`);
	}
}
