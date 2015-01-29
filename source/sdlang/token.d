// SDLang-D
// Written in the D programming language.

module sdlang.token;

import std.array;
import std.base64;
import std.conv;
import std.datetime;
import std.range;
import std.string;
import std.typetuple;
import std.variant;

import sdlang.symbol;
import sdlang.util;

/// DateTime doesn't support milliseconds, but SDL's "Date Time" type does.
/// So this is needed for any SDL "Date Time" that doesn't include a time zone.
struct DateTimeFrac
{
	DateTime dateTime;
	FracSec fracSec;
}

/++
If a "Date Time" literal in the SDL file has a time zone that's not found in
your system, you get one of these instead of a SysTime. (Because it's
impossible to indicate "unknown time zone" with 'std.datetime.TimeZone'.)

The difference between this and 'DateTimeFrac' is that 'DateTimeFrac'
indicates that no time zone was specified in the SDL at all, whereas
'DateTimeFracUnknownZone' indicates that a time zone was specified but
data for it could not be found on your system.
+/
struct DateTimeFracUnknownZone
{
	DateTime dateTime;
	FracSec fracSec;
	string timeZone;

	bool opEquals(const DateTimeFracUnknownZone b) const
	{
		return opEquals(b);
	}
	bool opEquals(ref const DateTimeFracUnknownZone b) const
	{
		return
			this.dateTime == b.dateTime &&
			this.fracSec  == b.fracSec  &&
			this.timeZone == b.timeZone;
	}
}

/++
SDL's datatypes map to D's datatypes as described below.
Most are straightforward, but take special note of the date/time-related types.

Boolean:                       bool
Null:                          typeof(null)
Unicode Character:             dchar
Double-Quote Unicode String:   string
Raw Backtick Unicode String:   string
Integer (32 bits signed):      int
Long Integer (64 bits signed): long
Float (32 bits signed):        float
Double Float (64 bits signed): double
Decimal (128+ bits signed):    real
Binary (standard Base64):      ubyte[]
Time Span:                     Duration

Date (with no time at all):           Date
Date Time (no timezone):              DateTimeFrac
Date Time (with a known timezone):    SysTime
Date Time (with an unknown timezone): DateTimeFracUnknownZone
+/
alias TypeTuple!(
	bool,
	string, dchar,
	int, long,
	float, double, real,
	Date, DateTimeFrac, SysTime, DateTimeFracUnknownZone, Duration,
	ubyte[],
	typeof(null),
) ValueTypes;

alias Algebraic!( ValueTypes ) Value; ///ditto

template isSDLSink(T)
{
	enum isSink =
		isOutputRange!T &&
		is(ElementType!(T)[] == string);
}

string toSDLString(T)(T value) if(
	is( T : Value        ) ||
	is( T : bool         ) ||
	is( T : string       ) ||
	is( T : dchar        ) ||
	is( T : int          ) ||
	is( T : long         ) ||
	is( T : float        ) ||
	is( T : double       ) ||
	is( T : real         ) ||
	is( T : Date         ) ||
	is( T : DateTimeFrac ) ||
	is( T : SysTime      ) ||
	is( T : DateTimeFracUnknownZone ) ||
	is( T : Duration     ) ||
	is( T : ubyte[]      ) ||
	is( T : typeof(null) )
)
{
	Appender!string sink;
	toSDLString(value, sink);
	return sink.data;
}

void toSDLString(Sink)(Value value, ref Sink sink) if(isOutputRange!(Sink,char))
{
	foreach(T; ValueTypes)
	{
		if(value.type == typeid(T))
		{
			toSDLString( value.get!T(), sink );
			return;
		}
	}
	
	throw new Exception("Internal SDLang-D error: Unhandled type of Value. Contains: "~value.toString());
}

void toSDLString(Sink)(typeof(null) value, ref Sink sink) if(isOutputRange!(Sink,char))
{
	sink.put("null");
}

void toSDLString(Sink)(bool value, ref Sink sink) if(isOutputRange!(Sink,char))
{
	sink.put(value? "true" : "false");
}

//TODO: Figure out how to properly handle strings/chars containing lineSep or paraSep
void toSDLString(Sink)(string value, ref Sink sink) if(isOutputRange!(Sink,char))
{
	sink.put('"');
	
	// This loop is UTF-safe
	foreach(char ch; value)
	{
		if     (ch == '\n') sink.put(`\n`);
		else if(ch == '\r') sink.put(`\r`);
		else if(ch == '\t') sink.put(`\t`);
		else if(ch == '\"') sink.put(`\"`);
		else if(ch == '\\') sink.put(`\\`);
		else
			sink.put(ch);
	}

	sink.put('"');
}

void toSDLString(Sink)(dchar value, ref Sink sink) if(isOutputRange!(Sink,char))
{
	sink.put('\'');
	
	if     (value == '\n') sink.put(`\n`);
	else if(value == '\r') sink.put(`\r`);
	else if(value == '\t') sink.put(`\t`);
	else if(value == '\'') sink.put(`\'`);
	else if(value == '\\') sink.put(`\\`);
	else
		sink.put(value);

	sink.put('\'');
}

void toSDLString(Sink)(int value, ref Sink sink) if(isOutputRange!(Sink,char))
{
	sink.put( "%s".format(value) );
}

void toSDLString(Sink)(long value, ref Sink sink) if(isOutputRange!(Sink,char))
{
	sink.put( "%sL".format(value) );
}

void toSDLString(Sink)(float value, ref Sink sink) if(isOutputRange!(Sink,char))
{
	sink.put( "%.10sF".format(value) );
}

void toSDLString(Sink)(double value, ref Sink sink) if(isOutputRange!(Sink,char))
{
	sink.put( "%.30sD".format(value) );
}

void toSDLString(Sink)(real value, ref Sink sink) if(isOutputRange!(Sink,char))
{
	sink.put( "%.30sBD".format(value) );
}

void toSDLString(Sink)(Date value, ref Sink sink) if(isOutputRange!(Sink,char))
{
	sink.put(to!string(value.year));
	sink.put('/');
	sink.put(to!string(cast(int)value.month));
	sink.put('/');
	sink.put(to!string(value.day));
}

void toSDLString(Sink)(DateTimeFrac value, ref Sink sink) if(isOutputRange!(Sink,char))
{
	toSDLString(value.dateTime.date, sink);
	sink.put(' ');
	sink.put("%.2s".format(value.dateTime.hour));
	sink.put(':');
	sink.put("%.2s".format(value.dateTime.minute));
	
	if(value.dateTime.second != 0)
	{
		sink.put(':');
		sink.put("%.2s".format(value.dateTime.second));
	}

	if(value.fracSec.msecs != 0)
	{
		sink.put('.');
		sink.put("%.3s".format(value.fracSec.msecs));
	}
}

void toSDLString(Sink)(SysTime value, ref Sink sink) if(isOutputRange!(Sink,char))
{
	auto dateTimeFrac = DateTimeFrac(cast(DateTime)value, value.fracSec);
	toSDLString(dateTimeFrac, sink);
	
	sink.put("-");
	
	auto tzString = value.timezone.name;
	
	// If name didn't exist, try abbreviation.
	// Note that according to std.datetime docs, on Windows the
	// stdName/dstName may not be properly abbreviated.
	version(Windows) {} else
	if(tzString == "")
	{
		auto tz = value.timezone;
		auto stdTime = value.stdTime;
		
		if(tz.hasDST())
			tzString = tz.dstInEffect(stdTime)? tz.dstName : tz.stdName;
		else
			tzString = tz.stdName;
	}
	
	if(tzString == "")
	{
		auto offset = value.timezone.utcOffsetAt(value.stdTime);
		sink.put("GMT");

		if(offset < seconds(0))
		{
			sink.put("-");
			offset = -offset;
		}
		else
			sink.put("+");
		
		sink.put("%.2s".format(offset.hours));
		sink.put(":");
		sink.put("%.2s".format(offset.minutes));
	}
	else
		sink.put(tzString);
}

void toSDLString(Sink)(DateTimeFracUnknownZone value, ref Sink sink) if(isOutputRange!(Sink,char))
{
	auto dateTimeFrac = DateTimeFrac(value.dateTime, value.fracSec);
	toSDLString(dateTimeFrac, sink);
	
	sink.put("-");
	sink.put(value.timeZone);
}

void toSDLString(Sink)(Duration value, ref Sink sink) if(isOutputRange!(Sink,char))
{
	if(value < seconds(0))
	{
		sink.put("-");
		value = -value;
	}
	
	auto days = value.total!"days"();
	if(days != 0)
	{
		sink.put("%s".format(days));
		sink.put("d:");
	}

	sink.put("%.2s".format(value.hours));
	sink.put(':');
	sink.put("%.2s".format(value.minutes));
	sink.put(':');
	sink.put("%.2s".format(value.seconds));

	if(value.fracSec.msecs != 0)
	{
		sink.put('.');
		sink.put("%.3s".format(value.fracSec.msecs));
	}
}

void toSDLString(Sink)(ubyte[] value, ref Sink sink) if(isOutputRange!(Sink,char))
{
	sink.put('[');
	sink.put( Base64.encode(value) );
	sink.put(']');
}

/// This only represents terminals. Nonterminals aren't
/// constructed since the AST is directly built during parsing.
struct Token
{
	Symbol symbol = sdlang.symbol.symbol!"Error"; /// The "type" of this token
	Location location;
	Value value; /// Only valid when 'symbol' is symbol!"Value", otherwise null
	string data; /// Original text from source

	@disable this();
	this(Symbol symbol, Location location, Value value=Value(null), string data=null)
	{
		this.symbol   = symbol;
		this.location = location;
		this.value    = value;
		this.data     = data;
	}
	
	/// Tokens with differing symbols are always unequal.
	/// Tokens with differing values are always unequal.
	/// Tokens with differing Value types are always unequal.
	/// Member 'location' is always ignored for comparison.
	/// Member 'data' is ignored for comparison *EXCEPT* when the symbol is Ident.
	bool opEquals(Token b)
	{
		return opEquals(b);
	}
	bool opEquals(ref Token b) ///ditto
	{
		if(
			this.symbol     != b.symbol     ||
			this.value.type != b.value.type ||
			this.value      != b.value
		)
			return false;
		
		if(this.symbol == .symbol!"Ident")
			return this.data == b.data;
		
		return true;
	}
	
	bool matches(string symbolName)()
	{
		return this.symbol == .symbol!symbolName;
	}
}

version(sdlangUnittest)
unittest
{
	import std.stdio;
	writeln("Unittesting sdlang token...");
	stdout.flush();
	
	auto loc  = Location("", 0, 0, 0);
	auto loc2 = Location("a", 1, 1, 1);

	assert(Token(symbol!"EOL",loc) == Token(symbol!"EOL",loc ));
	assert(Token(symbol!"EOL",loc) == Token(symbol!"EOL",loc2));
	assert(Token(symbol!":",  loc) == Token(symbol!":",  loc ));
	assert(Token(symbol!"EOL",loc) != Token(symbol!":",  loc ));
	assert(Token(symbol!"EOL",loc,Value(null),"\n") == Token(symbol!"EOL",loc,Value(null),"\n"));

	assert(Token(symbol!"EOL",loc,Value(null),"\n") == Token(symbol!"EOL",loc,Value(null),";" ));
	assert(Token(symbol!"EOL",loc,Value(null),"A" ) == Token(symbol!"EOL",loc,Value(null),"B" ));
	assert(Token(symbol!":",  loc,Value(null),"A" ) == Token(symbol!":",  loc,Value(null),"BB"));
	assert(Token(symbol!"EOL",loc,Value(null),"A" ) != Token(symbol!":",  loc,Value(null),"A" ));

	assert(Token(symbol!"Ident",loc,Value(null),"foo") == Token(symbol!"Ident",loc,Value(null),"foo"));
	assert(Token(symbol!"Ident",loc,Value(null),"foo") != Token(symbol!"Ident",loc,Value(null),"BAR"));

	assert(Token(symbol!"Value",loc,Value(null),"foo") == Token(symbol!"Value",loc, Value(null),"foo"));
	assert(Token(symbol!"Value",loc,Value(null),"foo") == Token(symbol!"Value",loc2,Value(null),"foo"));
	assert(Token(symbol!"Value",loc,Value(null),"foo") == Token(symbol!"Value",loc, Value(null),"BAR"));
	assert(Token(symbol!"Value",loc,Value(   7),"foo") == Token(symbol!"Value",loc, Value(   7),"BAR"));
	assert(Token(symbol!"Value",loc,Value(   7),"foo") != Token(symbol!"Value",loc, Value( "A"),"foo"));
	assert(Token(symbol!"Value",loc,Value(   7),"foo") != Token(symbol!"Value",loc, Value(   2),"foo"));
	assert(Token(symbol!"Value",loc,Value(cast(int)7)) != Token(symbol!"Value",loc, Value(cast(long)7)));
	assert(Token(symbol!"Value",loc,Value(cast(float)1.2)) != Token(symbol!"Value",loc, Value(cast(double)1.2)));
}

version(sdlangUnittest)
unittest
{
	import std.stdio;
	writeln("Unittesting sdlang Value.toSDLString()...");
	stdout.flush();
	
	// Bool and null
	assert(Value(null ).toSDLString() == "null");
	assert(Value(true ).toSDLString() == "true");
	assert(Value(false).toSDLString() == "false");
	
	// Base64 Binary
	assert(Value(cast(ubyte[])"hello world".dup).toSDLString() == "[aGVsbG8gd29ybGQ=]");

	// Integer
	assert(Value(cast( int) 7).toSDLString() ==  "7");
	assert(Value(cast( int)-7).toSDLString() == "-7");
	assert(Value(cast( int) 0).toSDLString() ==  "0");

	assert(Value(cast(long) 7).toSDLString() ==  "7L");
	assert(Value(cast(long)-7).toSDLString() == "-7L");
	assert(Value(cast(long) 0).toSDLString() ==  "0L");

	// Floating point
	assert(Value(cast(float) 1.5).toSDLString() ==  "1.5F");
	assert(Value(cast(float)-1.5).toSDLString() == "-1.5F");
	assert(Value(cast(float)   0).toSDLString() ==    "0F");

	assert(Value(cast(double) 1.5).toSDLString() ==  "1.5D");
	assert(Value(cast(double)-1.5).toSDLString() == "-1.5D");
	assert(Value(cast(double)   0).toSDLString() ==    "0D");

	assert(Value(cast(real) 1.5).toSDLString() ==  "1.5BD");
	assert(Value(cast(real)-1.5).toSDLString() == "-1.5BD");
	assert(Value(cast(real)   0).toSDLString() ==    "0BD");

	// String
	assert(Value("hello"  ).toSDLString() == `"hello"`);
	assert(Value(" hello ").toSDLString() == `" hello "`);
	assert(Value(""       ).toSDLString() == `""`);
	assert(Value("hello \r\n\t\"\\ world").toSDLString() == `"hello \r\n\t\"\\ world"`);
	assert(Value("日本語").toSDLString() == `"日本語"`);

	// Chars
	assert(Value(cast(dchar) 'A').toSDLString() ==  `'A'`);
	assert(Value(cast(dchar)'\r').toSDLString() == `'\r'`);
	assert(Value(cast(dchar)'\n').toSDLString() == `'\n'`);
	assert(Value(cast(dchar)'\t').toSDLString() == `'\t'`);
	assert(Value(cast(dchar)'\'').toSDLString() == `'\''`);
	assert(Value(cast(dchar)'\\').toSDLString() == `'\\'`);
	assert(Value(cast(dchar) '月').toSDLString() ==  `'月'`);

	// Date
	assert(Value(Date( 2004,10,31)).toSDLString() == "2004/10/31");
	assert(Value(Date(-2004,10,31)).toSDLString() == "-2004/10/31");

	// DateTimeFrac w/o Frac
	assert(Value(DateTimeFrac(DateTime(2004,10,31,  14,30,15))).toSDLString() == "2004/10/31 14:30:15");
	assert(Value(DateTimeFrac(DateTime(2004,10,31,   1, 2, 3))).toSDLString() == "2004/10/31 01:02:03");
	assert(Value(DateTimeFrac(DateTime(-2004,10,31, 14,30,15))).toSDLString() == "-2004/10/31 14:30:15");

	// DateTimeFrac w/ Frac
	assert(Value(DateTimeFrac(DateTime(2004,10,31,  14,30,15), FracSec.from!"msecs"(123))).toSDLString() == "2004/10/31 14:30:15.123");
	assert(Value(DateTimeFrac(DateTime(2004,10,31,  14,30,15), FracSec.from!"msecs"(120))).toSDLString() == "2004/10/31 14:30:15.120");
	assert(Value(DateTimeFrac(DateTime(2004,10,31,  14,30,15), FracSec.from!"msecs"(100))).toSDLString() == "2004/10/31 14:30:15.100");
	assert(Value(DateTimeFrac(DateTime(2004,10,31,  14,30,15), FracSec.from!"msecs"( 12))).toSDLString() == "2004/10/31 14:30:15.012");
	assert(Value(DateTimeFrac(DateTime(2004,10,31,  14,30,15), FracSec.from!"msecs"(  1))).toSDLString() == "2004/10/31 14:30:15.001");
	assert(Value(DateTimeFrac(DateTime(-2004,10,31, 14,30,15), FracSec.from!"msecs"(123))).toSDLString() == "-2004/10/31 14:30:15.123");

	// DateTimeFracUnknownZone
	assert(Value(DateTimeFracUnknownZone(DateTime(2004,10,31, 14,30,15), FracSec.from!"msecs"(123), "Foo/Bar")).toSDLString() == "2004/10/31 14:30:15.123-Foo/Bar");

	// SysTime
	assert(Value(SysTime(DateTime(2004,10,31, 14,30,15), new immutable SimpleTimeZone( hours(0)             ))).toSDLString() == "2004/10/31 14:30:15-GMT+00:00");
	assert(Value(SysTime(DateTime(2004,10,31,  1, 2, 3), new immutable SimpleTimeZone( hours(0)             ))).toSDLString() == "2004/10/31 01:02:03-GMT+00:00");
	assert(Value(SysTime(DateTime(2004,10,31, 14,30,15), new immutable SimpleTimeZone( hours(2)+minutes(10) ))).toSDLString() == "2004/10/31 14:30:15-GMT+02:10");
	assert(Value(SysTime(DateTime(2004,10,31, 14,30,15), new immutable SimpleTimeZone(-hours(5)-minutes(30) ))).toSDLString() == "2004/10/31 14:30:15-GMT-05:30");
	assert(Value(SysTime(DateTime(2004,10,31, 14,30,15), new immutable SimpleTimeZone( hours(2)+minutes( 3) ))).toSDLString() == "2004/10/31 14:30:15-GMT+02:03");
	assert(Value(SysTime(DateTime(2004,10,31, 14,30,15), FracSec.from!"msecs"(123), new immutable SimpleTimeZone( hours(0) ))).toSDLString() == "2004/10/31 14:30:15.123-GMT+00:00");

	// Duration
	assert( "12:14:42"         == Value( days( 0)+hours(12)+minutes(14)+seconds(42)+msecs(  0)).toSDLString());
	assert("-12:14:42"         == Value(-days( 0)-hours(12)-minutes(14)-seconds(42)-msecs(  0)).toSDLString());
	assert( "00:09:12"         == Value( days( 0)+hours( 0)+minutes( 9)+seconds(12)+msecs(  0)).toSDLString());
	assert( "00:00:01.023"     == Value( days( 0)+hours( 0)+minutes( 0)+seconds( 1)+msecs( 23)).toSDLString());
	assert( "23d:05:21:23.532" == Value( days(23)+hours( 5)+minutes(21)+seconds(23)+msecs(532)).toSDLString());
	assert( "23d:05:21:23.530" == Value( days(23)+hours( 5)+minutes(21)+seconds(23)+msecs(530)).toSDLString());
	assert( "23d:05:21:23.500" == Value( days(23)+hours( 5)+minutes(21)+seconds(23)+msecs(500)).toSDLString());
	assert("-23d:05:21:23.532" == Value(-days(23)-hours( 5)-minutes(21)-seconds(23)-msecs(532)).toSDLString());
	assert("-23d:05:21:23.500" == Value(-days(23)-hours( 5)-minutes(21)-seconds(23)-msecs(500)).toSDLString());
	assert( "23d:05:21:23"     == Value( days(23)+hours( 5)+minutes(21)+seconds(23)+msecs(  0)).toSDLString());
}
