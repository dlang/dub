module common;

import std.conv : text;
import std.stdio : File, stdout, stderr;

/// Name of the log file
enum logFile = "test.log";

/// has true if some test fails
bool any_errors = false;

/// prints (non error) message to standard output and log file
void log(Args...)(Args args)
	if (Args.length)
{
	const str = text("[INFO] ", args);
	version(Windows) stdout.writeln(str);
	else stdout.writeln("\033[0;33m", str, "\033[0m");
	stdout.flush;
	File(logFile, "a").writeln(str);
}

/// prints error message to standard error stream and log file
/// and set any_errors var to true value to indicate that some
/// test fails
void logError(Args...)(Args args)
{
	const str = text("[ERROR] ", args);
	version(Windows) stderr.writeln(str);
	else stderr.writeln("\033[0;31m", str, "\033[0m");
	stderr.flush;
	File(logFile, "a").writeln(str);
	any_errors = true;
}

void die(Args...)(Args args)
{
	stderr.writeln(args);
	throw new Exception("Test failed");
}
