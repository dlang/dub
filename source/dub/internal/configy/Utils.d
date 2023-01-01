/*******************************************************************************

    Utilities used internally by the config parser.

    Compile this library with `-debug=ConfigFillerDebug` to get verbose output.
    This can be achieved with `debugVersions` in dub, or by depending on the
    `debug` configuration provided by `dub.json`.

    Copyright:
        Copyright (c) 2019-2022 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module dub.internal.configy.Utils;

import std.format;

/// Type of sink used by the `toString`
package alias SinkType = void delegate (in char[]) @safe;

/*******************************************************************************

    Debugging utility for config filler

    Since this module does a lot of meta-programming, some things can easily
    go wrong. For example, a condition being false might happen because it is
    genuinely false or because the condition is buggy.

    To make figuring out if a config is properly parsed or not, a little utility
    (config-dumper) exists, which will provide a verbose output of what the
    config filler does. To do this, `config-dumper` is compiled with
    the below `debug` version.

*******************************************************************************/

debug (ConfigFillerDebug)
{
    /// A thin wrapper around `stderr.writefln` with indentation
    package void dbgWrite (Args...) (string fmt, Args args)
    {
        import std.stdio;
        stderr.write(IndentChars[0 .. indent >= IndentChars.length ? $ : indent]);
        stderr.writefln(fmt, args);
    }

    /// Log a value that is to be returned
    /// The value will be the first argument and painted yellow
    package T dbgWriteRet (T, Args...) (auto ref T return_, string fmt, Args args)
    {
        dbgWrite(fmt, return_.paint(Yellow), args);
        return return_;
    }

    /// The current indentation
    package size_t indent;

    /// Helper for indentation (who needs more than 16 levels of indent?)
    private immutable IndentChars = "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t";
}
else
{
    /// No-op
    package void dbgWrite (Args...) (string fmt, lazy Args args) {}

    /// Ditto
    package T dbgWriteRet (T, Args...) (auto ref T return_, string fmt, lazy Args args)
    {
        return return_;
    }
}

/// Thin wrapper to simplify colorization
package struct Colored (T)
{
    /// Color used
    private string color;

    /// Value to print
    private T value;

    /// Hook for `formattedWrite`
    public void toString (scope SinkType sink)
    {
        static if (is(typeof(T.init.length) : size_t))
            if (this.value.length == 0) return;

        formattedWrite(sink, "%s%s%s", this.color, this.value, Reset);
    }
}

/// Ditto
package Colored!T paint (T) (T arg, string color)
{
    return Colored!T(color, arg);
}

/// Paint `arg` in color `ifTrue` if `cond` evaluates to `true`, use color `ifFalse` otherwise
package Colored!T paintIf (T) (T arg, bool cond, string ifTrue, string ifFalse)
{
    return Colored!T(cond ? ifTrue : ifFalse, arg);
}

/// Paint a boolean in green if `true`, red otherwise, unless `reverse` is set to `true`,
/// in which case the colors are swapped
package Colored!bool paintBool (bool value, bool reverse = false)
{
    return value.paintIf(reverse ^ value, Green, Red);
}

/// Reset the foreground color used
package immutable Reset = "\u001b[0m";
/// Set the foreground color to red, used for `false`, missing, errors, etc...
package immutable Red = "\u001b[31m";
/// Set the foreground color to red, used for warnings and other things
/// that should draw attention but do not pose an immediate issue
package immutable Yellow = "\u001b[33m";
/// Set the foreground color to green, used for `true`, present, etc...
package immutable Green = "\u001b[32m";
/// Set the foreground color to green, used field names / path
package immutable Cyan = "\u001b[36m";
