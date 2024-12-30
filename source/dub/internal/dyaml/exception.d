
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

///Exceptions thrown by D:YAML and _exception related code.
module dub.internal.dyaml.exception;


import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.format;
import std.range;
import std.string;
import std.typecons;


/// Base class for all exceptions thrown by D:YAML.
class YAMLException : Exception
{
    mixin basicExceptionCtors;
}

/// Position in a YAML stream, used for error messages.
struct Mark
{
    /// File name.
    string name = "<unknown>";
    /// Line number.
    ushort line;
    /// Column number.
    ushort column;

    public:
        /// Construct a Mark with specified line and column in the file.
        this(string name, const uint line, const uint column) @safe pure nothrow @nogc
        {
            this.name = name;
            this.line = cast(ushort)min(ushort.max, line);
            // This *will* overflow on extremely wide files but saves CPU time
            // (mark ctor takes ~5% of time)
            this.column = cast(ushort)column;
        }

        /// Get a string representation of the mark.
        void toString(W)(ref W writer) const scope
        {
            // Line/column numbers start at zero internally, make them start at 1.
            void writeClamped(ushort v)
            {
                writer.formattedWrite!"%s"(v + 1);
                if (v == ushort.max)
                {
                    put(writer, "or higher");
                }
            }
            put(writer, name);
            put(writer, ":");
            writeClamped(line);
            put(writer, ",");
            writeClamped(column);
        }
}

/// Base class of YAML exceptions with marked positions of the problem.
abstract class MarkedYAMLException : YAMLException
{
    /// Position of the error.
    Mark mark;
    /// Additional position information, usually the start of a token or scalar
    Nullable!Mark mark2;
    /// A label for the extra information
    string mark2Label;

    // Construct a MarkedYAMLException with two marks
    this(string context, const Mark mark, string mark2Label, const Nullable!Mark mark2,
         string file = __FILE__, size_t line = __LINE__) @safe pure nothrow
    {
        super(context, file, line);
        this.mark = mark;
        this.mark2 = mark2;
        this.mark2Label = mark2Label;
    }

    // Construct a MarkedYAMLException with specified problem.
    this(string msg, const Mark mark,
         string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow
    {
        super(msg, file, line);
        this.mark = mark;
    }

    /// Custom toString to add context without requiring allocation up-front
    void toString(W)(ref W sink) const
    {
        sink.formattedWrite!"%s@%s(%s): "(typeid(this).name, file, line);
        put(sink, msg);
        put(sink, "\n");
        mark.toString(sink);
        if (!mark2.isNull)
        {
            put(sink, "\n");
            put(sink, mark2Label);
            put(sink, ":");
            mark2.get.toString(sink);
        }
        put(sink, "\n");
        put(sink, info.toString());
    }
    /// Ditto
    override void toString(scope void delegate(in char[]) sink) const
    {
        toString!(typeof(sink))(sink);
    }
    /// An override of message
    override const(char)[] message() const @safe nothrow
    {
        if (mark2.isNull)
        {
            return assertNotThrown(text(msg, "\n", mark));
        }
        else
        {
            return assertNotThrown(text(msg, "\n", mark, "\n", mark2Label, ": ", mark2.get));
        }
    }
}

/// Exception thrown on composer errors.
class ComposerException : MarkedYAMLException
{
    mixin MarkedExceptionCtors;
}

/// Exception thrown on constructor errors.
class ConstructorException : MarkedYAMLException
{
    mixin MarkedExceptionCtors;
}

/// Exception thrown on loader errors.
class LoaderException : MarkedYAMLException
{
    mixin MarkedExceptionCtors;
}

/// Exception thrown on node related errors.
class NodeException : MarkedYAMLException
{
    mixin MarkedExceptionCtors;
}

/// Exception thrown on parser errors.
class ParserException : MarkedYAMLException
{
    mixin MarkedExceptionCtors;
}

/// Exception thrown on Reader errors.
class ReaderException : MarkedYAMLException
{
    mixin MarkedExceptionCtors;
}

/// Exception thrown on Representer errors.
class RepresenterException : YAMLException
{
    mixin basicExceptionCtors;
}

/// Exception thrown on scanner errors.
class ScannerException : MarkedYAMLException
{
    mixin MarkedExceptionCtors;
}

private:

/// Constructors of marked YAML exceptions are identical, so we use a mixin.
///
/// See_Also: MarkedYAMLException
template MarkedExceptionCtors()
{
    public:
        this(string msg, const Mark mark1, string mark2Label,
             const Mark mark2, string file = __FILE__, size_t line = __LINE__)
            @safe pure nothrow
        {
            super(msg, mark1, mark2Label, Nullable!Mark(mark2), file, line);
        }

        this(string msg, const Mark mark,
             string file = __FILE__, size_t line = __LINE__)
            @safe pure nothrow
        {
            super(msg, mark, file, line);
        }
        this(string msg, const Mark mark1, string mark2Label,
             const Nullable!Mark mark2, string file = __FILE__, size_t line = __LINE__)
            @safe pure nothrow
        {
            super(msg, mark1, mark2Label, mark2, file, line);
        }
}
