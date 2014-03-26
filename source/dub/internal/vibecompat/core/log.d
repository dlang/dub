/**
	Central logging facility for vibe.

	Copyright: © 2012 rejectedsoftware e.K.
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
	shared LogLevel s_minLevel = LogLevel.info;
	shared LogLevel s_logFileLevel;
}

/// Sets the minimum log level to be printed.
void setLogLevel(LogLevel level) nothrow
{
	s_minLevel = level;
}

LogLevel getLogLevel()
{
	return s_minLevel;
}

/**
	Logs a message.

	Params:
		level = The log level for the logged message
		fmt = See http://dlang.org/phobos/std_format.html#format-string
*/
void logDebug(T...)(string fmt, lazy T args) nothrow { log(LogLevel.debug_, fmt, args); }
/// ditto
void logDiagnostic(T...)(string fmt, lazy T args) nothrow { log(LogLevel.diagnostic, fmt, args); }
/// ditto
void logInfo(T...)(string fmt, lazy T args) nothrow { log(LogLevel.info, fmt, args); }
/// ditto
void logWarn(T...)(string fmt, lazy T args) nothrow { log(LogLevel.warn, fmt, args); }
/// ditto
void logError(T...)(string fmt, lazy T args) nothrow { log(LogLevel.error, fmt, args); }

/// ditto
void log(T...)(LogLevel level, string fmt, lazy T args)
nothrow {
	if( level < s_minLevel ) return;
	string pref;
	final switch( level ){
		case LogLevel.debug_: pref = "trc"; break;
		case LogLevel.diagnostic: pref = "dbg"; break;
		case LogLevel.info: pref = "INF"; break;
		case LogLevel.warn: pref = "WRN"; break;
		case LogLevel.error: pref = "ERR"; break;
		case LogLevel.fatal: pref = "FATAL"; break;
		case LogLevel.none: assert(false);
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
			if (level == LogLevel.info) {
				stdout.writeln(txt.data());
				stdout.flush();
			} else {
				stderr.writeln(txt.data());
				stderr.flush();
			}
		}
	} catch( Exception e ){
		// this is bad but what can we do..
		debug assert(false, e.msg);
	}
}

/// Specifies the log level for a particular log message.
enum LogLevel {
	debug_,
	diagnostic,
	info,
	warn,
	error,
	fatal,
	none
}

