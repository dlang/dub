module run_unittest.runner.runner;

import run_unittest.test_config;
import run_unittest.runner.config;
import run_unittest.runner.individual;
import run_unittest.log;

import core.sync.rwmutex;
import core.sync.mutex;
import core.atomic;
import std.array;
import std.algorithm;
import std.file;
import std.format;
import std.path;

struct Runner {
	RunnerConfig config;
	ErrorSink sink;

	shared int skippedTests;
	shared int failedTests;
	shared int successfulTests;
	int totalTests () {
		return skippedTests.atomicLoad + failedTests.atomicLoad + successfulTests.atomicLoad;
	}

	int run (string[] patterns) {
		// Get around issue https://github.com/dlang/dmd/issues/17955
		// with older compilers
		//locks = new typeof(locks);
		locks[""] = null;
		locksMutex = new typeof(locksMutex);

		skippedTests = failedTests = successfulTests = 0;

		if (config.dc_backend == DcBackend.gdc) {
			import std.process;
			if ("DFLAGS" !in environment) {
				immutable defaultFlags = "-q,-Wno-error -allinst";
				sink.info("Adding ", defaultFlags, " to DFLAGS because gdmd will fail some tests without them");
				environment["DFLAGS"] = defaultFlags;
			}
		}

		string[] testCases;

		import std.array;
		dirEntries(".", SpanMode.shallow)
			.filter!`a.isDir`
			.filter!(a => !canFind(["extra", "common"], a.baseName))
			.filter!(entry => entry.name.matches(patterns))
			.map!(a => a.name.baseName)
			.copy(appender(&testCases));

		void runTc(string tc) {
			auto tcSink = new TestCaseSink(sink, tc);
			auto tcRunner = TestCaseRunner(tc, tcSink, this);
			try {
				tcRunner.run();
				successfulTests.atomicOp!"+="(1);
			} catch (TCFailure) {
				failedTests.atomicOp!"+="(1);
			} catch (TCSkip) {
				skippedTests.atomicOp!"+="(1);
			} catch (Exception e) {
				tcSink.error("Unexpected exception was thrown: ", e);
				failedTests.atomicOp!"+="(1);
			}
		}

		import std.parallelism;
		if (config.jobs != 0)
			defaultPoolThreads = config.jobs - 1;
		foreach (tc; testCases.parallel)
			runTc(tc);

		if (totalTests == 0) {
			sink.error("No tests that match your search were found");
			throw new Exception("No tests were run");
		}

		sink.status(format("Summary %s total: %s successful %s failed and %s skipped",
						 totalTests, successfulTests, failedTests, skippedTests));
		return failedTests != 0;
	}

	void acquireLocks (const string[] keys, ErrorSink sink) {
		const orderedKeys = keys.dup.sort.release;
		auto ourLocks = new shared(Mutex)[](orderedKeys.length);

		{
			locksMutex.lock;
			scope(exit) locksMutex.unlock;

			foreach (i, key; orderedKeys)
				ourLocks[i] = (cast()locks).require(key, new shared Mutex());
		}

		ourLocks.each!`a.lock`;
	}

	void releaseLocks (const string[] keys, ErrorSink sink) {
		locksMutex.lock;
		scope(exit) locksMutex.unlock;
		keys.each!(key => locks[key].unlock);
	}
private:
	shared Mutex[string] locks;
	shared Mutex locksMutex;
}

private:

bool matches(string dir, string[] patterns) {
	if (patterns.length == 0) return true;

	foreach (pat; patterns)
		if (globMatch(baseName(dir), pat)) return true;
	return false;
}

unittest {
	assert(matches("./foo", []));
	assert(matches("./foo", ["foo"]));
	assert(matches("./foo", ["f*"]));
	assert(!matches("./foo", ["bar"]));
	assert(matches("./foo", ["b", "f*"]));
}
