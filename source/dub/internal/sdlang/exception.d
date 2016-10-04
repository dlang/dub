// SDLang-D
// Written in the D programming language.

module dub.internal.sdlang.exception;

version (Have_sdlang_d) public import sdlang.exception;
else:

import std.exception;
import std.range;
import std.stdio;
import std.string;

import dub.internal.sdlang.ast;
import dub.internal.sdlang.util;

/// Abstract parent class of all SDLang-D defined exceptions.
abstract class SDLangException : Exception
{
	this(string msg, string file = __FILE__, size_t line = __LINE__)
	{
		super(msg, file, line);
	}
}

/// Thrown when a syntax error is encounterd while parsing.
class ParseException : SDLangException
{
	Location location;
	bool hasLocation;

	this(string msg, string file = __FILE__, size_t line = __LINE__)
	{
		hasLocation = false;
		super(msg, file, line);
	}

	this(Location location, string msg, string file = __FILE__, size_t line = __LINE__)
	{
		hasLocation = true;
		super("%s: %s".format(location.toString(), msg), file, line);
	}
}

/// Compatibility alias
deprecated("The new name is ParseException")
alias SDLangParseException = ParseException;

/++
Thrown when attempting to do something in the DOM that's unsupported, such as:

$(UL
$(LI Adding the same instance of a tag or attribute to more than one parent.)
$(LI Writing SDLang where:
	$(UL
	$(LI The root tag has values, attributes or a namespace. )
	$(LI An anonymous tag has a namespace. )
	$(LI An anonymous tag has no values. )
	$(LI A floating point value is infinity or NaN. )
	)
))
+/
class ValidationException : SDLangException
{
	this(string msg, string file = __FILE__, size_t line = __LINE__)
	{
		super(msg, file, line);
	}
}

/// Compatibility alias
deprecated("The new name is ValidationException")
alias SDLangValidationException = ValidationException;

/// Thrown when someting is wrong with the provided arguments to a function.
class ArgumentException : SDLangException
{
	this(string msg, string file = __FILE__, size_t line = __LINE__)
	{
		super(msg, file, line);
	}
}

/// Thrown by the DOM on empty range and out-of-range conditions.
abstract class DOMException : SDLangException
{
	Tag base; /// The tag searched from

	this(Tag base, string msg, string file = __FILE__, size_t line = __LINE__)
	{
		this.base = base;
		super(msg, file, line);
	}

	/// Prefixes a message with file/line information from the tag (if tag exists).
	/// Optionally takes output range as a sink.
	string customMsg(string msg)
	{
		if(!base)
			return msg;

		Appender!string sink;
		this.customMsg(sink, msg);
		return sink.data;
	}

	///ditto
	void customMsg(Sink)(ref Sink sink, string msg) if(isOutputRange!(Sink,char))
	{
		if(base)
		{
			sink.put(base.location.toString());
			sink.put(": ");
			sink.put(msg);
		}
		else
			sink.put(msg);
	}

	/// Outputs a message to stderr, prefixed with file/line information
	void writeCustomMsg(string msg)
	{
		stderr.writeln( customMsg(msg) );
	}
}

/// Thrown by the DOM on empty range and out-of-range conditions.
class DOMRangeException : DOMException
{
	this(Tag base, string msg, string file = __FILE__, size_t line = __LINE__)
	{
		super(base, msg, file, line);
	}
}

/// Compatibility alias
deprecated("The new name is DOMRangeException")
alias SDLangRangeException = DOMRangeException;

/// Abstract parent class of `TagNotFoundException`, `ValueNotFoundException`
/// and `AttributeNotFoundException`.
///
/// Thrown by the DOM's `sdlang.ast.Tag.expectTag`, etc. functions if a matching element isn't found.
abstract class DOMNotFoundException : DOMException
{
	FullName tagName; /// The tag searched for

	this(Tag base, FullName tagName, string msg, string file = __FILE__, size_t line = __LINE__)
	{
		this.tagName = tagName;
		super(base, msg, file, line);
	}
}

/// Thrown by the DOM's `sdlang.ast.Tag.expectTag`, etc. functions if a Tag isn't found.
class TagNotFoundException : DOMNotFoundException
{
	this(Tag base, FullName tagName, string msg, string file = __FILE__, size_t line = __LINE__)
	{
		super(base, tagName, msg, file, line);
	}
}

/// Thrown by the DOM's `sdlang.ast.Tag.expectValue`, etc. functions if a Value isn't found.
class ValueNotFoundException : DOMNotFoundException
{
	/// Expected type for the not-found value.
	TypeInfo valueType;

	this(Tag base, FullName tagName, TypeInfo valueType, string msg, string file = __FILE__, size_t line = __LINE__)
	{
		this.valueType = valueType;
		super(base, tagName, msg, file, line);
	}
}

/// Thrown by the DOM's `sdlang.ast.Tag.expectAttribute`, etc. functions if an Attribute isn't found.
class AttributeNotFoundException : DOMNotFoundException
{
	FullName attributeName; /// The attribute searched for

	/// Expected type for the not-found attribute's value.
	TypeInfo valueType;

	this(Tag base, FullName tagName, FullName attributeName, TypeInfo valueType, string msg,
		string file = __FILE__, size_t line = __LINE__)
	{
		this.valueType = valueType;
		this.attributeName = attributeName;
		super(base, tagName, msg, file, line);
	}
}
