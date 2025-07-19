import common;

import std.algorithm;
import std.file;
import std.process;
import std.string;

void main () {
	chdir("sample");

	auto arch = execute(["uname", "-m"]).output.strip;
	if (arch == "i386")
		arch = "x86";
	if (arch == "i686")
		arch = "x86";
	if (arch == "arm64")
		arch = "aarch64";

	if (spawnProcess([dub, "build", "--arch=" ~ arch]).wait != 0)
        die("Dub build failed");
	auto p = teeProcess(["./test"]);
	p.wait;
	immutable output = p.stdout.chomp;
	if (output != arch)
		die("Build settings ARCH was incorrect. Expected ", arch, " got ", output);
}
