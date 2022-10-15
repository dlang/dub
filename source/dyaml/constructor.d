
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * Class that processes YAML mappings, sequences and scalars into nodes.
 * This can be used to add custom data types. A tutorial can be found
 * $(LINK2 https://dlang-community.github.io/D-YAML/, here).
 */
module dyaml.constructor;


import std.array;
import std.algorithm;
import std.base64;
import std.container;
import std.conv;
import std.datetime;
import std.exception;
import std.regex;
import std.string;
import std.typecons;
import std.utf;

import dyaml.node;
import dyaml.exception;
import dyaml.style;

package:

// Exception thrown at constructor errors.
class ConstructorException : YAMLException
{
    /// Construct a ConstructorException.
    ///
    /// Params:  msg   = Error message.
    ///          start = Start position of the error context.
    ///          end   = End position of the error context.
    this(string msg, Mark start, Mark end, string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow
    {
        super(msg ~ "\nstart: " ~ start.toString() ~ "\nend: " ~ end.toString(),
              file, line);
    }
}

/** Constructs YAML values.
 *
 * Each YAML scalar, sequence or mapping has a tag specifying its data type.
 * Constructor uses user-specifyable functions to create a node of desired
 * data type from a scalar, sequence or mapping.
 *
 *
 * Each of these functions is associated with a tag, and can process either
 * a scalar, a sequence, or a mapping. The constructor passes each value to
 * the function with corresponding tag, which then returns the resulting value
 * that can be stored in a node.
 *
 * If a tag is detected with no known constructor function, it is considered an error.
 */
/*
 * Construct a node.
 *
 * Params:  start = Start position of the node.
 *          end   = End position of the node.
 *          tag   = Tag (data type) of the node.
 *          value = Value to construct node from (string, nodes or pairs).
 *          style = Style of the node (scalar or collection style).
 *
 * Returns: Constructed node.
 */
Node constructNode(T)(const Mark start, const Mark end, const string tag,
                T value) @safe
    if((is(T : string) || is(T == Node[]) || is(T == Node.Pair[])))
{
    Node newNode;
    try
    {
        switch(tag)
        {
            case "tag:yaml.org,2002:null":
                newNode = Node(YAMLNull(), tag);
                break;
            case "tag:yaml.org,2002:bool":
                static if(is(T == string))
                {
                    newNode = Node(constructBool(value), tag);
                    break;
                }
                else throw new Exception("Only scalars can be bools");
            case "tag:yaml.org,2002:int":
                static if(is(T == string))
                {
                    newNode = Node(constructLong(value), tag);
                    break;
                }
                else throw new Exception("Only scalars can be ints");
            case "tag:yaml.org,2002:float":
                static if(is(T == string))
                {
                    newNode = Node(constructReal(value), tag);
                    break;
                }
                else throw new Exception("Only scalars can be floats");
            case "tag:yaml.org,2002:binary":
                static if(is(T == string))
                {
                    newNode = Node(constructBinary(value), tag);
                    break;
                }
                else throw new Exception("Only scalars can be binary data");
            case "tag:yaml.org,2002:timestamp":
                static if(is(T == string))
                {
                    newNode = Node(constructTimestamp(value), tag);
                    break;
                }
                else throw new Exception("Only scalars can be timestamps");
            case "tag:yaml.org,2002:str":
                static if(is(T == string))
                {
                    newNode = Node(constructString(value), tag);
                    break;
                }
                else throw new Exception("Only scalars can be strings");
            case "tag:yaml.org,2002:value":
                static if(is(T == string))
                {
                    newNode = Node(constructString(value), tag);
                    break;
                }
                else throw new Exception("Only scalars can be values");
            case "tag:yaml.org,2002:omap":
                static if(is(T == Node[]))
                {
                    newNode = Node(constructOrderedMap(value), tag);
                    break;
                }
                else throw new Exception("Only sequences can be ordered maps");
            case "tag:yaml.org,2002:pairs":
                static if(is(T == Node[]))
                {
                    newNode = Node(constructPairs(value), tag);
                    break;
                }
                else throw new Exception("Only sequences can be pairs");
            case "tag:yaml.org,2002:set":
                static if(is(T == Node.Pair[]))
                {
                    newNode = Node(constructSet(value), tag);
                    break;
                }
                else throw new Exception("Only mappings can be sets");
            case "tag:yaml.org,2002:seq":
                static if(is(T == Node[]))
                {
                    newNode = Node(constructSequence(value), tag);
                    break;
                }
                else throw new Exception("Only sequences can be sequences");
            case "tag:yaml.org,2002:map":
                static if(is(T == Node.Pair[]))
                {
                    newNode = Node(constructMap(value), tag);
                    break;
                }
                else throw new Exception("Only mappings can be maps");
            case "tag:yaml.org,2002:merge":
                newNode = Node(YAMLMerge(), tag);
                break;
            default:
                newNode = Node(value, tag);
                break;
        }
    }
    catch(Exception e)
    {
        throw new ConstructorException("Error constructing " ~ typeid(T).toString()
                        ~ ":\n" ~ e.msg, start, end);
    }

    newNode.startMark_ = start;

    return newNode;
}

private:
// Construct a boolean _node.
bool constructBool(const string str) @safe
{
    string value = str.toLower();
    if(value.among!("yes", "true", "on")){return true;}
    if(value.among!("no", "false", "off")){return false;}
    throw new Exception("Unable to parse boolean value: " ~ value);
}

// Construct an integer (long) _node.
long constructLong(const string str) @safe
{
    string value = str.replace("_", "");
    const char c = value[0];
    const long sign = c != '-' ? 1 : -1;
    if(c == '-' || c == '+')
    {
        value = value[1 .. $];
    }

    enforce(value != "", new Exception("Unable to parse float value: " ~ value));

    long result;
    try
    {
        //Zero.
        if(value == "0")               {result = cast(long)0;}
        //Binary.
        else if(value.startsWith("0b")){result = sign * to!int(value[2 .. $], 2);}
        //Hexadecimal.
        else if(value.startsWith("0x")){result = sign * to!int(value[2 .. $], 16);}
        //Octal.
        else if(value[0] == '0')       {result = sign * to!int(value, 8);}
        //Sexagesimal.
        else if(value.canFind(":"))
        {
            long val;
            long base = 1;
            foreach_reverse(digit; value.split(":"))
            {
                val += to!long(digit) * base;
                base *= 60;
            }
            result = sign * val;
        }
        //Decimal.
        else{result = sign * to!long(value);}
    }
    catch(ConvException e)
    {
        throw new Exception("Unable to parse integer value: " ~ value);
    }

    return result;
}
@safe unittest
{
    string canonical   = "685230";
    string decimal     = "+685_230";
    string octal       = "02472256";
    string hexadecimal = "0x_0A_74_AE";
    string binary      = "0b1010_0111_0100_1010_1110";
    string sexagesimal = "190:20:30";

    assert(685230 == constructLong(canonical));
    assert(685230 == constructLong(decimal));
    assert(685230 == constructLong(octal));
    assert(685230 == constructLong(hexadecimal));
    assert(685230 == constructLong(binary));
    assert(685230 == constructLong(sexagesimal));
}

// Construct a floating point (real) _node.
real constructReal(const string str) @safe
{
    string value = str.replace("_", "").toLower();
    const char c = value[0];
    const real sign = c != '-' ? 1.0 : -1.0;
    if(c == '-' || c == '+')
    {
        value = value[1 .. $];
    }

    enforce(value != "" && value != "nan" && value != "inf" && value != "-inf",
            new Exception("Unable to parse float value: " ~ value));

    real result;
    try
    {
        //Infinity.
        if     (value == ".inf"){result = sign * real.infinity;}
        //Not a Number.
        else if(value == ".nan"){result = real.nan;}
        //Sexagesimal.
        else if(value.canFind(":"))
        {
            real val = 0.0;
            real base = 1.0;
            foreach_reverse(digit; value.split(":"))
            {
                val += to!real(digit) * base;
                base *= 60.0;
            }
            result = sign * val;
        }
        //Plain floating point.
        else{result = sign * to!real(value);}
    }
    catch(ConvException e)
    {
        throw new Exception("Unable to parse float value: \"" ~ value ~ "\"");
    }

    return result;
}
@safe unittest
{
    bool eq(real a, real b, real epsilon = 0.2) @safe
    {
        return a >= (b - epsilon) && a <= (b + epsilon);
    }

    string canonical   = "6.8523015e+5";
    string exponential = "685.230_15e+03";
    string fixed       = "685_230.15";
    string sexagesimal = "190:20:30.15";
    string negativeInf = "-.inf";
    string NaN         = ".NaN";

    assert(eq(685230.15, constructReal(canonical)));
    assert(eq(685230.15, constructReal(exponential)));
    assert(eq(685230.15, constructReal(fixed)));
    assert(eq(685230.15, constructReal(sexagesimal)));
    assert(eq(-real.infinity, constructReal(negativeInf)));
    assert(to!string(constructReal(NaN)) == "nan");
}

// Construct a binary (base64) _node.
ubyte[] constructBinary(const string value) @safe
{
    import std.ascii : newline;
    import std.array : array;

    // For an unknown reason, this must be nested to work (compiler bug?).
    try
    {
        return Base64.decode(value.representation.filter!(c => !newline.canFind(c)).array);
    }
    catch(Base64Exception e)
    {
        throw new Exception("Unable to decode base64 value: " ~ e.msg);
    }
}

@safe unittest
{
    auto test = "The Answer: 42".representation;
    char[] buffer;
    buffer.length = 256;
    string input = Base64.encode(test, buffer).idup;
    const value = constructBinary(input);
    assert(value == test);
    assert(value == [84, 104, 101, 32, 65, 110, 115, 119, 101, 114, 58, 32, 52, 50]);
}

// Construct a timestamp (SysTime) _node.
SysTime constructTimestamp(const string str) @safe
{
    string value = str;

    auto YMDRegexp = regex("^([0-9][0-9][0-9][0-9])-([0-9][0-9]?)-([0-9][0-9]?)");
    auto HMSRegexp = regex("^[Tt \t]+([0-9][0-9]?):([0-9][0-9]):([0-9][0-9])(\\.[0-9]*)?");
    auto TZRegexp  = regex("^[ \t]*Z|([-+][0-9][0-9]?)(:[0-9][0-9])?");

    try
    {
        // First, get year, month and day.
        auto matches = match(value, YMDRegexp);

        enforce(!matches.empty,
                new Exception("Unable to parse timestamp value: " ~ value));

        auto captures = matches.front.captures;
        const year  = to!int(captures[1]);
        const month = to!int(captures[2]);
        const day   = to!int(captures[3]);

        // If available, get hour, minute, second and fraction, if present.
        value = matches.front.post;
        matches  = match(value, HMSRegexp);
        if(matches.empty)
        {
            return SysTime(DateTime(year, month, day), UTC());
        }

        captures = matches.front.captures;
        const hour            = to!int(captures[1]);
        const minute          = to!int(captures[2]);
        const second          = to!int(captures[3]);
        const hectonanosecond = cast(int)(to!real("0" ~ captures[4]) * 10_000_000);

        // If available, get timezone.
        value = matches.front.post;
        matches = match(value, TZRegexp);
        if(matches.empty || matches.front.captures[0] == "Z")
        {
            // No timezone.
            return SysTime(DateTime(year, month, day, hour, minute, second),
                           hectonanosecond.dur!"hnsecs", UTC());
        }

        // We have a timezone, so parse it.
        captures = matches.front.captures;
        int sign    = 1;
        int tzHours;
        if(!captures[1].empty)
        {
            if(captures[1][0] == '-') {sign = -1;}
            tzHours   = to!int(captures[1][1 .. $]);
        }
        const tzMinutes = (!captures[2].empty) ? to!int(captures[2][1 .. $]) : 0;
        const tzOffset  = dur!"minutes"(sign * (60 * tzHours + tzMinutes));

        return SysTime(DateTime(year, month, day, hour, minute, second),
                       hectonanosecond.dur!"hnsecs",
                       new immutable SimpleTimeZone(tzOffset));
    }
    catch(ConvException e)
    {
        throw new Exception("Unable to parse timestamp value " ~ value ~ " : " ~ e.msg);
    }
    catch(DateTimeException e)
    {
        throw new Exception("Invalid timestamp value " ~ value ~ " : " ~ e.msg);
    }

    assert(false, "This code should never be reached");
}
@safe unittest
{
    string timestamp(string value)
    {
        return constructTimestamp(value).toISOString();
    }

    string canonical      = "2001-12-15T02:59:43.1Z";
    string iso8601        = "2001-12-14t21:59:43.10-05:00";
    string spaceSeparated = "2001-12-14 21:59:43.10 -5";
    string noTZ           = "2001-12-15 2:59:43.10";
    string noFraction     = "2001-12-15 2:59:43";
    string ymd            = "2002-12-14";

    assert(timestamp(canonical)      == "20011215T025943.1Z");
    //avoiding float conversion errors
    assert(timestamp(iso8601)        == "20011214T215943.0999999-05:00" ||
           timestamp(iso8601)        == "20011214T215943.1-05:00");
    assert(timestamp(spaceSeparated) == "20011214T215943.0999999-05:00" ||
           timestamp(spaceSeparated) == "20011214T215943.1-05:00");
    assert(timestamp(noTZ)           == "20011215T025943.0999999Z" ||
           timestamp(noTZ)           == "20011215T025943.1Z");
    assert(timestamp(noFraction)     == "20011215T025943Z");
    assert(timestamp(ymd)            == "20021214T000000Z");
}

// Construct a string _node.
string constructString(const string str) @safe
{
    return str;
}

// Convert a sequence of single-element mappings into a sequence of pairs.
Node.Pair[] getPairs(string type, const Node[] nodes) @safe
{
    Node.Pair[] pairs;
    pairs.reserve(nodes.length);
    foreach(node; nodes)
    {
        enforce(node.nodeID == NodeID.mapping && node.length == 1,
                new Exception("While constructing " ~ type ~
                              ", expected a mapping with single element"));

        pairs ~= node.as!(Node.Pair[]);
    }

    return pairs;
}

// Construct an ordered map (ordered sequence of key:value pairs without duplicates) _node.
Node.Pair[] constructOrderedMap(const Node[] nodes) @safe
{
    auto pairs = getPairs("ordered map", nodes);

    //Detect duplicates.
    //TODO this should be replaced by something with deterministic memory allocation.
    auto keys = new RedBlackTree!Node();
    foreach(ref pair; pairs)
    {
        enforce(!(pair.key in keys),
                new Exception("Duplicate entry in an ordered map: "
                              ~ pair.key.debugString()));
        keys.insert(pair.key);
    }
    return pairs;
}
@safe unittest
{
    Node[] alternateTypes(uint length) @safe
    {
        Node[] pairs;
        foreach(long i; 0 .. length)
        {
            auto pair = (i % 2) ? Node.Pair(i.to!string, i) : Node.Pair(i, i.to!string);
            pairs ~= Node([pair]);
        }
        return pairs;
    }

    Node[] sameType(uint length) @safe
    {
        Node[] pairs;
        foreach(long i; 0 .. length)
        {
            auto pair = Node.Pair(i.to!string, i);
            pairs ~= Node([pair]);
        }
        return pairs;
    }

    assertThrown(constructOrderedMap(alternateTypes(8) ~ alternateTypes(2)));
    assertNotThrown(constructOrderedMap(alternateTypes(8)));
    assertThrown(constructOrderedMap(sameType(64) ~ sameType(16)));
    assertThrown(constructOrderedMap(alternateTypes(64) ~ alternateTypes(16)));
    assertNotThrown(constructOrderedMap(sameType(64)));
    assertNotThrown(constructOrderedMap(alternateTypes(64)));
}

// Construct a pairs (ordered sequence of key: value pairs allowing duplicates) _node.
Node.Pair[] constructPairs(const Node[] nodes) @safe
{
    return getPairs("pairs", nodes);
}

// Construct a set _node.
Node[] constructSet(const Node.Pair[] pairs) @safe
{
    // In future, the map here should be replaced with something with deterministic
    // memory allocation if possible.
    // Detect duplicates.
    ubyte[Node] map;
    Node[] nodes;
    nodes.reserve(pairs.length);
    foreach(pair; pairs)
    {
        enforce((pair.key in map) is null, new Exception("Duplicate entry in a set"));
        map[pair.key] = 0;
        nodes ~= pair.key;
    }

    return nodes;
}
@safe unittest
{
    Node.Pair[] set(uint length) @safe
    {
        Node.Pair[] pairs;
        foreach(long i; 0 .. length)
        {
            pairs ~= Node.Pair(i.to!string, YAMLNull());
        }

        return pairs;
    }

    auto DuplicatesShort   = set(8) ~ set(2);
    auto noDuplicatesShort = set(8);
    auto DuplicatesLong    = set(64) ~ set(4);
    auto noDuplicatesLong  = set(64);

    bool eq(Node.Pair[] a, Node[] b)
    {
        if(a.length != b.length){return false;}
        foreach(i; 0 .. a.length)
        {
            if(a[i].key != b[i])
            {
                return false;
            }
        }
        return true;
    }

    auto nodeDuplicatesShort   = DuplicatesShort.dup;
    auto nodeNoDuplicatesShort = noDuplicatesShort.dup;
    auto nodeDuplicatesLong    = DuplicatesLong.dup;
    auto nodeNoDuplicatesLong  = noDuplicatesLong.dup;

    assertThrown(constructSet(nodeDuplicatesShort));
    assertNotThrown(constructSet(nodeNoDuplicatesShort));
    assertThrown(constructSet(nodeDuplicatesLong));
    assertNotThrown(constructSet(nodeNoDuplicatesLong));
}

// Construct a sequence (array) _node.
Node[] constructSequence(Node[] nodes) @safe
{
    return nodes;
}

// Construct an unordered map (unordered set of key:value _pairs without duplicates) _node.
Node.Pair[] constructMap(Node.Pair[] pairs) @safe
{
    //Detect duplicates.
    //TODO this should be replaced by something with deterministic memory allocation.
    auto keys = new RedBlackTree!Node();
    foreach(ref pair; pairs)
    {
        enforce(!(pair.key in keys),
                new Exception("Duplicate entry in a map: " ~ pair.key.debugString()));
        keys.insert(pair.key);
    }
    return pairs;
}
