/+ dub.sdl:
    name "build-timings-test"
+/
module build_timings_test;

import std.algorithm : canFind;
import std.exception : enforce;
import std.file : mkdirRecurse, rmdirRecurse, tempDir, write;
import std.path : absolutePath, buildPath, buildNormalizedPath, dirName;
import std.process : environment, execute;
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
	write(app, `import helper;
version(unittest) {} else void main() {
    import std.stdio : stderr;
    assert(answer() == 42);
    stderr.writeln("APP-RAN");
}`);
	enum goodHelper = `module helper;
int answer() { return 42; }
unittest { import std.stdio : stderr; stderr.writeln("TEST-RAN"); }
`;
	write(helper, goodHelper);

	string run(string[] args, bool success = true) {
		auto result = execute([dub, args[0], "--skip-registry=all", "--compiler=" ~ dc, "--root=" ~ root] ~ args[1 .. $],
			["DUB_HOME": buildPath(root, "dub-home")]);
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
	auto parallel = run(["build", "--force", "--parallel"] ~ timing);
	enforce(parallel.canFind("3 invocations"), parallel);
	auto combined = run(["build", "--force", "--build-mode=allAtOnce", "--build-timings"]);
	enforce(combined.canFind("compile+link") && combined.canFind("1 invocation;"), combined);
	auto separate = run(["build", "--force", "--build-timings"]);
	enforce(separate.canFind("2 invocations"), separate);
	auto ran = run(["run", "--force", "--quiet"] ~ timing);
	enforce(ran.canFind("APP-RAN") && ran.indexOf("Build timings (completed)") >= 0, ran);
	enforce(ran.indexOf("Build timings") < ran.indexOf("APP-RAN"), ran);
	auto tested = run(["test", "--force", "--parallel"] ~ timing);
	enforce(tested.canFind("TEST-RAN") && tested.indexOf("Build timings (completed)") >= 0, tested);
	enforce(tested.indexOf("Build timings") < tested.indexOf("TEST-RAN"), tested);

	write(helper, goodHelper ~ "unittest { assert(false); }\n");
	auto testFailure = run(["test", "--force"] ~ timing, false);
	enforce(testFailure.canFind("Build timings (completed)") && !testFailure.canFind("partial; build failed"), testFailure);
	write(helper, "module helper; invalid syntax here\n");
	auto failed = run(["build", "--force"] ~ timing, false);
	enforce(failed.canFind("Build timings (partial; build failed)") && failed.canFind("exit "), failed);
	write(helper, "module helper; extern(C) int missingTimingSymbol(); int answer() { return missingTimingSymbol(); }\n");
	auto linkFailure = run(["build", "--force"] ~ timing, false);
	enforce(linkFailure.canFind("partial; build failed") && linkFailure.canFind("3 invocations"), linkFailure);
	write(helper, goodHelper);
	auto unsupported = run(["build", "--rdmd", "--build-timings"], false);
	enforce(unsupported.canFind("--build-timings is not supported with --rdmd"), unsupported);

	// A dependency gets its own target label, in the same build report.
	mkdirRecurse(buildPath(root, "dep", "source"));
	write(buildPath(root, "dep", "dub.sdl"), "name \"timing-dep\"\ntargetType \"staticLibrary\"\n");
	write(buildPath(root, "dep", "source", "dep.d"), "module dep; int dependencyValue() { return 42; }\n");
	write(recipe, "name \"timing-fixture\"\ntargetType \"executable\"\ndependency \"timing-dep\" path=\"dep\"\n" ~ linkerSettings);
	write(helper, "module helper; import dep; int answer() { return dependencyValue(); }\n");
	auto dependency = run(["build", "--force", "--build-timings"]);
	enforce(dependency.canFind("timing-dep /") && dependency.canFind("timing-fixture /"), dependency);
	enforce(dependency.canFind("3 invocations"), dependency);
}
