/**
	Handles all the console output of the Dub package manager, by providing useful
	methods for handling colored text. The module also disables colors when stdout
	and stderr are not a TTY in order to avoid ASCII escape sequences in piped
	output. The module can autodetect and configure itself in this regard by
	calling initLogging() at the beginning of the program. But, whether to color
	text or not can also be set manually with setLoggingColorsEnabled(bool).

	The output for the log levels error, warn and info is formatted like this:

	"			 <tag> <text>"
	 '----------'
	 fixed width

	the "tag" part can be colored (most oftenly will be) and always has a fixed
	width, which is defined as a const at the beginning of this module.

	The output for the log levels debug and diagnostic will be just the plain
	string.

	There are some default tag string and color values for some logging levels:
	- warn: "Warning", yellow bold
	- error: "Error", red bold

	Actually, for error and warn levels, the tag color is fixed to the ones listed
	above.

	Also, the default tag string for the info level is "" (the empty string) and
	the default color is white (usually it's manually set when calling logInfo
	with the wanted tag string, but this allows to just logInfo("text") without
	having to worry about the tag if it's not needed).

	Usage:
		After initializing the logging module with initLogging(), the functions
		logDebug(..), logDiagnostic(..), logInfo(..), logWarning(..) and logError(..)
		can be used to print log messages. Whether the messages are printed on stdout
		or stderr depends on the log level (warning and error go to stderr).
		The log(..) function can also be used. Check the signature and documentation
		of the functions for more information.

		The minimum log level to print can be configured using setLogLevel(..),
		and whether to color outputted text or not can be set with
		setLoggingColorsEnabled(..)

		The color(str, color) function can be used to color text within a log
		message, for instance like this:

		logInfo("Tag", Color.green, "My %s message", "colored".color(Color.red))

	Copyright: © 2018 Giacomo De Lazzari
	License: Subject to the terms of the MIT license, as written in the included LICENSE file.
	Authors: Giacomo De Lazzari
*/

module dub.logging;

import std.stdio;
import std.array;
import std.format;
import std.string;

import dub.internal.colorize : fg, mode;

/**
	An enum listing possible colors for terminal output, useful to set the color
	of a tag. Re-exported from d-colorize in dub.internal.colorize. See the enum
	definition there for a list of possible values.
*/
public alias Color = fg;

/**
	An enum listing possible text "modes" for terminal output, useful to set the
	text to bold, underline, blinking, etc...
	Re-exported from d-colorize in dub.internal.colorize. See the enum definition
	there for a list of possible values.
*/
public alias Mode = mode;

/// The tag width in chars, defined as a constant here
private const int TAG_WIDTH = 12;

/// Possible log levels supported
enum LogLevel {
	debug_,
	diagnostic,
	info,
	warn,
	error,
	none
}

// The current minimum log level to be printed
private shared LogLevel _minLevel = LogLevel.info;

/*
	Whether to print text with colors or not, defaults to true but will be set
	to false in initLogging() if stdout or stderr are not a TTY (which means the
	output is probably being piped and we don't want ASCII escape chars in it)
*/
private shared bool _printColors = true;

// isatty() is used in initLogging() to detect whether or not we are on a TTY
extern (C) int isatty(int);

/**
	This function must be called at the beginning for the program, before any
	logging occurs. It will detect whether or not stdout/stderr are a console/TTY
	and will consequently disable colored output if needed.

	Forgetting to call the function will result in ASCII escape sequences in the
	piped output, probably an undesiderable thing.
*/
void initLogging()
{
	import core.stdc.stdio;

	// Initially enable colors, we'll disable them during this functions if we
	// find any reason to
	_printColors = true;

	// The following stuff depends on the platform
	version (Windows)
	{
		version (CRuntime_DigitalMars)
		{
			if (!isatty(core.stdc.stdio.stdout._file) ||
					!isatty(core.stdc.stdio.stderr._file))
				_printColors = false;
		}
		else version (CRuntime_Microsoft)
		{
			if (!isatty(fileno(core.stdc.stdio.stdout)) ||
					!isatty(fileno(core.stdc.stdio.stderr)))
				_printColors = false;
		}
		else
			_printColors = false;
	}
	else version (Posix)
	{
		import core.sys.posix.unistd;

		if (!isatty(STDERR_FILENO) || !isatty(STDOUT_FILENO))
			_printColors = false;
	}
}

/// Sets the minimum log level to be printed
void setLogLevel(LogLevel level) nothrow
{
	_minLevel = level;
}

/// Gets the minimum log level to be printed
LogLevel getLogLevel()
{
	return _minLevel;
}

/// Set whether to print colors or not
void setLoggingColorsEnabled(bool enabled)
{
	_printColors = enabled;
}

/**
	Shorthand function to log a message with debug/diagnostic level, no tag string
	or tag color required (since there will be no tag).

	Params:
		level = The log level for the logged message
		fmt = See http://dlang.org/phobos/std_format.html#format-string
*/
void logDebug(T...)(string fmt, lazy T args) nothrow
{
	log(LogLevel.debug_, false, "", Color.init, fmt, args);
}

/// ditto
void logDiagnostic(T...)(string fmt, lazy T args) nothrow
{
	log(LogLevel.diagnostic, false, "", Color.init, fmt, args);
}

/**
	Shorthand function to log a message with info level, with custom tag string
	and tag color.

	Params:
		tag = The string the tag at the beginning of the line should contain
		tagColor = The color the tag string should have
		level = The log level for the logged message
		fmt = See http://dlang.org/phobos/std_format.html#format-string
*/
void logInfo(T...)(string tag, Color tagColor, string fmt, lazy T args) nothrow
{
	log(LogLevel.info, false, tag, tagColor, fmt, args);
}

/**
	Shorthand function to log a message with info level, this version prints an
	empty tag automatically (which is different from not having a tag - in this
	case there will be an identation of TAG_WIDTH chars on the left anyway).

	Params:
		level = The log level for the logged message
		fmt = See http://dlang.org/phobos/std_format.html#format-string
*/
void logInfo(T...)(string fmt, lazy T args) nothrow if (!is(T[0] : Color))
{
	log(LogLevel.info, false, "", Color.init, fmt, args);
}

/**
	Shorthand function to log a message with info level, this version doesn't
	print a tag at all, it effectively just prints the given string.

	Params:
		level = The log level for the logged message
		fmt = See http://dlang.org/phobos/std_format.html#format-string
*/
void logInfoNoTag(T...)(string fmt, lazy T args) nothrow if (!is(T[0] : Color))
{
	log(LogLevel.info, true, "", Color.init, fmt, args);
}

/**
	Shorthand function to log a message with warning level, with custom tag string.
	The tag color is fixed to yellow.

	Params:
		tag = The string the tag at the beginning of the line should contain
		level = The log level for the logged message
		fmt = See http://dlang.org/phobos/std_format.html#format-string
*/
void logWarnTag(T...)(string tag, string fmt, lazy T args) nothrow
{
	log(LogLevel.warn, false, tag, Color.yellow, fmt, args);
}

/**
	Shorthand function to log a message with warning level, using the default
	tag "Warning". The tag color is also fixed to yellow.

	Params:
		level = The log level for the logged message
		fmt = See http://dlang.org/phobos/std_format.html#format-string
*/
void logWarn(T...)(string fmt, lazy T args) nothrow
{
	log(LogLevel.warn, false, "Warning", Color.yellow, fmt, args);
}

/**
	Shorthand function to log a message with error level, with custom tag string.
	The tag color is fixed to red.

	Params:
		tag = The string the tag at the beginning of the line should contain
		level = The log level for the logged message
		fmt = See http://dlang.org/phobos/std_format.html#format-string
*/
void logErrorTag(T...)(string tag, string fmt, lazy T args) nothrow
{
	log(LogLevel.error, false, tag, Color.red, fmt, args);
}

/**
	Shorthand function to log a message with error level, using the default
	tag "Error". The tag color is also fixed to red.

	Params:
		level = The log level for the logged message
		fmt = See http://dlang.org/phobos/std_format.html#format-string
*/
void logError(T...)(string fmt, lazy T args) nothrow
{
	log(LogLevel.error, false, "Error", Color.red, fmt, args);
}

/**
	Log a message with the specified log level and with the specified tag string
	and color. If the log level is debug or diagnostic, the tag is not printed
	thus the tag string and tag color will be ignored. If the log level is error
	or warning, the tag will be in bold text. Also the tag can be disabled (for
	any log level) by passing true as the second argument.

	Params:
		level = The log level for the logged message
		disableTag = Setting this to true disables the tag, no matter what
		tag = The string the tag at the beginning of the line should contain
		tagColor = The color the tag string should have
		fmt = See http://dlang.org/phobos/std_format.html#format-string
*/
void log(T...)(
	LogLevel level,
	bool disableTag,
	string tag,
	Color tagColor,
	string fmt,
	lazy T args
) nothrow
{
	if (level < _minLevel)
		return;

	auto hasTag = true;
	if (level <= LogLevel.diagnostic)
		hasTag = false;
	if (disableTag)
		hasTag = false;

	auto boldTag = false;
	if (level >= LogLevel.warn)
		boldTag = true;

	try
	{
		string result = format(fmt, args);

		if (hasTag)
			result = tag.rightJustify(TAG_WIDTH, ' ').color(tagColor, boldTag ? Mode.bold : Mode.init) ~ " " ~ result;

		import dub.internal.colorize : cwrite;

		File output = (level <= LogLevel.info) ? stdout : stderr;

		if (output.isOpen)
		{
			output.cwrite(result, "\n");
			output.flush();
		}
	}
	catch (Exception e)
	{
		debug assert(false, e.msg);
	}
}

/**
	Colors the specified string with the specified color. The function is used to
	print colored text within a log message. The function also checks whether
	color output is enabled or disabled (when not outputting to a TTY) and, in the
	last case, just returns the plain string. This allows to use it like so:

	logInfo("Tag", Color.green, "My %s log message", "colored".color(Color.red));

	without worring whether or not colored output is enabled or not.

	Also a mode can be specified, such as bold/underline/etc...

	Params:
		str = The string to color
		color = The color to apply
		mode = An optional mode, such as bold/underline/etc...
*/
string color(const string str, const Color c, const Mode m = Mode.init)
{
	import dub.internal.colorize;

	if (_printColors)
		return dub.internal.colorize.color(str, c, bg.init, m);
	else
		return str;
}

/**
	This function is the same as the above one, but just accepts a mode.
	It's useful, for instance, when outputting bold text without changing the
	color.

	Params:
		str = The string to color
		mode = The mode, such as bold/underline/etc...
*/
string color(const string str, const Mode m = Mode.init)
{
	import dub.internal.colorize;

	if (_printColors)
		return dub.internal.colorize.color(str, fg.init, bg.init, m);
	else
		return str;
}
