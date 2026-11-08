/+ dub.sdl:
    name "build-timings-test"
+/
module build_timings_test;

import std.algorithm : canFind;
import std.exception : enforce;
import std.file : exists, mkdirRecurse, readText, rmdirRecurse, tempDir, write;
import std.json : JSONValue, parseJSON;
import std.path : absolutePath, buildPath, buildNormalizedPath, dirName;
import std.process : Config, environment, execute;
import std.random : uniform;
import std.conv : to;
import std.string : indexOf;

void main()
{
	version (Windows) enum dubName = "dub.exe";
	else enum dubName = "dub";
	auto dub = environment.get("DUB", buildPath(__FILE_FULL_PATH__.dirName.dirName, "bin", dubName));
	auto dc = environment.get("DC", "dmd");
	auto base = buildNormalizedPath(tempDir()).absolutePath;
	auto root = buildPath(base, "dub-build-timings-" ~ uniform(ulong.min, ulong.max).to!string);
	enforce(root.dirName == base);
	mkdirRecurse(buildPath(root, "source"));
	scope (exit) rmdirRecurse(root);
	auto recipe = buildPath(root, "dub.sdl");
	auto app = buildPath(root, "source", "app.d");
	auto helper = buildPath(root, "source", "helper.d");
	// Repeated forced builds should not reuse incremental linker state.
	enum linkerSettings = "lflags \"/INCREMENTAL:NO\" platform=\"windows-dmd\"\n";
	write(recipe, "name \"timing-fixture\"\ntargetType \"executable\"\n" ~ linkerSettings);
	enum startupCheck = `private void verifyTimingReport() {
    import std.file : readText;
    import std.json : parseJSON;
    import std.process : environment;
    auto path = environment.get("EXPECTED_TIMING_REPORT");
    if (path.length) {
        auto report = parseJSON(readText(path));
        assert(report["completed"].boolean && report["invocations"].array.length > 0);
    }
}`;
	write(app, startupCheck ~ `
import helper : answer;
version(unittest) {} else void main() {
    import std.stdio : stderr;
    verifyTimingReport();
    assert(answer() == 42);
    stderr.writeln("APP-RAN");
}`);
	enum goodHelper = "module helper;\n" ~ startupCheck ~ `
int answer() { return 42; }
unittest { import std.stdio : stderr; verifyTimingReport(); stderr.writeln("TEST-RAN"); }
`;
	write(helper, goodHelper);

	auto caller = buildPath(root, "caller");
	mkdirRecurse(caller);
	enum reportOption = "--build-timings-file=timings.json";
	JSONValue report() { return parseJSON(readText(buildPath(caller, "timings.json"))); }
	string run(string[] args, bool success = true, string startupReport = null) {
		string[string] env = ["DUB_HOME": buildPath(root, "dub-home")];
		if (startupReport.length) {
			auto path = buildPath(caller, startupReport);
			enforce(!exists(path), path);
			args ~= "--build-timings-file=" ~ startupReport;
			env["EXPECTED_TIMING_REPORT"] = path;
		}
		auto result = execute([dub, args[0], "--skip-registry=all", "--compiler=" ~ dc, "--root=" ~ root] ~ args[1 .. $],
			env, Config.none, size_t.max, caller);
		enforce((result.status == 0) == success, root ~ "\n" ~ args.to!string ~ "\n" ~ result.output);
		return result.output;
	}
	enum timing = ["--build-timings", "--build-mode=singleFile"];
	auto disabled = run(["build", "--force", "--build-mode=singleFile"]);
	enforce(!disabled.canFind("Build timings"), disabled);
	auto enabledCached = run(["build"] ~ timing);
	enforce(enabledCached.canFind("0 invocations"), enabledCached);
	auto built = run(["build", "--force"] ~ timing);
	enforce(built.canFind("Build timings (completed)") && built.canFind("3 invocations"), built);
	enforce(built.canFind("app.d") && built.canFind("helper.d"), built);
	auto cached = run(["build"] ~ timing);
	enforce(cached.canFind("No compiler or linker invocations") && cached.canFind("0 invocations"), cached);
	auto parallel = run(["build", "--force", "--parallel", reportOption] ~ timing);
	enforce(parallel.canFind("3 invocations"), parallel);
	auto json = report();
	enforce(json["schemaVersion"].integer == 1 && json["completed"].boolean);
	auto rows = json["invocations"].array;
	enforce(rows.length == 3);
	long sum;
	size_t compiled, linked;
	foreach (row; rows) {
		enforce(row["package"].str == "timing-fixture" && row["exitStatus"].integer == 0);
		auto start = row["startOffsetNs"].integer;
		auto end = row["endOffsetNs"].integer;
		enforce(start >= 0 && end >= start && end <= json["buildElapsedNs"].integer);
		enforce(row["elapsedNs"].integer == end - start);
		sum += end - start;
		if (row["phase"].str == "compile") {
			enforce(row["sources"].array.length == 1 && row["sources"][0].str.canFind(".d"));
			compiled++;
		} else {
			enforce(row["phase"].str == "link" && !row["sources"].array.length);
			linked++;
		}
	}
	enforce(compiled == 2 && linked == 1 && sum == json["summedInvocationNs"].integer);
	version (Posix) {
		import std.conv : octal;
		import std.file : setAttributes;
		setAttributes(buildPath(caller, "timings.json"), octal!600);
	}
	auto fileOnly = run(["build", "--build-mode=singleFile", reportOption]);
	enforce(!fileOnly.canFind("Build timings"), fileOnly);
	enforce(report()["completed"].boolean && !report()["invocations"].array.length);
	version (Posix) {
		import std.conv : octal;
		import std.file : getAttributes;
		enforce((getAttributes(buildPath(caller, "timings.json")) & octal!777) == octal!600);
	}
	enum unwritable = "--build-timings-file=missing-dir/report.json";
	enforce(run(["build", "--build-mode=singleFile", unwritable], false).canFind("Could not write build timings"));
	auto combined = run(["build", "--force", "--build-mode=allAtOnce", "--build-timings"]);
	enforce(combined.canFind("compile+link") && combined.canFind("1 invocation;"), combined);
	auto separate = run(["build", "--force", "--build-timings"]);
	enforce(separate.canFind("2 invocations"), separate);
	auto ran = run(["run", "--force", "--quiet"] ~ timing, true, "run.json");
	enforce(ran.canFind("APP-RAN") && ran.indexOf("Build timings (completed)") >= 0, ran);
	enforce(ran.indexOf("Build timings") < ran.indexOf("APP-RAN"), ran);
	auto tested = run(["test", "--build=unittest", "--force", "--parallel"] ~ timing, true, "test.json");
	enforce(tested.canFind("TEST-RAN") && tested.indexOf("Build timings (completed)") >= 0, tested);
	enforce(tested.indexOf("Build timings") < tested.indexOf("TEST-RAN"), tested);

	write(helper, goodHelper ~ `unittest {
    import std.stdio : stderr;
    verifyTimingReport();
    stderr.writeln("REPORT-READ-BEFORE-FAILURE");
    assert(false);
}`);
	auto testFailure = run(["test", "--build=unittest", "--force"] ~ timing, false, "failed-test.json");
	enforce(testFailure.canFind("Build timings (completed)") && !testFailure.canFind("partial; build failed"), testFailure);
	enforce(testFailure.canFind("REPORT-READ-BEFORE-FAILURE"), testFailure);
	write(helper, "module helper; invalid syntax here\n");
	auto failed = run(["build", "--force"] ~ timing, false);
	enforce(failed.canFind("Build timings (partial; build failed)") && failed.canFind("exit "), failed);
	write(helper, "module helper; extern(C) int missingTimingSymbol(); int answer() { return missingTimingSymbol(); }\n");
	auto linkFailure = run(["build", "--force", reportOption] ~ timing, false);
	enforce(linkFailure.canFind("partial; build failed") && linkFailure.canFind("3 invocations"), linkFailure);
	json = report();
	enforce(!json["completed"].boolean && json["invocations"].array.length == 3);
	bool failedLink;
	foreach (row; json["invocations"].array)
		if (row["phase"].str == "link" && row["exitStatus"].integer != 0) failedLink = true;
	enforce(failedLink);
	auto bothFailed = run(["build", "--force", unwritable] ~ timing, false);
	enforce(bothFailed.canFind("Could not write build timings") && bothFailed.canFind("missingTimingSymbol"), bothFailed);
	write(helper, goodHelper);
	auto unsupported = run(["build", "--rdmd", "--build-timings"], false);
	enforce(unsupported.canFind("--build-timings is not supported with --rdmd"), unsupported);
	enforce(run(["build", "--rdmd", reportOption], false).canFind("--build-timings-file is not supported with --rdmd"));

	// A dependency gets its own target label, in the same build report.
	mkdirRecurse(buildPath(root, "dep", "source"));
	write(buildPath(root, "dep", "dub.sdl"), "name \"timing-dep\"\ntargetType \"staticLibrary\"\n");
	write(buildPath(root, "dep", "source", "dep.d"), "module dep; int dependencyValue() { return 42; }\n");
	write(recipe, "name \"timing-fixture\"\ntargetType \"executable\"\ndependency \"timing-dep\" path=\"dep\"\n" ~ linkerSettings);
	write(helper, "module helper; import dep; int answer() { return dependencyValue(); }\n");
	auto dependency = run(["build", "--force", "--build-timings"]);
	enforce(dependency.canFind("timing-dep /") && dependency.canFind("timing-fixture /"), dependency);
	enforce(dependency.canFind("3 invocations"), dependency);

	write(recipe, "name \"timing-fixture\"\ntargetType \"none\"\n");
	write(buildPath(caller, "timings.json"), "stale report");
	run(["test", reportOption]);
	auto skipped = report();
	enforce(skipped["completed"].boolean && skipped["invocations"].array.length == 0);
	enforce(skipped["summedInvocationNs"].integer == 0 && skipped["buildElapsedNs"].integer == 0);
}
