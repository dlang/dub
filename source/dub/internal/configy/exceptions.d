/*******************************************************************************

    Definitions for Exceptions used by the config module.

    Copyright:
        Copyright (c) 2019-2022 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module dub.internal.configy.exceptions;

import dub.internal.configy.utils;
import dub.internal.configy.backend.node;

import std.algorithm : filter, map;
import std.format;
import std.string : soundexer;

/*******************************************************************************

    Base exception type thrown by the config parser

    Whenever dealing with Exceptions thrown by the config parser, catching
    this type will allow to optionally format with colors:
    ```
    try
    {
        auto conf = parseConfigFile!Config(cmdln);
        // ...
    }
    catch (ConfigException exc)
    {
        writeln("Parsing the config file failed:");
        writelfln(isOutputATTY() ? "%S" : "%s", exc);
    }
    ```

*******************************************************************************/

public abstract class ConfigException : Exception
{
    /// Position at which the error happened
    public Location loc;

    /// The path in the configuration structure at which the error resides
    public string path;

    /// Constructor
    public this (string path, Location position,
                 string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow @nogc
    {
        super(null, file, line);
        this.path = path;
        this.loc = position;
    }

    /***************************************************************************

        Overrides `Throwable.toString` and its sink overload

        It is quite likely that errors from this module may be printed directly
        to the end user, who might not have technical knowledge.

        This format the error in a nicer format (e.g. with colors),
        and will additionally provide a stack-trace if the `ConfigFillerDebug`
        `debug` version was provided.

        Format_chars:
          The default format char ("%s") will print a regular message.
          If an uppercase 's' is used ("%S"), colors will be used.

        Params:
          sink = The sink to send the piece-meal string to
          spec = See https://dlang.org/phobos/std_format_spec.html

    ***************************************************************************/

    public override string toString () scope
    {
        // Need to be overriden otherwise the overload is shadowed
        return super.toString();
    }

    /// Ditto
    public override void toString (scope void delegate(in char[]) sink) const scope
        @trusted
    {
        // This breaks the type system, as it blindly trusts a delegate
        // However, the type system lacks a way to sanely build an utility
        // which accepts a delegate with different qualifiers, so this is the
        // less evil approach.
        this.toString(cast(SinkType) sink, FormatSpec!char("%s"));
    }

    /// Ditto
    public void toString (scope SinkType sink, in FormatSpec!char spec)
        const scope @safe
    {
        if (this.loc.toString(sink, spec))
            sink(": ");

        if (this.path.length)
        {
            const useColors = spec.spec == 'S';
            if (useColors) sink(Yellow);
            sink(this.path);
            if (useColors) sink(Reset);
            sink(": ");
        }

        this.formatMessage(sink, spec);

        debug (ConfigFillerDebug)
            this.stackTraceToString(sink);
    }

    /// Print the regular D stack-trace for debugging purpose
    public void stackTraceToString (scope SinkType sink) const scope @safe {
        sink("\n\tError originated from: ");
        Location(this.file, this.line).toString(sink);

        if (!this.info)
            return;

        () @trusted nothrow {
            try {
                sink("\n----------------");
                foreach (t; info) {
                    sink("\n"); sink(t);
                }
            }
            // ignore more errors
            catch (Throwable) {}
        }();
    }

    /// Ditto
    public final string stackTraceToString () const scope @safe {
        string buffer;
        this.stackTraceToString((in char[] data) { buffer ~= data; });
        return buffer;
    }

    /// Hook called by `toString` to simplify coloring
    protected abstract void formatMessage (
        scope SinkType sink, in FormatSpec!char spec)
        const scope @safe;
}

/// A configuration exception that is only a single message
package final class ConfigExceptionImpl : ConfigException
{
    public this (string msg, Location position,
                 string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow @nogc
    {
        this(msg, null, position, file, line);
    }

    public this (string msg, string path, Location position,
                 string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow @nogc
    {
        super(path, position, file, line);
        this.msg = msg;
    }

    protected override void formatMessage (
        scope SinkType sink, in FormatSpec!char spec)
        const scope @safe
    {
        sink(this.msg);
    }
}

/// Exception thrown when the type of the YAML node does not match the D type
package final class TypeConfigException : ConfigException
{
    /// The actual (in the YAML document) type of the node
    public string actual;

    /// The expected (as specified in the D type) type
    public string expected;

    /// Constructor
    public this (Node node, string expected, string path,
                 string file = __FILE__, size_t line = __LINE__)
        @safe nothrow
    {
        this(node.type().toString(), expected, path, node.location(),
             file, line);
    }

    /// Ditto
    public this (string actual, string expected, string path,
        Location position, string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow @nogc
    {
        super(path, position, file, line);
        this.actual = actual;
        this.expected = expected;
    }

    /// Format the message with or without colors
    protected override void formatMessage (
        scope SinkType sink, in FormatSpec!char spec)
        const scope @safe
    {
        const useColors = spec.spec == 'S';

        const fmt = "Expected to be %s, but is a %s";

        if (useColors)
            formattedWrite(sink, fmt, this.expected.paint(Green), this.actual.paint(Red));
        else
            formattedWrite(sink, fmt, this.expected, this.actual);
    }
}

/// Similar to a `TypeConfigException`, but specific to `Duration`
package final class DurationTypeConfigException : ConfigException
{
    /// The list of valid fields
    public immutable string[] DurationSuffixes = [
        "weeks", "days",  "hours",  "minutes", "seconds",
        "msecs", "usecs", "hnsecs", "nsecs",
    ];

    /// Actual type of the node
    public string actual;

    /// Constructor
    public this (Node node, string path, string file = __FILE__, size_t line = __LINE__)
        @safe nothrow
    {
        super(path, node.location(), file, line);
        this.actual = node.type.toString();
    }

    /// Format the message with or without colors
    protected override void formatMessage (
        scope SinkType sink, in FormatSpec!char spec)
        const scope @safe
    {
        const useColors = spec.spec == 'S';

        const fmt = "Field is of type %s, but expected a mapping with at least one of: %-(%s, %)";
        if (useColors)
            formattedWrite(sink, fmt, this.actual.paint(Red),
                           this.DurationSuffixes.map!(s => s.paint(Green)));
        else
            formattedWrite(sink, fmt, this.actual, this.DurationSuffixes);
    }
}

/// Exception thrown when an unknown key is found in strict mode
public class UnknownKeyConfigException : ConfigException
{
    /// The list of valid field names
    public immutable string[] fieldNames;

    /// The erroring key
    public string key;

    /// Constructor
    public this (string path, string key, immutable string[] fieldNames,
                 Location position, string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow
    {
        super(path.addPath(key), position, file, line);
        this.key = key;
        this.fieldNames = fieldNames;
    }

    /// Format the message with or without colors
    protected override void formatMessage (
        scope SinkType sink, in FormatSpec!char spec)
        const scope @safe
    {
        const useColors = spec.spec == 'S';

        // Try to find a close match, as the error is likely a typo
        // This is especially important when the config file has a large
        // number of fields, where the message is otherwise near-useless.
        const origSound = soundexer(this.key);
        auto matches = this.fieldNames.filter!(f => f.soundexer == origSound);
        const hasMatch  = !matches.save.empty;

        if (hasMatch)
        {
            const fmt = "Key is not a valid member of this section. Did you mean: %-(%s, %)";
            if (useColors)
                formattedWrite(sink, fmt, matches.map!(f => f.paint(Green)));
            else
                formattedWrite(sink, fmt, matches);
        }
        else
        {
            // No match, just print everything
            const fmt = "Key is not a valid member of this section. There are %s valid keys: %-(%s, %)";
            if (useColors)
                formattedWrite(sink, fmt, this.fieldNames.length.paint(Yellow),
                               this.fieldNames.map!(f => f.paint(Green)));
            else
                formattedWrite(sink, fmt, this.fieldNames.length, this.fieldNames);
        }
    }
}

/// Exception thrown when a required key is missing
public class MissingKeyException : ConfigException
{
    /// Constructor
    public this (string path, Location position,
                 string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow @nogc
    {
        super(path, position, file, line);
    }

    /// Format the message with or without colors
    protected override void formatMessage (
        scope SinkType sink, in FormatSpec!char spec)
        const scope @safe
    {
        sink("Required key was not found in configuration or command line arguments");
    }
}

/// Wrap an user-thrown Exception that happened in a hook/ctor
public class ConstructionException : ConfigException
{
    /// Constructor
    public this (Exception next, string path, Location position,
                 string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow @nogc
    {
        super(path, position, file, line);
        this.next = next;
    }

    /// Format the message with or without colors
    protected override void formatMessage (
        scope SinkType sink, in FormatSpec!char spec)
        const scope @trusted
    {
        if (auto dyn = cast(ConfigException) this.next)
            dyn.toString(sink, spec);
        else
            sink(this.next.message);
    }
}

/// Thrown when an array read from config does not match a static array size
public class ArrayLengthException : ConfigException
{
    private size_t actual;
    private size_t expected;

    /// Constructor
    public this (size_t actual, size_t expected,
                 string path, in Location position,
                 string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow @nogc
    {
        assert(actual != expected);
        this.actual = actual;
        this.expected = expected;
        super(path, position, file, line);
    }

    /// Format the message with or without colors
    protected override void formatMessage (
        scope SinkType sink, in FormatSpec!char spec)
        const scope @trusted
    {
        import core.internal.string : unsignedToTempString;

        char[20] buffer = void;
        sink("Too ");
        sink((this.actual > this.expected) ? "many" : "few");
        sink(" entries for sequence: Expected ");
        sink(unsignedToTempString(this.expected, buffer));
        sink(", got ");
        sink(unsignedToTempString(this.actual, buffer));
    }
}
