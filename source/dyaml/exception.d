
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

///Exceptions thrown by D:YAML and _exception related code.
module dyaml.exception;


import std.algorithm;
import std.array;
import std.string;
import std.conv;


/// Base class for all exceptions thrown by D:YAML.
class YAMLException : Exception
{
    /// Construct a YAMLException with specified message and position where it was thrown.
    public this(string msg, string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow @nogc
    {
        super(msg, file, line);
    }
}

/// Position in a YAML stream, used for error messages.
struct Mark
{
    package:
        /// File name.
        string name_;
        /// Line number.
        ushort line_;
        /// Column number.
        ushort column_;

    public:
        /// Construct a Mark with specified line and column in the file.
        this(string name, const uint line, const uint column) @safe pure nothrow @nogc
        {
            name_   = name;
            line_   = cast(ushort)min(ushort.max, line);
            // This *will* overflow on extremely wide files but saves CPU time
            // (mark ctor takes ~5% of time)
            column_ = cast(ushort)column;
        }

        /// Get a file name.
        @property string name() @safe pure nothrow @nogc const
        {
            return name_;
        }

        /// Get a line number.
        @property ushort line() @safe pure nothrow @nogc const
        {
            return line_;
        }

        /// Get a column number.
        @property ushort column() @safe pure nothrow @nogc const
        {
            return column_;
        }

        /// Duplicate a mark
        Mark dup () const scope @safe pure nothrow
        {
            return Mark(this.name_.idup, this.line_, this.column_);
        }

        /// Get a string representation of the mark.
        string toString() const scope @safe pure nothrow
        {
            // Line/column numbers start at zero internally, make them start at 1.
            static string clamped(ushort v) @safe pure nothrow
            {
                return text(v + 1, v == ushort.max ? " or higher" : "");
            }
            return "file " ~ name_ ~ ",line " ~ clamped(line_) ~ ",column " ~ clamped(column_);
        }
}

// Base class of YAML exceptions with marked positions of the problem.
abstract class MarkedYAMLException : YAMLException
{
    /// Position of the error.
    Mark mark;

    // Construct a MarkedYAMLException with specified context and problem.
    this(string context, scope const Mark contextMark,
         string problem, scope const Mark problemMark,
         string file = __FILE__, size_t line = __LINE__) @safe pure nothrow
    {
        const msg = context ~ '\n' ~
                    (contextMark != problemMark ? contextMark.toString() ~ '\n' : "") ~
                    problem ~ '\n' ~ problemMark.toString() ~ '\n';
        super(msg, file, line);
        mark = problemMark.dup;
    }

    // Construct a MarkedYAMLException with specified problem.
    this(string problem, scope const Mark problemMark,
         string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow
    {
        super(problem ~ '\n' ~ problemMark.toString(), file, line);
        mark = problemMark.dup;
    }

    /// Construct a MarkedYAMLException from a struct storing constructor parameters.
    this(ref const(MarkedYAMLExceptionData) data) @safe pure nothrow
    {
        with(data) this(context, contextMark, problem, problemMark);
    }
}

package:
// A struct storing parameters to the MarkedYAMLException constructor.
struct MarkedYAMLExceptionData
{
    // Context of the error.
    string context;
    // Position of the context in a YAML buffer.
    Mark contextMark;
    // The error itself.
    string problem;
    // Position if the error.
    Mark problemMark;
}

// Constructors of YAML exceptions are mostly the same, so we use a mixin.
//
// See_Also: YAMLException
template ExceptionCtors()
{
    public this(string msg, string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow
    {
        super(msg, file, line);
    }
}

// Constructors of marked YAML exceptions are mostly the same, so we use a mixin.
//
// See_Also: MarkedYAMLException
template MarkedExceptionCtors()
{
    public:
        this(string context, const Mark contextMark, string problem,
             const Mark problemMark, string file = __FILE__, size_t line = __LINE__)
            @safe pure nothrow
        {
            super(context, contextMark, problem, problemMark,
                  file, line);
        }

        this(string problem, const Mark problemMark,
             string file = __FILE__, size_t line = __LINE__)
            @safe pure nothrow
        {
            super(problem, problemMark, file, line);
        }

        this(ref const(MarkedYAMLExceptionData) data) @safe pure nothrow
        {
            super(data);
        }
}
