module run_unittest.runner.config;

import run_unittest.test_config;
import run_unittest.log;

import core.sync.mutex;
import std.algorithm;

struct RunnerConfig {
	Os os;
	DcBackend dc_backend;
	FeVersion dlang_fe_version;

	string dubPath;
	string dc;
	bool color;
	int jobs;
}

RunnerConfig generateRunnerConfig(ErrorSink sink) {
	import std.process;

	RunnerConfig config;

	version(linux) config.os = Os.linux;
	else version(Windows) config.os = Os.windows;
	else version(OSX) config.os = Os.osx;
	else static assert(false, "Unknown target OS");

	version(DigitalMars) config.dc_backend = DcBackend.dmd;
	else version(LDC) config.dc_backend = DcBackend.ldc;
	else version(GNU) config.dc_backend = DcBackend.gdc;
	else static assert(false, "Unknown compiler");
	{
		auto envDc = environment.get("DC");
		if (envDc.length == 0) {
			sink.warn("The DC environment is empty. Defaulting to dmd");
			envDc = "dmd";
		}

		handleEnvironmentDc(envDc, config.dc_backend, sink);
		config.dc = envDc;
	}

	import std.format;
	config.dlang_fe_version = __VERSION__;
	{
		const envFe = environment.get("FRONTEND");
		handleEnvironmentFrontend(envFe, sink);
	}

	import std.path;
	immutable fallbackPath = buildNormalizedPath(absolutePath("../bin/dub"));
	config.dubPath = environment.get("DUB", fallbackPath);

	return config;
}


private:

void handleEnvironmentFrontend(string envFe, ErrorSink errorSink) {
	if (envFe.length == 0) return;

	errorSink.warn("The FRONTEND environment variable is ignored and this script will compute it by itself");
	errorSink.warn("You can safely remove the variable from the environment");
}

unittest {
	auto sink = new CaptureErrorSink();
	handleEnvironmentFrontend(null, sink);
	assert(sink.empty());
}

unittest {
	auto sink = new CaptureErrorSink();
	handleEnvironmentFrontend("", sink);
	assert(sink.empty());
}

unittest {
	auto sink = new CaptureErrorSink();
	handleEnvironmentFrontend("2109", sink);
	assert(!sink.empty());
	assert(sink.warningsBlock.canFind("FRONTEND"));
}

void handleEnvironmentDc(string envDc, DcBackend thisDc, ErrorSink sink) {
	import std.path;

	const dcBasename = baseName(envDc);
	DcBackend dcBackendGuess;
	if (dcBasename.canFind("gdmd"))
		dcBackendGuess = DcBackend.gdc;
	else if (dcBasename.canFind("gdc")) {
		sink.error("Running the testsuite with plain gdc is not supported.");
		sink.error("Please use (an up-to-date) gdmd instead.");
		throw new Exception("gdc is not supported. Use gdmd");
	} else if (dcBasename.canFind("ldc", "ldmd"))
		dcBackendGuess = DcBackend.ldc;
	else if (dcBasename.canFind("dmd"))
		dcBackendGuess = DcBackend.dmd;
	else {
		// Dub will fail as well with this
		throw new Exception("DC environment variable(" ~ envDc ~ ") does not seem to be a D compiler");
	}

	if (dcBackendGuess != thisDc) {
		sink.error("The DC environment is not the same backend as the D compiler");
		sink.error("used to build this script: ", dcBackendGuess, " vs ", thisDc, '.');
		sink.error("If you invoke this script manually make sure you compile this");
		sink.error("script with the same compiler that you will run the tests with.");

		throw new Exception("$DC is not the same compiler as the one used to build this script");
	}
}

CaptureErrorSink successfullDcTestCase(string env, DcBackend backend) {
	auto sink = new CaptureErrorSink();
	try {
		handleEnvironmentDc(env, backend, sink);
	} catch (Exception e) {
		assert(false, sink.toString());
	}
	return sink;
}

CaptureErrorSink unsuccessfullDcTestCase(string env, DcBackend backend) {
	auto sink = new CaptureErrorSink();
	try {
		handleEnvironmentDc(env, backend, sink);
	} catch (Exception e) {
		return sink;
	}
	assert(false, "handleEnvironemntDc did not fail as expected");
}

unittest {
	auto sink = successfullDcTestCase("/usr/bin/dmd", DcBackend.dmd);
	assert(sink.empty, sink.toString);
}
unittest {
	auto sink = successfullDcTestCase("dmd", DcBackend.dmd);
	assert(sink.empty);
}

unittest {
	successfullDcTestCase("/usr/bin/dmd-2.109", DcBackend.dmd);
}
unittest {
	successfullDcTestCase("dmd-2.111", DcBackend.dmd);
}
unittest {
	successfullDcTestCase("/bin/gdmd", DcBackend.gdc);
}
unittest {
	successfullDcTestCase("x86_64-pc-linux-gnu-gdmd-15", DcBackend.gdc);
}
unittest {
	successfullDcTestCase("ldc2", DcBackend.ldc);
}
unittest {
	successfullDcTestCase("/usr/local/bin/ldc", DcBackend.ldc);
}
unittest {
	successfullDcTestCase("ldmd2-1.37", DcBackend.ldc);
}

unittest {
	unsuccessfullDcTestCase("/usr/bin/true", DcBackend.dmd);
}

unittest {
	auto sink = unsuccessfullDcTestCase("dmd", DcBackend.gdc);
	assert(sink.errorsBlock.canFind("dmd"));
	assert(sink.errorsBlock.canFind("gdc"));

	assert(sink.errorsBlock.canFind("compile this script with the same compiler"));
}

unittest {
	auto sink = unsuccessfullDcTestCase("gdc-11", DcBackend.gdc);
	assert(sink.errorsBlock.canFind("gdc"));
	assert(sink.errorsBlock.canFind("gdmd"));
}
