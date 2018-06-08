/**
	Handles all the console output of the Dub package manager, by providing useful
  methods for handling colored text. The module also disables colors when stdout
  and stderr are not a TTY in order to avoid ASCII escape sequences in piped
  output. The module can autodetect and configure itself in this regard by
  calling initLogging() at the beginning of the program. But, whether to color
  text or not can also be set manually with printColorsInLog(bool).

  The output for the log levels error, warn and info is formatted like this:

  "       <tag> <text>"
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

    The minimum log level to print can be configured using setLogLevel(..), and
    whether to color outputted text or not can be set with printColorsInLog(..).

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

import dub.internal.colorize : fg;

/**
  An enum listing possible colors for terminal output, useful to set the color
  of a tag
*/
public alias Color = fg;

/// The tag width in chars
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
private LogLevel _minLevel = LogLevel.info;

/*
  Whether to print text with colors or not, defaults to true but will be set
  to false in initLogging() if stdout or stderr are not a TTY (which means the
  output is probably being piped and we don't want ASCII escape chars in it)
*/
private bool _printColors = true;

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
void printColorsInLog(bool enabled)
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
  log(LogLevel.debug_, "", Color.init, fmt, args);
}

/// ditto
void logDiagnostic(T...)(string fmt, lazy T args) nothrow
{
  log(LogLevel.diagnostic, "", Color.init, fmt, args);
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
  log(LogLevel.info, tag, tagColor, fmt, args);
}

/**
	Shorthand function to log a message with info level, this version prints an
  empty tag automatically (which is different from not having a tag - in this
  case there will be an identation of TAG_WIDTH chars on the left anyway).

	Params:
		level = The log level for the logged message
		fmt = See http://dlang.org/phobos/std_format.html#format-string
*/
void logInfo(T...)(string fmt, lazy T args) nothrow
{
  log(LogLevel.info, "", Color.init, fmt, args);
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
  log(LogLevel.warn, tag, Color.yellow, fmt, args);
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
  log(LogLevel.warn, "Warning", Color.yellow, fmt, args);
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
  log(LogLevel.error, tag, Color.red, fmt, args);
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
  log(LogLevel.error, "Error", Color.red, fmt, args);
}

/**
	Log a message with the specified log level and with the specified tag string
  and color. If the log level is debug or diagnostic, the tag is not printed
  thus the tag string and tag color will be ignored.

	Params:
		level = The log level for the logged message
    tag = The string the tag at the beginning of the line should contain
    tagColor = The color the tag string should have
		fmt = See http://dlang.org/phobos/std_format.html#format-string
*/
void log(T...)(
  LogLevel level,
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

  try
  {
    string result = format(fmt, args);

    if (hasTag)
      result = tag.rightJustify(TAG_WIDTH, ' ').color(tagColor) ~ " " ~ result;

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
*/
string color(const string str, const Color c = Color.init)
{
  import dub.internal.colorize;

  if (_printColors == true)
    return dub.internal.colorize.color(str, c);
  else
    return str;
}
