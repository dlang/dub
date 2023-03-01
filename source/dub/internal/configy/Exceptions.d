/*******************************************************************************

    Definitions for Exceptions used by the config module.

    Copyright:
        Copyright (c) 2019-2022 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module dub.internal.configy.Exceptions;

import dub.internal.configy.Utils;

import dub.internal.dyaml.exception;
import dub.internal.dyaml.node;

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
    public Mark yamlPosition;

    /// The path at which the key resides
    public string path;

    /// If non-empty, the key under 'path' which triggered the error
    /// If empty, the key should be considered part of 'path'
    public string key;

    /// Constructor
    public this (string path, string key, Mark position,
                 string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow @nogc
    {
        super(null, file, line);
        this.path = path;
        this.key = key;
        this.yamlPosition = position;
    }

    /// Ditto
    public this (string path, Mark position,
                 string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow @nogc
    {
        this(path, null, position, file, line);
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
        // Need to be overridden, otherwise the overload is shadowed
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
        import core.internal.string : unsignedToTempString;

        const useColors = spec.spec == 'S';
        char[20] buffer = void;

        if (useColors) sink(Yellow);
        sink(this.yamlPosition.name);
        if (useColors) sink(Reset);

        sink("(");
        if (useColors) sink(Cyan);
        sink(unsignedToTempString(this.yamlPosition.line, buffer));
        if (useColors) sink(Reset);
        sink(":");
        if (useColors) sink(Cyan);
        sink(unsignedToTempString(this.yamlPosition.column, buffer));
        if (useColors) sink(Reset);
        sink("): ");

        if (this.path.length || this.key.length)
        {
            if (useColors) sink(Yellow);
            sink(this.path);
            if (this.path.length && this.key.length)
                sink(".");
            sink(this.key);
            if (useColors) sink(Reset);
            sink(": ");
        }

        this.formatMessage(sink, spec);

        debug (ConfigFillerDebug)
        {
            sink("\n\tError originated from: ");
            sink(this.file);
            sink("(");
            sink(unsignedToTempString(line, buffer));
            sink(")");

            if (!this.info)
                return;

            () @trusted nothrow
            {
                try
                {
                    sink("\n----------------");
                    foreach (t; info)
                    {
                        sink("\n"); sink(t);
                    }
                }
                // ignore more errors
                catch (Throwable) {}
            }();
        }
    }

    /// Hook called by `toString` to simplify coloring
    protected abstract void formatMessage (
        scope SinkType sink, in FormatSpec!char spec)
        const scope @safe;
}

/// A configuration exception that is only a single message
package final class ConfigExceptionImpl : ConfigException
{
    public this (string msg, Mark position,
                 string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow @nogc
    {
        this(msg, null, null, position, file, line);
    }

    public this (string msg, string path, string key, Mark position,
                 string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow @nogc
    {
        super(path, key, position, file, line);
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
    public this (Node node, string expected, string path, string key = null,
                 string file = __FILE__, size_t line = __LINE__)
        @safe nothrow
    {
        this(node.nodeTypeString(), expected, path, key, node.startMark(),
             file, line);
    }

    /// Ditto
    public this (string actual, string expected, string path, string key,
                 Mark position, string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow @nogc
    {
        super(path, key, position, file, line);
        this.actual = actual;
        this.expected = expected;
    }

    /// Format the message with or without colors
    protected override void formatMessage (
        scope SinkType sink, in FormatSpec!char spec)
        const scope @safe
    {
        const useColors = spec.spec == 'S';

        const fmt = "Expected to be of type %s, but is a %s";

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
        super(path, null, node.startMark(), file, line);
        this.actual = node.nodeTypeString();
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

    /// Constructor
    public this (string path, string key, immutable string[] fieldNames,
                 Mark position, string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow @nogc
    {
        super(path, key, position, file, line);
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
    public this (string path, string key, Mark position,
                 string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow @nogc
    {
        super(path, key, position, file, line);
    }

    /// Format the message with or without colors
    protected override void formatMessage (
        scope SinkType sink, in FormatSpec!char spec)
        const scope @safe
    {
        sink("Required key was not found in configuration or command line arguments");
    }
}

/// Wrap an user-thrown Exception that happened in a Converter/ctor/fromString
public class ConstructionException : ConfigException
{
    /// Constructor
    public this (Exception next, string path, Mark position,
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
