module run_unittest.test_config;

import run_unittest.log;

import std.algorithm;
import std.array;
import std.conv;
import std.string;

enum Os {
	linux,
    windows,
	osx,
}

enum DcBackend {
	gdc,
	dmd,
	ldc,
}

enum DubCommand {
	run,
	test,
	build,
	none,
}

struct FeVersion {
	int value;
	alias value this;
}

struct TestConfig {
	Os[] os;
	DcBackend[] dc_backend;
	FeVersion dlang_fe_version_min;
	DubCommand[] dub_command = [ DubCommand.run ];
	string dub_config = null;
	string dub_build_type = null;
	string[] locks;
	bool expect_nonzero = false;

	string[] extra_dub_args;
}

TestConfig parseConfig(string content, ErrorSink errorSink) {
	TestConfig result;

	bool any_errors = false;
	foreach (line; content.lineSplitter) {
		line = line.strip();
		if (line.empty) continue;
		if (line[0] == '#') continue;

		const split = line.findSplit("=");
		if (!split[1].length) {
			errorSink.warn("Malformed config line '", line, "'. Missing =");
			continue;
		}

		const key = split[0].strip();
		const value = split[2];

		sw: switch (key) {
			static foreach (idx, _; TestConfig.tupleof) {
			case TestConfig.tupleof[idx].stringof:
				if (!handle(result.tupleof[idx], key, value, errorSink))
					any_errors = true;
				break sw;
			}
			default:
				errorSink.error("Setting ", key, " is not recognized.",
								" Available settings are: ",
								join([__traits(allMembers, TestConfig)], ", "));
				any_errors = true;
				break;
		}
	}

	if (any_errors)
		throw new Exception("Config file is not in the correct format");

	return result;
}


private:

bool handle(T)(ref T field, string memberName, string value, ErrorSink errorSink)
	 if (is(T == string) || !is(T: V[], V))
{
	value = value.strip();
	try {
		alias TgtType = TargetType!T;
		field = to!TgtType(value);
	} catch (ConvException e) {

		errorSink.error("Setting ", memberName, " does not recognize value ", value,
						". Possible values are: ", PossibleValues!T);
		return false;
	}

	static if (is(T == FeVersion)) {
		if (field < 2000 || field >= 3000) {
			errorSink.error("The value ", value, " for setting ", memberName, " does not respect the format ", PossibleValues!T);
			return false;
		}
	}
	return true;
}

bool handle(T)(ref T[] field, string memberName, string value, ErrorSink errorSink)
if (!is(immutable T == immutable char))
{
	value = value.strip();
	if ((value[0] != '[') ^ (value[$ - 1] != ']')) {
		errorSink.error("Setting ", memberName, " missmatch of [ and ]");
		return false;
	}

	string[] values;
	if (value[0] == '[') {
		assert(value[$ - 1] == ']');
		value = value[1 .. $ - 1];
		values = value.split(',');
	} else {
		values = [ value ];
	}

	bool any_errors = false;
	field = [];
	foreach (singleValue; values) {
		T thisValue;
		if (!handle(thisValue, memberName, singleValue, errorSink)) {
			any_errors = true;
			continue;
		}
		field ~= thisValue;
	}

	return !any_errors;
}

template PossibleValues (T) {
	static if (is(T == FeVersion)) {
		enum PossibleValues = "2XXX";
	} else static if (is(T == string)) {
		enum PossibleValues = "<anything>";
	} else static if (is(T == bool)) {
		enum PossibleValues = "true or false";
	} else {
		enum PossibleValues = (){
			string result;
			alias members = __traits(allMembers, T);

			result ~= members[0];
			foreach(member; members[1..$]) {
				result ~= ", ";
				result ~= member;
			}

			return result;
		}();
	}
}

template TargetType (T) {
	static if (__traits(isScalar, T))
		alias TargetType = T;
	else static if (is(T == FeVersion))
		alias TargetType = int;
	else static if (is(T == string))
		alias TargetType = T;
	else
		static assert(false, "Unknown type " ~ T.stringof);
}


void parseSuccess(out TestConfig config, out CaptureErrorSink sink, string content) {
	sink = new CaptureErrorSink();
	try {
		config = parseConfig(content, sink);
	} catch (Exception e) {
		assert(false, "Parsing failed with error messages: " ~ sink.toString());
	}
}

void parseFailure(out CaptureErrorSink sink, string content) {
	sink = new CaptureErrorSink();
	try {
		const _ = parseConfig(content, sink);
	} catch (Exception e) {
		return;
	}
	assert(false, "Parsing did not fail as expected");
}

unittest {
	TestConfig config;
	CaptureErrorSink sink;
	parseSuccess(config, sink, `
	dub_command = test
	os = [ linux,windows,    osx]
	dc_backend = [dmd, gdc,ldc]
       dub_config =    cappy-barry

	dlang_fe_version_min = 2108
	# A comment
		# and one with spaces
    locks=[XX,YY]

    dub_build_type = foo

    expect_nonzero = true
    extra_dub_args = [ -f, -b ]
	`);

	assert(config.dc_backend == [DcBackend.dmd, DcBackend.gdc, DcBackend.ldc]);
	assert(config.os == [Os.linux, Os.windows, Os.osx]);
	assert(config.dub_command == [ DubCommand.test ]);
	assert(config.dlang_fe_version_min == 2108);
	assert(config.dub_config == "cappy-barry");
	assert(config.locks == ["XX", "YY"]);
	assert(config.dub_build_type == "foo");
	assert(config.expect_nonzero);
	assert(config.extra_dub_args == ["-f", "-b"]);
	assert(sink.empty);
}

unittest {
	TestConfig config;
	CaptureErrorSink sink;
	parseSuccess(config, sink, `
dub_command = build

dc_backend = [gdc]
`);

	assert(config.dc_backend == [DcBackend.gdc]);
	assert(config.dub_command == [ DubCommand.build ]);
	assert(config.os == []);
	assert(config.dlang_fe_version_min == 0);
	assert(sink.empty);
}

unittest {
	CaptureErrorSink sink;
	parseFailure(sink, `dub_command = foo_bar_baz`);
	assert(sink.errors.length == 1);
	assert(sink.errors[0].canFind("dub_command"));
	assert(sink.errors[0].canFind("foo_bar_baz"));

	assert(sink.errors[0].canFind("run"));
	assert(sink.errors[0].canFind("build"));
	assert(sink.errors[0].canFind("test"));
}

unittest {
	CaptureErrorSink sink;
	parseFailure(sink, `strace = [boo]`);
	assert(sink.errors.length == 1);
	assert(sink.errors[0].canFind("strace"));

	assert(sink.errors[0].canFind("dub_command"));
	assert(sink.errors[0].canFind("dlang_fe_version_min"));
	assert(sink.errors[0].canFind("os"));
	assert(sink.errors[0].canFind("dc_backend"));
}

unittest {
	CaptureErrorSink sink;
	parseFailure(sink, `os = linux]`);
	assert(sink.errors.length == 1);
	assert(sink.errors[0].canFind("os"));
}

unittest {
	CaptureErrorSink sink;
	TestConfig config;
	parseSuccess(config, sink, `os = [linux, linux]`);

	assert(sink.empty);
	assert(config.os == [Os.linux, Os.linux]);
}

unittest {
	CaptureErrorSink sink;
	parseFailure(sink, `dc_backend = [gdmd]`);

	assert(sink.errors.length == 1);
	assert(sink.errors[0].canFind("dc_backend"));
	assert(sink.errors[0].canFind("gdmd"));
}

unittest {
	CaptureErrorSink sink;
	parseFailure(sink, `dc_backend = [ldmd2, gdmd, ldc2]`);

	assert(sink.errors.length == 3);
	assert(sink.errors[0].canFind("dc_backend"));
	assert(sink.errors[0].canFind("ldmd2"));
	assert(sink.errors[1].canFind("dc_backend"));
	assert(sink.errors[1].canFind("gdmd"));
	assert(sink.errors[2].canFind("dc_backend"));
	assert(sink.errors[2].canFind("ldc2"));
}

unittest {
	CaptureErrorSink sink;
	parseFailure(sink, `dlang_fe_version_min = 2.109`);

	assert(sink.errors.length == 1);
	assert(sink.errors[0].canFind("2.109"));
	assert(sink.errors[0].canFind("2XXX"));
}

unittest {
	CaptureErrorSink sink;
	parseFailure(sink, `dlang_fe_version_min = 2.foo`);

	assert(sink.errors.length == 1);
	assert(sink.errors[0].canFind("2.foo"));
}

unittest {
	CaptureErrorSink sink;
	parseFailure(sink, `dlang_fe_version_min = garbage`);

	assert(sink.errors.length == 1);
	assert(sink.errors[0].canFind("garbage"));
}

unittest {
	TestConfig config;
	CaptureErrorSink sink;
	parseSuccess(config, sink, `dub_command = [build, test]`);

	assert(config.dub_command == [DubCommand.build, DubCommand.test]);
}

unittest {
	CaptureErrorSink sink;
	parseFailure(sink, `expect_nonzero = 1`);

	assert(sink.errors.length == 1);
	assert(sink.errors[0].canFind("1"));
	assert(sink.errors[0].canFind("true"));
	assert(sink.errors[0].canFind("false"));
}
