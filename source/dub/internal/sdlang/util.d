// SDLang-D
// Written in the D programming language.

module dub.internal.sdlang.util;

version (Have_sdlang_d) public import sdlang.util;
else:

import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.range;
import std.stdio;
import std.string;

import dub.internal.sdlang.exception;
import dub.internal.sdlang.token;

enum sdlangVersion = "0.9.1";

alias immutable(ubyte)[] ByteString;

auto startsWith(T)(string haystack, T needle)
	if( is(T:ByteString) || is(T:string) )
{
	return std.algorithm.startsWith( cast(ByteString)haystack, cast(ByteString)needle );
}

struct Location
{
	string file; /// Filename (including path)
	int line; /// Zero-indexed
	int col;  /// Zero-indexed, Tab counts as 1
	size_t index; /// Index into the source

	this(int line, int col, int index)
	{
		this.line  = line;
		this.col   = col;
		this.index = index;
	}

	this(string file, int line, int col, int index)
	{
		this.file  = file;
		this.line  = line;
		this.col   = col;
		this.index = index;
	}

	/// Convert to string. Optionally takes output range as a sink.
	string toString()
	{
		Appender!string sink;
		this.toString(sink);
		return sink.data;
	}

	///ditto
	void toString(Sink)(ref Sink sink) if(isOutputRange!(Sink,char))
	{
		sink.put(file);
		sink.put("(");
		sink.put(to!string(line+1));
		sink.put(":");
		sink.put(to!string(col+1));
		sink.put(")");
	}
}

struct FullName
{
	string namespace;
	string name;

	/// Convert to string. Optionally takes output range as a sink.
	string toString()
	{
		if(namespace == "")
			return name;

		Appender!string sink;
		this.toString(sink);
		return sink.data;
	}

	///ditto
	void toString(Sink)(ref Sink sink) if(isOutputRange!(Sink,char))
	{
		if(namespace != "")
		{
			sink.put(namespace);
			sink.put(":");
		}

		sink.put(name);
	}

	///
	static string combine(string namespace, string name)
	{
		return FullName(namespace, name).toString();
	}
	///
	@("FullName.combine example")
	unittest
	{
		assert(FullName.combine("", "name") == "name");
		assert(FullName.combine("*", "name") == "*:name");
		assert(FullName.combine("namespace", "name") == "namespace:name");
	}

	///
	static FullName parse(string fullName)
	{
		FullName result;
		
		auto parts = fullName.findSplit(":");
		if(parts[1] == "") // No colon
		{
			result.namespace = "";
			result.name      = parts[0];
		}
		else
		{
			result.namespace = parts[0];
			result.name      = parts[2];
		}

		return result;
	}
	///
	@("FullName.parse example")
	unittest
	{
		assert(FullName.parse("name") == FullName("", "name"));
		assert(FullName.parse("*:name") == FullName("*", "name"));
		assert(FullName.parse("namespace:name") == FullName("namespace", "name"));
	}

	/// Throws with appropriate message if this.name is "*".
	/// Wildcards are only supported for namespaces, not names.
	void ensureNoWildcardName(string extaMsg = null)
	{
		if(name == "*")
			throw new ArgumentException(`Wildcards ("*") only allowed for namespaces, not names. `~extaMsg);
	}
}
struct Foo { string foo; }

void removeIndex(E)(ref E[] arr, ptrdiff_t index)
{
	arr = arr[0..index] ~ arr[index+1..$];
}

void trace(string file=__FILE__, size_t line=__LINE__, TArgs...)(TArgs args)
{
	version(sdlangTrace)
	{
		writeln(file, "(", line, "): ", args);
		stdout.flush();
	}
}

string toString(TypeInfo ti)
{
	if     (ti == typeid( bool         )) return "bool";
	else if(ti == typeid( string       )) return "string";
	else if(ti == typeid( dchar        )) return "dchar";
	else if(ti == typeid( int          )) return "int";
	else if(ti == typeid( long         )) return "long";
	else if(ti == typeid( float        )) return "float";
	else if(ti == typeid( double       )) return "double";
	else if(ti == typeid( real         )) return "real";
	else if(ti == typeid( Date         )) return "Date";
	else if(ti == typeid( DateTimeFrac )) return "DateTimeFrac";
	else if(ti == typeid( DateTimeFracUnknownZone )) return "DateTimeFracUnknownZone";
	else if(ti == typeid( SysTime      )) return "SysTime";
	else if(ti == typeid( Duration     )) return "Duration";
	else if(ti == typeid( ubyte[]      )) return "ubyte[]";
	else if(ti == typeid( typeof(null) )) return "null";

	return "{unknown}";
}

enum BOM {
	UTF8,           /// UTF-8
	UTF16LE,        /// UTF-16 (little-endian)
	UTF16BE,        /// UTF-16 (big-endian)
	UTF32LE,        /// UTF-32 (little-endian)
	UTF32BE,        /// UTF-32 (big-endian)
}

enum NBOM = __traits(allMembers, BOM).length;
immutable ubyte[][NBOM] ByteOrderMarks =
[
	[0xEF, 0xBB, 0xBF],         //UTF8
	[0xFF, 0xFE],               //UTF16LE
	[0xFE, 0xFF],               //UTF16BE
	[0xFF, 0xFE, 0x00, 0x00],   //UTF32LE
	[0x00, 0x00, 0xFE, 0xFF]    //UTF32BE
];
