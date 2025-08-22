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

	this(RunnerConfig config, ErrorSink sink) {
		this.config = config;
		this.sink = sink;

		// Get around issue https://github.com/dlang/dmd/issues/17955
		// with older compilers
		//locks = new typeof(locks);
		locks[""] = null;
		locksMutex = new typeof(locksMutex);
		lockExclusive = new typeof(lockExclusive);
	}

	int run (string[] patterns) {
		if (config.dc_backend == DcBackend.gdc) {
			import std.process;
			if ("DFLAGS" !in environment) {
				immutable defaultFlags = "-q,-Wno-error -allinst";
				sink.info("Adding ", defaultFlags, " to DFLAGS because gdmd will fail some tests without them");
				environment["DFLAGS"] = defaultFlags;
			}
		}

		const testCases = dirEntries(".", SpanMode.shallow)
			.filter!`a.isDir`
			.filter!(a => !canFind(["extra", "common", "run_unittest"], a.baseName))
			.filter!(entry => entry.name.matches(patterns))
			.map!(a => a.name.baseName)
			.array;

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
						   totalTests, successfulTests.atomicLoad, failedTests.atomicLoad, skippedTests.atomicLoad));
		return failedTests != 0;
	}

	void acquireLocks (const TestConfig testConfig) {
		if (testConfig.must_be_run_alone) {
			lockExclusive.writer.lock();
			return;
		}

		lockExclusive.reader.lock();

		const orderedKeys = testConfig.locks.dup.sort.release;
		auto ourLocks = new shared(Mutex)[](orderedKeys.length);

		onLocks((locks) {
			foreach (i, key; orderedKeys)
				ourLocks[i].atomicStore(cast(shared)locks.require(key, new Mutex()));
		});

		foreach (i; 0 .. ourLocks.length)
			ourLocks[i].lock;
	}

	void releaseLocks (const TestConfig testConfig) {
		if (testConfig.must_be_run_alone) {
			lockExclusive.writer.unlock();
			return;
		}
		lockExclusive.reader.unlock();

		onLocks((locks) {
			testConfig.locks.each!(key => locks[key].unlock);
		});
	}
private:
	shared ReadWriteMutex lockExclusive;
	shared Mutex[string] locks;
	void onLocks(void delegate(Mutex[string] unsharedLocks) action) {
		locksMutex.lock;
		scope(exit) locksMutex.unlock;
		action(cast(Mutex[string])locks);
	}

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
