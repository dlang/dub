/+ dub.json: {
   "name": "dflags_dont_disable_tests_script"
} +/

module main;

int main()
{
	import std.process;
	import std.path;
	import std.stdio;
	import std.algorithm;

	const dir = __FILE_FULL_PATH__.dirName();
	const testFile = dir.buildPath("dflags_dont_disable_tests.d");
	const dub = environment.get("DUB");
	auto env = environment.toAA();
	// An unobtrusive flag, supported by all compilers
	env["DFLAGS"] = "-g";

	const result = execute([dub, "test", "--single", testFile], env);

	if (result.status != 0) {
		stderr.writeln("Dub failed with exit code: ", result.status);
		stderr.writeln("Dub output:");
		stderr.writeln(result.output);
		stderr.writeln();
		return 1;
	}

	if (!result.output.canFind("IM_A_UNITTEST")) {
		stderr.writeln("unittest flags not passed with custom $DFLAGS");
		stderr.writeln("Dub output:");
		stderr.writeln(result.output);
		stderr.writeln();
		return 1;
	}

	return 0;
}
