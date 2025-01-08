
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * YAML events.
 * Code based on PyYAML: http://www.pyyaml.org
 */
module dub.internal.dyaml.event;

import std.array;
import std.conv;

import dub.internal.dyaml.exception;
import dub.internal.dyaml.reader;
import dub.internal.dyaml.tagdirective;
import dub.internal.dyaml.style;


package:
///Event types.
enum EventID : ubyte
{
    invalid = 0,     /// Invalid (uninitialized) event.
    streamStart,     /// Stream start
    streamEnd,       /// Stream end
    documentStart,   /// Document start
    documentEnd,     /// Document end
    alias_,           /// Alias
    scalar,          /// Scalar
    sequenceStart,   /// Sequence start
    sequenceEnd,     /// Sequence end
    mappingStart,    /// Mapping start
    mappingEnd       /// Mapping end
}

/**
 * YAML event produced by parser.
 *
 * 48 bytes on 64bit.
 */
struct Event
{
    @disable int opCmp(ref Event);

    ///Value of the event, if any.
    string value;
    ///Start position of the event in file/stream.
    Mark startMark;
    ///End position of the event in file/stream.
    Mark endMark;
    union
    {
        struct
        {
            ///Anchor of the event, if any.
            string _anchor;
            ///Tag of the event, if any.
            string _tag;
        }
        ///Tag directives, if this is a DocumentStart.
        //TagDirectives tagDirectives;
        TagDirective[] _tagDirectives;
    }
    ///Event type.
    EventID id = EventID.invalid;
    ///Style of scalar event, if this is a scalar event.
    ScalarStyle scalarStyle = ScalarStyle.invalid;
    ///Should the tag be implicitly resolved?
    bool implicit;
    /**
     * Is this document event explicit?
     *
     * Used if this is a DocumentStart or DocumentEnd.
     */
    alias explicitDocument = implicit;
    ///Collection style, if this is a SequenceStart or MappingStart.
    CollectionStyle collectionStyle = CollectionStyle.invalid;

    ///Is this a null (uninitialized) event?
    @property bool isNull() const pure @safe nothrow {return id == EventID.invalid;}

    ///Get string representation of the token ID.
    @property string idString() const @safe {return to!string(id);}

    auto ref anchor() inout @trusted pure {
        assert(id != EventID.documentStart, "DocumentStart events cannot have anchors.");
        return _anchor;
    }

    auto ref tag() inout @trusted pure {
        assert(id != EventID.documentStart, "DocumentStart events cannot have tags.");
        return _tag;
    }

    auto ref tagDirectives() inout @trusted pure {
        assert(id == EventID.documentStart, "Only DocumentStart events have tag directives.");
        return _tagDirectives;
    }
    void toString(W)(ref W writer) const
    {
        import std.algorithm.iteration : substitute;
        import std.format : formattedWrite;
        import std.range : put;
        final switch (id)
        {
            case EventID.scalar:
                put(writer, "=VAL ");
                if (anchor != "")
                {
                    writer.formattedWrite!"&%s " (anchor);
                }
                if (tag != "")
                {
                    writer.formattedWrite!"<%s> " (tag);
                }
                final switch(scalarStyle)
                {
                    case ScalarStyle.singleQuoted:
                        put(writer, "'");
                        break;
                    case ScalarStyle.doubleQuoted:
                        put(writer, "\"");
                        break;
                    case ScalarStyle.literal:
                        put(writer, "|");
                        break;
                    case ScalarStyle.folded:
                        put(writer, ">");
                        break;
                    case ScalarStyle.invalid: //default to plain
                    case ScalarStyle.plain:
                        put(writer, ":");
                        break;
                }
                if (value != "")
                {
                    writer.formattedWrite!"%s"(value.substitute("\n", "\\n", `\`, `\\`, "\r", "\\r", "\t", "\\t", "\b", "\\b"));
                }
                break;
            case EventID.streamStart:
                put(writer, "+STR");
                break;
            case EventID.documentStart:
                put(writer, "+DOC");
                if (explicitDocument)
                {
                    put(writer, " ---");
                }
                break;
            case EventID.mappingStart:
                put(writer, "+MAP");
                if (collectionStyle == CollectionStyle.flow)
                {
                    put(writer, " {}");
                }
                if (anchor != "")
                {
                    put(writer, " &");
                    put(writer, anchor);
                }
                if (tag != "")
                {
                    put(writer, " <");
                    put(writer, tag);
                    put(writer, ">");
                }
                break;
            case EventID.sequenceStart:
                put(writer, "+SEQ");
                if (collectionStyle == CollectionStyle.flow)
                {
                    put(writer, " []");
                }
                if (anchor != "")
                {
                    put(writer, " &");
                    put(writer, anchor);
                }
                if (tag != "")
                {
                    put(writer, " <");
                    put(writer, tag);
                    put(writer, ">");
                }
                break;
            case EventID.streamEnd:
                put(writer, "-STR");
                break;
            case EventID.documentEnd:
                put(writer, "-DOC");
                if (explicitDocument)
                {
                    put(writer, " ...");
                }
                break;
            case EventID.mappingEnd:
                put(writer, "-MAP");
                break;
            case EventID.sequenceEnd:
                put(writer, "-SEQ");
                break;
            case EventID.alias_:
                put(writer, "=ALI *");
                put(writer, anchor);
                break;
            case EventID.invalid:
                assert(0, "Invalid EventID produced");
        }
    }
}

/**
 * Construct a simple event.
 *
 * Params:  start    = Start position of the event in the file/stream.
 *          end      = End position of the event in the file/stream.
 *          anchor   = Anchor, if this is an alias event.
 */
Event event(EventID id)(const Mark start, const Mark end, const string anchor = null)
    @safe
    in(!(id == EventID.alias_ && anchor == ""), "Missing anchor for alias event")
{
    Event result;
    result.startMark = start;
    result.endMark   = end;
    result.anchor    = anchor;
    result.id        = id;
    return result;
}

/**
 * Construct a collection (mapping or sequence) start event.
 *
 * Params:  start    = Start position of the event in the file/stream.
 *          end      = End position of the event in the file/stream.
 *          anchor   = Anchor of the sequence, if any.
 *          tag      = Tag of the sequence, if specified.
 *          implicit = Should the tag be implicitly resolved?
 *          style = Style to use when outputting document.
 */
Event collectionStartEvent(EventID id)
    (const Mark start, const Mark end, const string anchor, const string tag,
     const bool implicit, const CollectionStyle style) pure @safe nothrow
{
    static assert(id == EventID.sequenceStart || id == EventID.sequenceEnd ||
                  id == EventID.mappingStart || id == EventID.mappingEnd);
    Event result;
    result.startMark       = start;
    result.endMark         = end;
    result.anchor          = anchor;
    result.tag             = tag;
    result.id              = id;
    result.implicit        = implicit;
    result.collectionStyle = style;
    return result;
}

/**
 * Construct a stream start event.
 *
 * Params:  start    = Start position of the event in the file/stream.
 *          end      = End position of the event in the file/stream.
 */
Event streamStartEvent(const Mark start, const Mark end)
    pure @safe nothrow
{
    Event result;
    result.startMark = start;
    result.endMark   = end;
    result.id        = EventID.streamStart;
    return result;
}

///Aliases for simple events.
alias streamEndEvent = event!(EventID.streamEnd);
alias aliasEvent = event!(EventID.alias_);
alias sequenceEndEvent = event!(EventID.sequenceEnd);
alias mappingEndEvent = event!(EventID.mappingEnd);

///Aliases for collection start events.
alias sequenceStartEvent = collectionStartEvent!(EventID.sequenceStart);
alias mappingStartEvent = collectionStartEvent!(EventID.mappingStart);

/**
 * Construct a document start event.
 *
 * Params:  start         = Start position of the event in the file/stream.
 *          end           = End position of the event in the file/stream.
 *          explicit      = Is this an explicit document start?
 *          YAMLVersion   = YAML version string of the document.
 *          tagDirectives = Tag directives of the document.
 */
Event documentStartEvent(const Mark start, const Mark end, const bool explicit, string YAMLVersion,
                         TagDirective[] tagDirectives) pure @safe nothrow
{
    Event result;
    result.value            = YAMLVersion;
    result.startMark        = start;
    result.endMark          = end;
    result.id               = EventID.documentStart;
    result.explicitDocument = explicit;
    result.tagDirectives    = tagDirectives;
    return result;
}

/**
 * Construct a document end event.
 *
 * Params:  start    = Start position of the event in the file/stream.
 *          end      = End position of the event in the file/stream.
 *          explicit = Is this an explicit document end?
 */
Event documentEndEvent(const Mark start, const Mark end, const bool explicit) pure @safe nothrow
{
    Event result;
    result.startMark        = start;
    result.endMark          = end;
    result.id               = EventID.documentEnd;
    result.explicitDocument = explicit;
    return result;
}

/// Construct a scalar event.
///
/// Params:  start    = Start position of the event in the file/stream.
///          end      = End position of the event in the file/stream.
///          anchor   = Anchor of the scalar, if any.
///          tag      = Tag of the scalar, if specified.
///          implicit = Should the tag be implicitly resolved?
///          value    = String value of the scalar.
///          style    = Scalar style.
Event scalarEvent(const Mark start, const Mark end, const string anchor, const string tag,
                  const bool implicit, const string value,
                  const ScalarStyle style = ScalarStyle.invalid) @safe pure nothrow @nogc
{
    Event result;
    result.value       = value;
    result.startMark   = start;
    result.endMark     = end;

    result.anchor  = anchor;
    result.tag     = tag;

    result.id          = EventID.scalar;
    result.scalarStyle = style;
    result.implicit    = implicit;
    return result;
}
