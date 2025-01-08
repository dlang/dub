
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * Class that processes YAML mappings, sequences and scalars into nodes.
 * This can be used to add custom data types. A tutorial can be found
 * $(LINK2 https://dlang-community.github.io/D-YAML/, here).
 */
module dub.internal.dyaml.constructor;


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

import dub.internal.dyaml.node;
import dub.internal.dyaml.exception;
import dub.internal.dyaml.style;

package:

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
    noreturn error(string a, string b)()
    {
        enum msg = "Error constructing " ~ T.stringof ~ ": Only " ~ a ~ " can be " ~ b;
        throw new ConstructorException(msg, start, "end", end);
    }
    switch(tag)
    {
        case "tag:yaml.org,2002:null":
            newNode = Node(YAMLNull(), tag);
            break;
        case "tag:yaml.org,2002:bool":
            static if(is(T == string))
            {
                newNode = Node(constructBool(value, start, end), tag);
                break;
            }
            else error!("scalars", "bools");
        case "tag:yaml.org,2002:int":
            static if(is(T == string))
            {
                newNode = Node(constructLong(value, start, end), tag);
                break;
            }
            else error!("scalars", "ints");
        case "tag:yaml.org,2002:float":
            static if(is(T == string))
            {
                newNode = Node(constructReal(value, start, end), tag);
                break;
            }
            else error!("scalars", "floats");
        case "tag:yaml.org,2002:binary":
            static if(is(T == string))
            {
                newNode = Node(constructBinary(value, start, end), tag);
                break;
            }
            else error!("scalars", "binary data");
        case "tag:yaml.org,2002:timestamp":
            static if(is(T == string))
            {
                newNode = Node(constructTimestamp(value, start, end), tag);
                break;
            }
            else error!("scalars", "timestamps");
        case "tag:yaml.org,2002:str":
            static if(is(T == string))
            {
                newNode = Node(constructString(value, start, end), tag);
                break;
            }
            else error!("scalars", "strings");
        case "tag:yaml.org,2002:value":
            static if(is(T == string))
            {
                newNode = Node(constructString(value, start, end), tag);
                break;
            }
            else error!("scalars", "values");
        case "tag:yaml.org,2002:omap":
            static if(is(T == Node[]))
            {
                newNode = Node(constructOrderedMap(value, start, end), tag);
                break;
            }
            else error!("sequences", "ordered maps");
        case "tag:yaml.org,2002:pairs":
            static if(is(T == Node[]))
            {
                newNode = Node(constructPairs(value, start, end), tag);
                break;
            }
            else error!("sequences", "pairs");
        case "tag:yaml.org,2002:set":
            static if(is(T == Node.Pair[]))
            {
                newNode = Node(constructSet(value, start, end), tag);
                break;
            }
            else error!("mappings", "sets");
        case "tag:yaml.org,2002:seq":
            static if(is(T == Node[]))
            {
                newNode = Node(constructSequence(value, start, end), tag);
                break;
            }
            else error!("sequences", "sequences");
        case "tag:yaml.org,2002:map":
            static if(is(T == Node.Pair[]))
            {
                newNode = Node(constructMap(value, start, end), tag);
                break;
            }
            else error!("mappings", "maps");
        case "tag:yaml.org,2002:merge":
            newNode = Node(YAMLMerge(), tag);
            break;
        default:
            newNode = Node(value, tag);
            break;
    }

    newNode.startMark_ = start;

    return newNode;
}

private:
// Construct a boolean _node.
bool constructBool(const string str, const Mark start, const Mark end) @safe
{
    string value = str.toLower();
    if(value.among!("yes", "true", "on")){return true;}
    if(value.among!("no", "false", "off")){return false;}
    throw new ConstructorException("Invalid boolean value: " ~ str, start, "ending at", end);
}

@safe unittest
{
    assert(collectException!ConstructorException(constructBool("foo", Mark("unittest", 1, 0), Mark("unittest", 1, 3))).msg == "Invalid boolean value: foo");
}

// Construct an integer (long) _node.
long constructLong(const string str, const Mark start, const Mark end) @safe
{
    string value = str.replace("_", "");
    const char c = value[0];
    const long sign = c != '-' ? 1 : -1;
    if(c == '-' || c == '+')
    {
        value = value[1 .. $];
    }

    enforce(value != "", new ConstructorException("Unable to parse integer value: " ~ str, start, "ending at", end));

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
        throw new ConstructorException("Unable to parse integer value: " ~ str, start, "ending at", end);
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

    assert(685230 == constructLong(canonical, Mark.init, Mark.init));
    assert(685230 == constructLong(decimal, Mark.init, Mark.init));
    assert(685230 == constructLong(octal, Mark.init, Mark.init));
    assert(685230 == constructLong(hexadecimal, Mark.init, Mark.init));
    assert(685230 == constructLong(binary, Mark.init, Mark.init));
    assert(685230 == constructLong(sexagesimal, Mark.init, Mark.init));
    assert(collectException!ConstructorException(constructLong("+", Mark.init, Mark.init)).msg == "Unable to parse integer value: +");
    assert(collectException!ConstructorException(constructLong("0xINVALID", Mark.init, Mark.init)).msg == "Unable to parse integer value: 0xINVALID");
}

// Construct a floating point (real) _node.
real constructReal(const string str, const Mark start, const Mark end) @safe
{
    string value = str.replace("_", "").toLower();
    const char c = value[0];
    const real sign = c != '-' ? 1.0 : -1.0;
    if(c == '-' || c == '+')
    {
        value = value[1 .. $];
    }

    enforce(value != "" && value != "nan" && value != "inf" && value != "-inf",
            new ConstructorException("Unable to parse float value: \"" ~ str ~ "\"", start, "ending at", end));

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
        throw new ConstructorException("Unable to parse float value: \"" ~ str ~ "\"", start, "ending at", end);
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

    assert(eq(685230.15, constructReal(canonical, Mark.init, Mark.init)));
    assert(eq(685230.15, constructReal(exponential, Mark.init, Mark.init)));
    assert(eq(685230.15, constructReal(fixed, Mark.init, Mark.init)));
    assert(eq(685230.15, constructReal(sexagesimal, Mark.init, Mark.init)));
    assert(eq(-real.infinity, constructReal(negativeInf, Mark.init, Mark.init)));
    assert(to!string(constructReal(NaN, Mark.init, Mark.init)) == "nan");
    assert(collectException!ConstructorException(constructReal("+", Mark.init, Mark.init)).msg == "Unable to parse float value: \"+\"");
    assert(collectException!ConstructorException(constructReal("74.invalid", Mark.init, Mark.init)).msg == "Unable to parse float value: \"74.invalid\"");
}

// Construct a binary (base64) _node.
ubyte[] constructBinary(const string value, const Mark start, const Mark end) @safe
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
        throw new ConstructorException("Unable to decode base64 value: " ~ e.msg, start, "ending at", end);
    }
}

@safe unittest
{
    auto test = "The Answer: 42".representation;
    char[] buffer;
    buffer.length = 256;
    string input = Base64.encode(test, buffer).idup;
    const value = constructBinary(input, Mark.init, Mark.init);
    assert(value == test);
    assert(value == [84, 104, 101, 32, 65, 110, 115, 119, 101, 114, 58, 32, 52, 50]);
}

// Construct a timestamp (SysTime) _node.
SysTime constructTimestamp(const string str, const Mark start, const Mark end) @safe
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
        return constructTimestamp(value, Mark.init, Mark.init).toISOString();
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
string constructString(const string str, const Mark start, const Mark end) @safe
{
    return str;
}

// Convert a sequence of single-element mappings into a sequence of pairs.
Node.Pair[] getPairs(string type)(const Node[] nodes) @safe
{
    enum msg = "While constructing " ~ type ~ ", expected a mapping with single element";
    Node.Pair[] pairs;
    pairs.reserve(nodes.length);
    foreach(node; nodes)
    {
        enforce(node.nodeID == NodeID.mapping && node.length == 1,
                new ConstructorException(msg, node.startMark));

        pairs ~= node.as!(Node.Pair[]);
    }

    return pairs;
}

// Construct an ordered map (ordered sequence of key:value pairs without duplicates) _node.
Node.Pair[] constructOrderedMap(const Node[] nodes, const Mark start, const Mark end) @safe
{
    auto pairs = getPairs!"an ordered map"(nodes);

    //Detect duplicates.
    //TODO this should be replaced by something with deterministic memory allocation.
    auto keys = new RedBlackTree!Node();
    foreach(ref pair; pairs)
    {
        auto foundMatch = keys.equalRange(pair.key);
        enforce(foundMatch.empty, new ConstructorException(
            "Duplicate entry in an ordered map", pair.key.startMark,
            "first occurrence here", foundMatch.front.startMark));
        keys.insert(pair.key);
    }
    return pairs;
}
@safe unittest
{
    uint lines;
    Node[] alternateTypes(uint length) @safe
    {
        Node[] pairs;
        foreach(long i; 0 .. length)
        {
            auto pair = (i % 2) ? Node.Pair(i.to!string, i) : Node.Pair(i, i.to!string);
            pair.key.startMark_ = Mark("unittest", lines++, 0);
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
            pair.key.startMark_ = Mark("unittest", lines++, 0);
            pairs ~= Node([pair]);
        }
        return pairs;
    }

    assert(collectException!ConstructorException(constructOrderedMap(alternateTypes(8) ~ alternateTypes(2), Mark.init, Mark.init)).message == "Duplicate entry in an ordered map\nunittest:9,1\nfirst occurrence here: unittest:1,1");
    assertNotThrown(constructOrderedMap(alternateTypes(8), Mark.init, Mark.init));
    assert(collectException!ConstructorException(constructOrderedMap(sameType(64) ~ sameType(16), Mark.init, Mark.init)).message == "Duplicate entry in an ordered map\nunittest:83,1\nfirst occurrence here: unittest:19,1");
    assert(collectException!ConstructorException(constructOrderedMap(alternateTypes(64) ~ alternateTypes(16), Mark.init, Mark.init)).message == "Duplicate entry in an ordered map\nunittest:163,1\nfirst occurrence here: unittest:99,1");
    assertNotThrown(constructOrderedMap(sameType(64), Mark.init, Mark.init));
    assertNotThrown(constructOrderedMap(alternateTypes(64), Mark.init, Mark.init));
    assert(collectException!ConstructorException(constructOrderedMap([Node([Node(1), Node(2)])], Mark.init, Mark.init)).message == "While constructing an ordered map, expected a mapping with single element\n<unknown>:1,1");
}

// Construct a pairs (ordered sequence of key: value pairs allowing duplicates) _node.
Node.Pair[] constructPairs(const Node[] nodes, const Mark start, const Mark end) @safe
{
    return getPairs!"pairs"(nodes);
}

// Construct a set _node.
Node[] constructSet(const Node.Pair[] pairs, const Mark start, const Mark end) @safe
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

    assertThrown(constructSet(nodeDuplicatesShort, Mark.init, Mark.init));
    assertNotThrown(constructSet(nodeNoDuplicatesShort, Mark.init, Mark.init));
    assertThrown(constructSet(nodeDuplicatesLong, Mark.init, Mark.init));
    assertNotThrown(constructSet(nodeNoDuplicatesLong, Mark.init, Mark.init));
}

// Construct a sequence (array) _node.
Node[] constructSequence(Node[] nodes, const Mark start, const Mark end) @safe
{
    return nodes;
}

// Construct an unordered map (unordered set of key:value _pairs without duplicates) _node.
Node.Pair[] constructMap(Node.Pair[] pairs, const Mark start, const Mark end) @safe
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
