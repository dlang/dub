
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * YAML dumper.
 *
 * Code based on $(LINK2 http://www.pyyaml.org, PyYAML).
 */
module dyaml.dumper;

import std.array;
import std.range.primitives;
import std.typecons;

import dyaml.emitter;
import dyaml.event;
import dyaml.exception;
import dyaml.linebreak;
import dyaml.node;
import dyaml.representer;
import dyaml.resolver;
import dyaml.serializer;
import dyaml.style;
import dyaml.tagdirective;


/**
 * Dumps YAML documents to files or streams.
 *
 * User specified Representer and/or Resolver can be used to support new
 * tags / data types.
 *
 * Setters are provided to affect output details (style, etc.).
 */
auto dumper()
{
    auto dumper = Dumper();
    dumper.resolver = Resolver.withDefaultResolvers;
    return dumper;
}

struct Dumper
{
    private:
        //Indentation width.
        int indent_ = 2;
        //Tag directives to use.
        TagDirective[] tags_;
    public:
        //Resolver to resolve tags.
        Resolver resolver;
        //Write scalars in canonical form?
        bool canonical;
        //Preferred text width.
        uint textWidth = 80;
        //Line break to use. Unix by default.
        LineBreak lineBreak = LineBreak.unix;
        //YAML version string. Default is 1.1.
        string YAMLVersion = "1.1";
        //Always explicitly write document start? Default is no explicit start.
        bool explicitStart = false;
        //Always explicitly write document end? Default is no explicit end.
        bool explicitEnd = false;

        //Name of the output file or stream, used in error messages.
        string name = "<unknown>";

        // Default style for scalar nodes. If style is $(D ScalarStyle.invalid), the _style is chosen automatically.
        ScalarStyle defaultScalarStyle = ScalarStyle.invalid;
        // Default style for collection nodes. If style is $(D CollectionStyle.invalid), the _style is chosen automatically.
        CollectionStyle defaultCollectionStyle = CollectionStyle.invalid;

        @disable bool opEquals(ref Dumper);
        @disable int opCmp(ref Dumper);

        ///Set indentation width. 2 by default. Must not be zero.
        @property void indent(uint indent) pure @safe nothrow
        in
        {
            assert(indent != 0, "Can't use zero YAML indent width");
        }
        do
        {
            indent_ = indent;
        }

        /**
         * Specify tag directives.
         *
         * A tag directive specifies a shorthand notation for specifying _tags.
         * Each tag directive associates a handle with a prefix. This allows for
         * compact tag notation.
         *
         * Each handle specified MUST start and end with a '!' character
         * (a single character "!" handle is allowed as well).
         *
         * Only alphanumeric characters, '-', and '__' may be used in handles.
         *
         * Each prefix MUST not be empty.
         *
         * The "!!" handle is used for default YAML _tags with prefix
         * "tag:yaml.org,2002:". This can be overridden.
         *
         * Params:  tags = Tag directives (keys are handles, values are prefixes).
         */
        @property void tagDirectives(string[string] tags) pure @safe
        {
            TagDirective[] t;
            foreach(handle, prefix; tags)
            {
                assert(handle.length >= 1 && handle[0] == '!' && handle[$ - 1] == '!',
                       "A tag handle is empty or does not start and end with a " ~
                       "'!' character : " ~ handle);
                assert(prefix.length >= 1, "A tag prefix is empty");
                t ~= TagDirective(handle, prefix);
            }
            tags_ = t;
        }
        ///
        @safe unittest
        {
            auto dumper = dumper();
            string[string] directives;
            directives["!short!"] = "tag:long.org,2011:";
            //This will emit tags starting with "tag:long.org,2011"
            //with a "!short!" prefix instead.
            dumper.tagDirectives(directives);
            dumper.dump(new Appender!string(), Node("foo"));
        }

        /**
         * Dump one or more YAML _documents to the file/stream.
         *
         * Note that while you can call dump() multiple times on the same
         * dumper, you will end up writing multiple YAML "files" to the same
         * file/stream.
         *
         * Params:  documents = Documents to _dump (root nodes of the _documents).
         *
         * Throws:  YAMLException on error (e.g. invalid nodes,
         *          unable to write to file/stream).
         */
        void dump(CharacterType = char, Range)(Range range, Node[] documents ...)
            if (isOutputRange!(Range, CharacterType) &&
                isOutputRange!(Range, char) || isOutputRange!(Range, wchar) || isOutputRange!(Range, dchar))
        {
            try
            {
                auto emitter = new Emitter!(Range, CharacterType)(range, canonical, indent_, textWidth, lineBreak);
                auto serializer = Serializer(resolver, explicitStart ? Yes.explicitStart : No.explicitStart,
                                             explicitEnd ? Yes.explicitEnd : No.explicitEnd, YAMLVersion, tags_);
                serializer.startStream(emitter);
                foreach(ref document; documents)
                {
                    auto data = representData(document, defaultScalarStyle, defaultCollectionStyle);
                    serializer.serialize(emitter, data);
                }
                serializer.endStream(emitter);
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to dump YAML to stream "
                                        ~ name ~ " : " ~ e.msg, e.file, e.line);
            }
        }
}
///Write to a file
@safe unittest
{
    auto node = Node([1, 2, 3, 4, 5]);
    dumper().dump(new Appender!string(), node);
}
///Write multiple YAML documents to a file
@safe unittest
{
    auto node1 = Node([1, 2, 3, 4, 5]);
    auto node2 = Node("This document contains only one string");
    dumper().dump(new Appender!string(), node1, node2);
    //Or with an array:
    dumper().dump(new Appender!string(), [node1, node2]);
}
///Write to memory
@safe unittest
{
    auto stream = new Appender!string();
    auto node = Node([1, 2, 3, 4, 5]);
    dumper().dump(stream, node);
}
///Use a custom resolver to support custom data types and/or implicit tags
@safe unittest
{
    import std.regex : regex;
    auto node = Node([1, 2, 3, 4, 5]);
    auto dumper = dumper();
    dumper.resolver.addImplicitResolver("!tag", regex("A.*"), "A");
    dumper.dump(new Appender!string(), node);
}
/// Set default scalar style
@safe unittest
{
    auto stream = new Appender!string();
    auto node = Node("Hello world!");
    auto dumper = dumper();
    dumper.defaultScalarStyle = ScalarStyle.singleQuoted;
    dumper.dump(stream, node);
}
/// Set default collection style
@safe unittest
{
    auto stream = new Appender!string();
    auto node = Node(["Hello", "world!"]);
    auto dumper = dumper();
    dumper.defaultCollectionStyle = CollectionStyle.flow;
    dumper.dump(stream, node);
}
// Make sure the styles are actually used
@safe unittest
{
    auto stream = new Appender!string();
    auto node = Node([Node("Hello world!"), Node(["Hello", "world!"])]);
    auto dumper = dumper();
    dumper.defaultScalarStyle = ScalarStyle.singleQuoted;
    dumper.defaultCollectionStyle = CollectionStyle.flow;
    dumper.explicitEnd = false;
    dumper.explicitStart = false;
    dumper.YAMLVersion = null;
    dumper.dump(stream, node);
    assert(stream.data == "['Hello world!', ['Hello', 'world!']]\n");
}
// Explicit document start/end markers
@safe unittest
{
    auto stream = new Appender!string();
    auto node = Node([1, 2, 3, 4, 5]);
    auto dumper = dumper();
    dumper.explicitEnd = true;
    dumper.explicitStart = true;
    dumper.YAMLVersion = null;
    dumper.dump(stream, node);
    //Skip version string
    assert(stream.data[0..3] == "---");
    //account for newline at end
    assert(stream.data[$-4..$-1] == "...");
}
@safe unittest
{
    auto stream = new Appender!string();
    auto node = Node([Node("Te, st2")]);
    auto dumper = dumper();
    dumper.explicitStart = true;
    dumper.explicitEnd = false;
    dumper.YAMLVersion = null;
    dumper.dump(stream, node);
    assert(stream.data == "--- ['Te, st2']\n");
}
// No explicit document start/end markers
@safe unittest
{
    auto stream = new Appender!string();
    auto node = Node([1, 2, 3, 4, 5]);
    auto dumper = dumper();
    dumper.explicitEnd = false;
    dumper.explicitStart = false;
    dumper.YAMLVersion = null;
    dumper.dump(stream, node);
    //Skip version string
    assert(stream.data[0..3] != "---");
    //account for newline at end
    assert(stream.data[$-4..$-1] != "...");
}
// Windows, macOS line breaks
@safe unittest
{
    auto node = Node(0);
    {
        auto stream = new Appender!string();
        auto dumper = dumper();
        dumper.explicitEnd = true;
        dumper.explicitStart = true;
        dumper.YAMLVersion = null;
        dumper.lineBreak = LineBreak.windows;
        dumper.dump(stream, node);
        assert(stream.data == "--- 0\r\n...\r\n");
    }
    {
        auto stream = new Appender!string();
        auto dumper = dumper();
        dumper.explicitEnd = true;
        dumper.explicitStart = true;
        dumper.YAMLVersion = null;
        dumper.lineBreak = LineBreak.macintosh;
        dumper.dump(stream, node);
        assert(stream.data == "--- 0\r...\r");
    }
}
