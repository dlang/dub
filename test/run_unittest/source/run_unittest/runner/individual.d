module run_unittest.runner.individual;

import run_unittest.log;
import run_unittest.runner;
import run_unittest.test_config;

import std.algorithm;
import std.file;
import std.format;
import std.path;
import std.process;

struct TestCaseRunner {
	string tc;
	ErrorSink sink;
	Runner runner;
	void delegate() testResultAction = null;

	void run() {
		initConfig();
		ensureTestCanRun();

		runner.acquireLocks(testConfig);
		scope(exit) runner.releaseLocks(testConfig);

		scope(success) endTest();
		if (testConfig.dub_command.length != 0) {
			foreach (dubConfig; ["dub.sdl", "dub.json", "package.json"])
				if (exists(buildPath(tc, dubConfig))) {
					runDubTestCase();
					return;
				}
		}
	}

private:
	TestConfig testConfig;

	void ensureTestCanRun() {
		import std.array;
		import std.format;

		string reason;
		static foreach (member; ["dc_backend", "os"]) {{
			const testArray = __traits(getMember, testConfig, member);
			const myValue = __traits(getMember, runner.config, member);

			if (testArray.length && !testArray.canFind(myValue)) {
				reason = format("our %s (%s) is not in %s", member, myValue, testArray);
			}
		}}

		if (testConfig.dlang_fe_version_min != 0
			&& testConfig.dlang_fe_version_min > runner.config.dlang_fe_version)
			reason = format("our frontend version (%s) is lower than the minimum %s",
						  runner.config.dlang_fe_version, testConfig.dlang_fe_version_min);

		if (reason)
			skipTest(reason);
	}

	unittest {
		import std.exception;

		auto sink = new CaptureErrorSink();
		TestCaseRunner tcr = TestCaseRunner("foo", sink, Runner());

		tcr.runner.config.dc_backend = DcBackend.dmd;
		tcr.runner.config.os = Os.linux;
		tcr.testConfig.dc_backend = [ DcBackend.dmd ];
		tcr.testConfig.os = [ Os.linux ];

		tcr.ensureTestCanRun();

		tcr.testConfig.dc_backend = [ DcBackend.gdc, DcBackend.ldc, DcBackend.dmd];
		tcr.ensureTestCanRun();

		tcr.testConfig.dc_backend = [ DcBackend.gdc, DcBackend.ldc ];
		assertThrown!TCSkip(tcr.ensureTestCanRun());
		assert(sink.statusBlock.canFind("dmd"));
		assert(sink.statusBlock.canFind("dc_backend"));
		sink.clear();

		tcr.testConfig.dc_backend = [ DcBackend.dmd ];
		tcr.testConfig.os = [ Os.windows ];
		assertThrown!TCSkip(tcr.ensureTestCanRun());
		assert(sink.statusBlock.canFind("linux"), sink.toString());
		assert(sink.statusBlock.canFind("os"));
		assert(sink.statusBlock.canFind("windows"));
		sink.clear;

		tcr.testConfig.os = [ Os.linux ];
		tcr.testConfig.dlang_fe_version_min = 2100;
		tcr.runner.config.dlang_fe_version = 2105;
		tcr.ensureTestCanRun();

		tcr.testConfig.dlang_fe_version_min = 2110;
		assertThrown!TCSkip(tcr.ensureTestCanRun());
		assert(sink.statusBlock.canFind("2110"));
		assert(sink.statusBlock.canFind("2105"));
		sink.clear();
	}

	void initConfig() {
		immutable testConfigPath = buildPath(tc, "test.config");
		if (testConfigPath.exists) {
			immutable testConfigContents = readText(testConfigPath);
			try
				testConfig = parseConfig(testConfigContents, sink);
			catch (Exception e)
				failTest("Could not load test.config:", e);
		}

		testConfig.locks ~= tc;
	}

	void runDubTestCase()
	in(testConfig.dub_command.length != 0)
	{
		foreach (cmd; getDubCmds()) {
			auto env = [
				"DUB": runner.config.dubPath,
				"DC": runner.config.dc,
				"CURR_DIR": getcwd(),
			];
			immutable redirect = Redirect.stdout | Redirect.stderrToStdout;

			beginTest(cmd);
			auto pipes = pipeProcess(cmd, redirect, env, Config.none, tc);
			scope(exit) pipes.pid.wait;

			foreach (line; pipes.stdout.byLine)
				passthrough(line);

			// Handle possible skips or explicit failures
			if (testResultAction)
				testResultAction();

			immutable exitStatus = pipes.pid.wait;
			if (testConfig.expect_nonzero) {
				if (exitStatus == 0)
					failTest("Expected non-0 exit status");
			} else
				if (exitStatus != 0)
					failTest("Expected 0 exit status");
		}
	}

	string[][] getDubCmds() {
		string[][] result;
		foreach (dub_command; testConfig.dub_command) {
			string dubVerb;
			sw: final switch (dub_command) {
				static foreach (member; __traits(allMembers, DubCommand)) {
				case __traits(getMember, DubCommand, member):
					dubVerb = member;
					break sw;
				}
			}

			auto now = [runner.config.dubPath, dubVerb, "--force"];
			now ~= ["--color", runner.config.color ? "always" : "never"];
			if (testConfig.dub_build_type !is null)
				now ~= ["--build", testConfig.dub_build_type];
			now ~= testConfig.extra_dub_args;
			result ~= now;
		}
		return result;
	}

	unittest {
		auto tcr = TestCaseRunner();
		tcr.runner.config.dubPath = "dub";
		tcr.runner.config.color = true;
		tcr.testConfig.dub_command = [ DubCommand.build ];
		import std.stdio;
		assert(tcr.getDubCmds == [ ["dub", "build", "--force", "--color", "always"] ]);
	}

	unittest {
		auto tcr = TestCaseRunner();
		tcr.runner.config.dubPath = "dub";
		tcr.runner.config.color = false;
		tcr.testConfig.dub_command = [ DubCommand.build, DubCommand.test ];
		assert(tcr.getDubCmds == [
			["dub", "build", "--force", "--color", "never"],
			["dub", "test", "--force", "--color", "never"],
		]);
	}

	unittest {
		auto tcr = TestCaseRunner();
		tcr.runner.config.dubPath = "dub";
		tcr.runner.config.color = false;
		tcr.testConfig.dub_command = [ DubCommand.run ];
		tcr.testConfig.extra_dub_args = [ "--", "--switch" ];
		assert(tcr.getDubCmds == [
			["dub", "run", "--force", "--color", "never", "--", "--switch"],
		]);
	}

	void passthrough(const(char)[] logLine) {
		import std.typecons;
		import std.string;
		alias Tup = Tuple!(string, void delegate(const(char)[]));
		auto actions = [
			Tup("ERROR", &sink.error),
			Tup("INFO", &sink.info),
			Tup("FAIL", (line) {
					immutable cpy = line.idup;
					testResultAction = () => failTest(cpy);
			}),
			Tup("SKIP", (line) {
					immutable cpy = line.idup;
					testResultAction = () => skipTest(cpy);
			}),
		];

		foreach (tup; actions) {
			immutable match = "[" ~ tup[0] ~ "]: ";
			if (logLine.startsWith(match)) {
				const rest = logLine[match.length .. $];
				tup[1](rest);
				return;
			}
		}
		sink.info(logLine);
	}

	void beginTest(const string[] cmd) {
		import std.array;
		sink.status("starting: ", cmd.join(" "));
	}
	void endTest() {
		sink.status("success");
	}
	noreturn failTest(const(char)[] reason, in Throwable exception = null) {
		sink.error("failed because: ", reason);

		if (exception) {
			import std.conv;
			sink.error("Error context:");
			foreach (trace; exception.info)
				sink.error(trace);
		}

		throw new TCFailure();
	}
	noreturn skipTest(const(char)[] reason) {
		sink.status("skipped because ", reason);
		throw new TCSkip();
	}
}


class TestResult : Exception {
	this() { super(""); }
}
class TCFailure : TestResult {}
class TCSkip : TestResult {}
