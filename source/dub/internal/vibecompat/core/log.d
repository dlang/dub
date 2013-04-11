/**
	Central logging facility for vibe.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.internal.vibecompat.core.log;

import std.array;
import std.datetime;
import std.format;
import std.stdio;
import core.thread;

private {
	shared LogLevel s_minLevel = LogLevel.Info;
	shared LogLevel s_logFileLevel;
	shared bool s_plainLogging = false;
}

/// Sets the minimum log level to be printed.
void setLogLevel(LogLevel level) nothrow
{
	s_minLevel = level;
}

/// Disables output of thread/task ids with each log message
void setPlainLogging(bool enable)
{
	s_plainLogging = enable;
}

/**
	Logs a message.

	Params:
		level = The log level for the logged message
		fmt = See http://dlang.org/phobos/std_format.html#format-string
*/
void logTrace(T...)(string fmt, auto ref T args) nothrow { log(LogLevel.Trace, fmt, args); }
/// ditto
void logDebug(T...)(string fmt, auto ref T args) nothrow { log(LogLevel.Debug, fmt, args); }
/// ditto
void logInfo(T...)(string fmt, auto ref T args) nothrow { log(LogLevel.Info, fmt, args); }
/// ditto
void logWarn(T...)(string fmt, auto ref T args) nothrow { log(LogLevel.Warn, fmt, args); }
/// ditto
void logError(T...)(string fmt, auto ref T args) nothrow { log(LogLevel.Error, fmt, args); }

/// ditto
void log(T...)(LogLevel level, string fmt, auto ref T args)
nothrow {
	if( level < s_minLevel ) return;
	string pref;
	final switch( level ){
		case LogLevel.Trace: pref = "trc"; break;
		case LogLevel.Debug: pref = "dbg"; break;
		case LogLevel.Info: pref = "INF"; break;
		case LogLevel.Warn: pref = "WRN"; break;
		case LogLevel.Error: pref = "ERR"; break;
		case LogLevel.Fatal: pref = "FATAL"; break;
		case LogLevel.None: assert(false);
	}

	try {
		auto txt = appender!string();
		txt.reserve(256);
		formattedWrite(txt, fmt, args);

		auto threadid = cast(ulong)cast(void*)Thread.getThis();
		auto fiberid = cast(ulong)cast(void*)Fiber.getThis();
		threadid ^= threadid >> 32;
		fiberid ^= fiberid >> 32;

		if( level >= s_minLevel ){
			if( s_plainLogging ) writeln(txt.data());
			else writefln("[%08X:%08X %s] %s", threadid, fiberid, pref, txt.data());
			stdout.flush();
		}
	} catch( Exception e ){
		// this is bad but what can we do..
		debug assert(false, e.msg);
	}
}

/// Specifies the log level for a particular log message.
enum LogLevel {
	Trace,
	Debug,
	Info,
	Warn,
	Error,
	Fatal,
	None
}

