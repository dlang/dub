//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * YAML emitter.
 * Code based on PyYAML: http://www.pyyaml.org
 */
module dub.internal.dyaml.emitter;


import std.algorithm;
import std.array;
import std.ascii;
import std.conv;
import std.encoding;
import std.exception;
import std.format;
import std.range;
import std.string;
import std.system;
import std.typecons;
import std.utf;

import dub.internal.dyaml.encoding;
import dub.internal.dyaml.escapes;
import dub.internal.dyaml.event;
import dub.internal.dyaml.exception;
import dub.internal.dyaml.linebreak;
import dub.internal.dyaml.queue;
import dub.internal.dyaml.scanner;
import dub.internal.dyaml.style;
import dub.internal.dyaml.tagdirective;


package:

//Stores results of analysis of a scalar, determining e.g. what scalar style to use.
struct ScalarAnalysis
{
    //Scalar itself.
    string scalar;

    enum AnalysisFlags
    {
        empty = 1<<0,
        multiline = 1<<1,
        allowFlowPlain = 1<<2,
        allowBlockPlain = 1<<3,
        allowSingleQuoted = 1<<4,
        allowDoubleQuoted = 1<<5,
        allowBlock = 1<<6,
        isNull = 1<<7
    }

    ///Analysis results.
    BitFlags!AnalysisFlags flags;
}

private alias isNewLine = among!('\n', '\u0085', '\u2028', '\u2029');

private alias isSpecialChar = among!('#', ',', '[', ']', '{', '}', '&', '*', '!', '|', '>', '\\', '\'', '"', '%', '@', '`');

private alias isFlowIndicator = among!(',', '?', '[', ']', '{', '}');

private alias isSpace = among!('\0', '\n', '\r', '\u0085', '\u2028', '\u2029', ' ', '\t');

//Emits YAML events into a file/stream.
struct Emitter(Range, CharType) if (isOutputRange!(Range, CharType))
{
    private:
        ///Default tag handle shortcuts and replacements.
        static TagDirective[] defaultTagDirectives_ =
            [TagDirective("!", "!"), TagDirective("!!", "tag:yaml.org,2002:")];

        ///Stream to write to.
        Range stream_;

        /// Type used for upcoming emitter steps
        alias EmitterFunction = void function(scope typeof(this)*) @safe;

        ///Stack of states.
        Appender!(EmitterFunction[]) states_;

        ///Current state.
        EmitterFunction state_;

        ///Event queue.
        Queue!Event events_;
        ///Event we're currently emitting.
        Event event_;

        ///Stack of previous indentation levels.
        Appender!(int[]) indents_;
        ///Current indentation level.
        int indent_ = -1;

        ///Level of nesting in flow context. If 0, we're in block context.
        uint flowLevel_ = 0;

        /// Describes context (where we are in the document).
        enum Context
        {
            /// Root node of a document.
            root,
            /// Sequence.
            sequence,
            /// Mapping.
            mappingNoSimpleKey,
            /// Mapping, in a simple key.
            mappingSimpleKey,
        }
        /// Current context.
        Context context_;

        ///Characteristics of the last emitted character:

        ///Line.
        uint line_ = 0;
        ///Column.
        uint column_ = 0;
        ///Whitespace character?
        bool whitespace_ = true;
        ///indentation space, '-', '?', or ':'?
        bool indentation_ = true;

        ///Does the document require an explicit document indicator?
        bool openEnded_;

        ///Formatting details.

        ///Canonical scalar format?
        bool canonical_;
        ///Best indentation width.
        uint bestIndent_ = 2;
        ///Best text width.
        uint bestWidth_ = 80;
        ///Best line break character/s.
        LineBreak bestLineBreak_;

        ///Tag directive handle - prefix pairs.
        TagDirective[] tagDirectives_;

        ///Anchor/alias to process.
        string preparedAnchor_ = null;
        ///Tag to process.
        string preparedTag_ = null;

        ///Analysis result of the current scalar.
        ScalarAnalysis analysis_;
        ///Style of the current scalar.
        ScalarStyle style_ = ScalarStyle.invalid;

    public:
        @disable int opCmp(ref Emitter);
        @disable bool opEquals(ref Emitter);

        /**
         * Construct an emitter.
         *
         * Params:  stream    = Output range to write to.
         *          canonical = Write scalars in canonical form?
         *          indent    = Indentation width.
         *          lineBreak = Line break character/s.
         */
        this(Range stream, const bool canonical, const int indent, const int width,
             const LineBreak lineBreak) @safe
        {
            states_.reserve(32);
            indents_.reserve(32);
            stream_ = stream;
            canonical_ = canonical;
            nextExpected!"expectStreamStart"();

            if(indent > 1 && indent < 10){bestIndent_ = indent;}
            if(width > bestIndent_ * 2)  {bestWidth_ = width;}
            bestLineBreak_ = lineBreak;

            analysis_.flags.isNull = true;
        }

        ///Emit an event.
        void emit(Event event) @safe
        {
            events_.push(event);
            while(!needMoreEvents())
            {
                event_ = events_.pop();
                callNext();
                event_.destroy();
            }
        }

    private:
        ///Pop and return the newest state in states_.
        EmitterFunction popState() @safe
            in(states_.data.length > 0,
                "Emitter: Need to pop a state but there are no states left")
        {
            const result = states_.data[$-1];
            states_.shrinkTo(states_.data.length - 1);
            return result;
        }

        void pushState(string D)() @safe
        {
            states_ ~= mixin("function(typeof(this)* self) { self."~D~"(); }");
        }

        ///Pop and return the newest indent in indents_.
        int popIndent() @safe
            in(indents_.data.length > 0,
                "Emitter: Need to pop an indent level but there" ~
                " are no indent levels left")
        {
            const result = indents_.data[$-1];
            indents_.shrinkTo(indents_.data.length - 1);
            return result;
        }

        ///Write a string to the file/stream.
        void writeString(const scope char[] str) @safe
        {
            static if(is(CharType == char))
            {
                copy(str, stream_);
            }
            static if(is(CharType == wchar))
            {
                const buffer = to!wstring(str);
                copy(buffer, stream_);
            }
            static if(is(CharType == dchar))
            {
                const buffer = to!dstring(str);
                copy(buffer, stream_);
            }
        }

        ///In some cases, we wait for a few next events before emitting.
        bool needMoreEvents() @safe nothrow
        {
            if(events_.length == 0){return true;}

            const event = events_.peek();
            if(event.id == EventID.documentStart){return needEvents(1);}
            if(event.id == EventID.sequenceStart){return needEvents(2);}
            if(event.id == EventID.mappingStart) {return needEvents(3);}

            return false;
        }

        ///Determines if we need specified number of more events.
        bool needEvents(in uint count) @safe nothrow
        {
            int level;

            foreach(const event; events_.range)
            {
                if(event.id.among!(EventID.documentStart, EventID.sequenceStart, EventID.mappingStart)) {++level;}
                else if(event.id.among!(EventID.documentEnd, EventID.sequenceEnd, EventID.mappingEnd)) {--level;}
                else if(event.id == EventID.streamStart){level = -1;}

                if(level < 0)
                {
                    return false;
                }
            }

            return events_.length < (count + 1);
        }

        ///Increase indentation level.
        void increaseIndent(const Flag!"flow" flow = No.flow, const bool indentless = false) @safe
        {
            indents_ ~= indent_;
            if(indent_ == -1)
            {
                indent_ = flow ? bestIndent_ : 0;
            }
            else if(!indentless)
            {
                indent_ += bestIndent_;
            }
        }

        ///Determines if the type of current event is as specified. Throws if no event.
        bool eventTypeIs(in EventID id) const pure @safe
            in(!event_.isNull, "Expected an event, but no event is available.")
        {
            return event_.id == id;
        }


        //States.


        //Stream handlers.

        ///Handle start of a file/stream.
        void expectStreamStart() @safe
            in(eventTypeIs(EventID.streamStart),
                "Expected streamStart, but got " ~ event_.idString)
        {

            writeStreamStart();
            nextExpected!"expectDocumentStart!(Yes.first)"();
        }

        ///Expect nothing, throwing if we still have something.
        void expectNothing() @safe
        {
            assert(0, "Expected nothing, but got " ~ event_.idString);
        }

        //Document handlers.

        ///Handle start of a document.
        void expectDocumentStart(Flag!"first" first)() @safe
            in(eventTypeIs(EventID.documentStart) || eventTypeIs(EventID.streamEnd),
                "Expected documentStart or streamEnd, but got " ~ event_.idString)
        {

            if(event_.id == EventID.documentStart)
            {
                const YAMLVersion = event_.value;
                auto tagDirectives = event_.tagDirectives;
                if(openEnded_ && (YAMLVersion !is null || tagDirectives !is null))
                {
                    writeIndicator("...", Yes.needWhitespace);
                    writeIndent();
                }

                if(YAMLVersion !is null)
                {
                    writeVersionDirective(prepareVersion(YAMLVersion));
                }

                if(tagDirectives !is null)
                {
                    tagDirectives_ = tagDirectives;
                    sort!"icmp(a.handle, b.handle) < 0"(tagDirectives_);

                    foreach(ref pair; tagDirectives_)
                    {
                        writeTagDirective(prepareTagHandle(pair.handle),
                                          prepareTagPrefix(pair.prefix));
                    }
                }

                bool eq(ref TagDirective a, ref TagDirective b){return a.handle == b.handle;}
                //Add any default tag directives that have not been overriden.
                foreach(ref def; defaultTagDirectives_)
                {
                    if(!std.algorithm.canFind!eq(tagDirectives_, def))
                    {
                        tagDirectives_ ~= def;
                    }
                }

                const implicit = first && !event_.explicitDocument && !canonical_ &&
                                 YAMLVersion is null && tagDirectives is null &&
                                 !checkEmptyDocument();
                if(!implicit)
                {
                    writeIndent();
                    writeIndicator("---", Yes.needWhitespace);
                    if(canonical_){writeIndent();}
                }
                nextExpected!"expectRootNode"();
            }
            else if(event_.id == EventID.streamEnd)
            {
                if(openEnded_)
                {
                    writeIndicator("...", Yes.needWhitespace);
                    writeIndent();
                }
                writeStreamEnd();
                nextExpected!"expectNothing"();
            }
        }

        ///Handle end of a document.
        void expectDocumentEnd() @safe
            in(eventTypeIs(EventID.documentEnd),
                "Expected DocumentEnd, but got " ~ event_.idString)
        {

            writeIndent();
            if(event_.explicitDocument)
            {
                writeIndicator("...", Yes.needWhitespace);
                writeIndent();
            }
            nextExpected!"expectDocumentStart!(No.first)"();
        }

        ///Handle the root node of a document.
        void expectRootNode() @safe
        {
            pushState!"expectDocumentEnd"();
            expectNode(Context.root);
        }

        ///Handle a mapping node.
        //
        //Params: simpleKey = Are we in a simple key?
        void expectMappingNode(const bool simpleKey = false) @safe
        {
            expectNode(simpleKey ? Context.mappingSimpleKey : Context.mappingNoSimpleKey);
        }

        ///Handle a sequence node.
        void expectSequenceNode() @safe
        {
            expectNode(Context.sequence);
        }

        ///Handle a new node. Context specifies where in the document we are.
        void expectNode(const Context context) @safe
        {
            context_ = context;

            const flowCollection = event_.collectionStyle == CollectionStyle.flow;

            switch(event_.id)
            {
                case EventID.alias_: expectAlias(); break;
                case EventID.scalar:
                     processAnchor("&");
                     processTag();
                     expectScalar();
                     break;
                case EventID.sequenceStart:
                     processAnchor("&");
                     processTag();
                     if(flowLevel_ > 0 || canonical_ || flowCollection || checkEmptySequence())
                     {
                         expectFlowSequence();
                     }
                     else
                     {
                         expectBlockSequence();
                     }
                     break;
                case EventID.mappingStart:
                     processAnchor("&");
                     processTag();
                     if(flowLevel_ > 0 || canonical_ || flowCollection || checkEmptyMapping())
                     {
                         expectFlowMapping();
                     }
                     else
                     {
                         expectBlockMapping();
                     }
                     break;
                default:
                     assert(0, "Expected alias_, scalar, sequenceStart or " ~
                                     "mappingStart, but got: " ~ event_.idString);
            }
        }
        ///Handle an alias.
        void expectAlias() @safe
            in(event_.anchor != "", "Anchor is not specified for alias")
        {
            processAnchor("*");
            nextExpected(popState());
        }

        ///Handle a scalar.
        void expectScalar() @safe
        {
            increaseIndent(Yes.flow);
            processScalar();
            indent_ = popIndent();
            nextExpected(popState());
        }

        //Flow sequence handlers.

        ///Handle a flow sequence.
        void expectFlowSequence() @safe
        {
            writeIndicator("[", Yes.needWhitespace, Yes.whitespace);
            ++flowLevel_;
            increaseIndent(Yes.flow);
            nextExpected!"expectFlowSequenceItem!(Yes.first)"();
        }

        ///Handle a flow sequence item.
        void expectFlowSequenceItem(Flag!"first" first)() @safe
        {
            if(event_.id == EventID.sequenceEnd)
            {
                indent_ = popIndent();
                --flowLevel_;
                static if(!first) if(canonical_)
                {
                    writeIndicator(",", No.needWhitespace);
                    writeIndent();
                }
                writeIndicator("]", No.needWhitespace);
                nextExpected(popState());
                return;
            }
            static if(!first){writeIndicator(",", No.needWhitespace);}
            if(canonical_ || column_ > bestWidth_){writeIndent();}
            pushState!"expectFlowSequenceItem!(No.first)"();
            expectSequenceNode();
        }

        //Flow mapping handlers.

        ///Handle a flow mapping.
        void expectFlowMapping() @safe
        {
            writeIndicator("{", Yes.needWhitespace, Yes.whitespace);
            ++flowLevel_;
            increaseIndent(Yes.flow);
            nextExpected!"expectFlowMappingKey!(Yes.first)"();
        }

        ///Handle a key in a flow mapping.
        void expectFlowMappingKey(Flag!"first" first)() @safe
        {
            if(event_.id == EventID.mappingEnd)
            {
                indent_ = popIndent();
                --flowLevel_;
                static if (!first) if(canonical_)
                {
                    writeIndicator(",", No.needWhitespace);
                    writeIndent();
                }
                writeIndicator("}", No.needWhitespace);
                nextExpected(popState());
                return;
            }

            static if(!first){writeIndicator(",", No.needWhitespace);}
            if(canonical_ || column_ > bestWidth_){writeIndent();}
            if(!canonical_ && checkSimpleKey())
            {
                pushState!"expectFlowMappingSimpleValue"();
                expectMappingNode(true);
                return;
            }

            writeIndicator("?", Yes.needWhitespace);
            pushState!"expectFlowMappingValue"();
            expectMappingNode();
        }

        ///Handle a simple value in a flow mapping.
        void expectFlowMappingSimpleValue() @safe
        {
            writeIndicator(":", No.needWhitespace);
            pushState!"expectFlowMappingKey!(No.first)"();
            expectMappingNode();
        }

        ///Handle a complex value in a flow mapping.
        void expectFlowMappingValue() @safe
        {
            if(canonical_ || column_ > bestWidth_){writeIndent();}
            writeIndicator(":", Yes.needWhitespace);
            pushState!"expectFlowMappingKey!(No.first)"();
            expectMappingNode();
        }

        //Block sequence handlers.

        ///Handle a block sequence.
        void expectBlockSequence() @safe
        {
            const indentless = (context_ == Context.mappingNoSimpleKey ||
                                context_ == Context.mappingSimpleKey) && !indentation_;
            increaseIndent(No.flow, indentless);
            nextExpected!"expectBlockSequenceItem!(Yes.first)"();
        }

        ///Handle a block sequence item.
        void expectBlockSequenceItem(Flag!"first" first)() @safe
        {
            static if(!first) if(event_.id == EventID.sequenceEnd)
            {
                indent_ = popIndent();
                nextExpected(popState());
                return;
            }

            writeIndent();
            writeIndicator("-", Yes.needWhitespace, No.whitespace, Yes.indentation);
            pushState!"expectBlockSequenceItem!(No.first)"();
            expectSequenceNode();
        }

        //Block mapping handlers.

        ///Handle a block mapping.
        void expectBlockMapping() @safe
        {
            increaseIndent(No.flow);
            nextExpected!"expectBlockMappingKey!(Yes.first)"();
        }

        ///Handle a key in a block mapping.
        void expectBlockMappingKey(Flag!"first" first)() @safe
        {
            static if(!first) if(event_.id == EventID.mappingEnd)
            {
                indent_ = popIndent();
                nextExpected(popState());
                return;
            }

            writeIndent();
            if(checkSimpleKey())
            {
                pushState!"expectBlockMappingSimpleValue"();
                expectMappingNode(true);
                return;
            }

            writeIndicator("?", Yes.needWhitespace, No.whitespace, Yes.indentation);
            pushState!"expectBlockMappingValue"();
            expectMappingNode();
        }

        ///Handle a simple value in a block mapping.
        void expectBlockMappingSimpleValue() @safe
        {
            writeIndicator(":", No.needWhitespace);
            pushState!"expectBlockMappingKey!(No.first)"();
            expectMappingNode();
        }

        ///Handle a complex value in a block mapping.
        void expectBlockMappingValue() @safe
        {
            writeIndent();
            writeIndicator(":", Yes.needWhitespace, No.whitespace, Yes.indentation);
            pushState!"expectBlockMappingKey!(No.first)"();
            expectMappingNode();
        }

        //Checkers.

        ///Check if an empty sequence is next.
        bool checkEmptySequence() const @safe pure nothrow
        {
            return event_.id == EventID.sequenceStart && events_.length > 0
                   && events_.peek().id == EventID.sequenceEnd;
        }

        ///Check if an empty mapping is next.
        bool checkEmptyMapping() const @safe pure nothrow
        {
            return event_.id == EventID.mappingStart && events_.length > 0
                   && events_.peek().id == EventID.mappingEnd;
        }

        ///Check if an empty document is next.
        bool checkEmptyDocument() const @safe pure nothrow
        {
            if(event_.id != EventID.documentStart || events_.length == 0)
            {
                return false;
            }

            const event = events_.peek();
            const emptyScalar = event.id == EventID.scalar && (event.anchor is null) &&
                                (event.tag is null) && event.implicit && event.value == "";
            return emptyScalar;
        }

        ///Check if a simple key is next.
        bool checkSimpleKey() @safe
        {
            uint length;
            const id = event_.id;
            const scalar = id == EventID.scalar;
            const collectionStart = id == EventID.mappingStart ||
                                    id == EventID.sequenceStart;

            if((id == EventID.alias_ || scalar || collectionStart)
               && (event_.anchor !is null))
            {
                if(preparedAnchor_ is null)
                {
                    preparedAnchor_ = prepareAnchor(event_.anchor);
                }
                length += preparedAnchor_.length;
            }

            if((scalar || collectionStart) && (event_.tag !is null))
            {
                if(preparedTag_ is null){preparedTag_ = prepareTag(event_.tag);}
                length += preparedTag_.length;
            }

            if(scalar)
            {
                if(analysis_.flags.isNull){analysis_ = analyzeScalar(event_.value);}
                length += analysis_.scalar.length;
            }

            if(length >= 128){return false;}

            return id == EventID.alias_ ||
                   (scalar && !analysis_.flags.empty && !analysis_.flags.multiline) ||
                   checkEmptySequence() ||
                   checkEmptyMapping();
        }

        ///Process and write a scalar.
        void processScalar() @safe
        {
            if(analysis_.flags.isNull){analysis_ = analyzeScalar(event_.value);}
            if(style_ == ScalarStyle.invalid)
            {
                style_ = chooseScalarStyle();
            }

            //if(analysis_.flags.multiline && (context_ != Context.mappingSimpleKey) &&
            //   ([ScalarStyle.invalid, ScalarStyle.plain, ScalarStyle.singleQuoted, ScalarStyle.doubleQuoted)
            //    .canFind(style_))
            //{
            //    writeIndent();
            //}
            auto writer = ScalarWriter!(Range, CharType)(&this, analysis_.scalar,
                                       context_ != Context.mappingSimpleKey);
            final switch(style_)
            {
                case ScalarStyle.invalid:      assert(false);
                case ScalarStyle.doubleQuoted: writer.writeDoubleQuoted(); break;
                case ScalarStyle.singleQuoted: writer.writeSingleQuoted(); break;
                case ScalarStyle.folded:       writer.writeFolded();       break;
                case ScalarStyle.literal:      writer.writeLiteral();      break;
                case ScalarStyle.plain:        writer.writePlain();        break;
            }
            analysis_.flags.isNull = true;
            style_ = ScalarStyle.invalid;
        }

        ///Process and write an anchor/alias.
        void processAnchor(const string indicator) @safe
        {
            if(event_.anchor is null)
            {
                preparedAnchor_ = null;
                return;
            }
            if(preparedAnchor_ is null)
            {
                preparedAnchor_ = prepareAnchor(event_.anchor);
            }
            if(preparedAnchor_ !is null && preparedAnchor_ != "")
            {
                writeIndicator(indicator, Yes.needWhitespace);
                writeString(preparedAnchor_);
            }
            preparedAnchor_ = null;
        }

        ///Process and write a tag.
        void processTag() @safe
        {
            string tag = event_.tag;

            if(event_.id == EventID.scalar)
            {
                if(style_ == ScalarStyle.invalid){style_ = chooseScalarStyle();}
                if((!canonical_ || (tag is null)) &&
                   ((tag == "tag:yaml.org,2002:str") || (style_ == ScalarStyle.plain ? event_.implicit : !event_.implicit && (tag is null))))
                {
                    preparedTag_ = null;
                    return;
                }
                if(event_.implicit && (tag is null))
                {
                    tag = "!";
                    preparedTag_ = null;
                }
            }
            else if((!canonical_ || (tag is null)) && event_.implicit)
            {
                preparedTag_ = null;
                return;
            }

            assert(tag != "", "Tag is not specified");
            if(preparedTag_ is null){preparedTag_ = prepareTag(tag);}
            if(preparedTag_ !is null && preparedTag_ != "")
            {
                writeIndicator(preparedTag_, Yes.needWhitespace);
            }
            preparedTag_ = null;
        }

        ///Determine style to write the current scalar in.
        ScalarStyle chooseScalarStyle() @safe
        {
            if(analysis_.flags.isNull){analysis_ = analyzeScalar(event_.value);}

            const style          = event_.scalarStyle;
            const invalidOrPlain = style == ScalarStyle.invalid || style == ScalarStyle.plain;
            const block          = style == ScalarStyle.literal || style == ScalarStyle.folded;
            const singleQuoted   = style == ScalarStyle.singleQuoted;
            const doubleQuoted   = style == ScalarStyle.doubleQuoted;

            const allowPlain     = flowLevel_ > 0 ? analysis_.flags.allowFlowPlain
                                                  : analysis_.flags.allowBlockPlain;
            //simple empty or multiline scalars can't be written in plain style
            const simpleNonPlain = (context_ == Context.mappingSimpleKey) &&
                                   (analysis_.flags.empty || analysis_.flags.multiline);

            if(doubleQuoted || canonical_)
            {
                return ScalarStyle.doubleQuoted;
            }

            if(invalidOrPlain && event_.implicit && !simpleNonPlain && allowPlain)
            {
                return ScalarStyle.plain;
            }

            if(block && flowLevel_ == 0 && context_ != Context.mappingSimpleKey &&
               analysis_.flags.allowBlock)
            {
                return style;
            }

            if((invalidOrPlain || singleQuoted) &&
               analysis_.flags.allowSingleQuoted &&
               !(context_ == Context.mappingSimpleKey && analysis_.flags.multiline))
            {
                return ScalarStyle.singleQuoted;
            }

            return ScalarStyle.doubleQuoted;
        }

        ///Prepare YAML version string for output.
        static string prepareVersion(const string YAMLVersion) @safe
            in(YAMLVersion.split(".")[0] == "1",
                "Unsupported YAML version: " ~ YAMLVersion)
        {
            return YAMLVersion;
        }

        ///Encode an Unicode character for tag directive and write it to writer.
        static void encodeChar(Writer)(ref Writer writer, in dchar c) @safe
        {
            char[4] data;
            const bytes = encode(data, c);
            //For each byte add string in format %AB , where AB are hex digits of the byte.
            foreach(const char b; data[0 .. bytes])
            {
                formattedWrite(writer, "%%%02X", cast(ubyte)b);
            }
        }

        ///Prepare tag directive handle for output.
        static string prepareTagHandle(const string handle) @safe
            in(handle != "", "Tag handle must not be empty")
            in(handle.drop(1).dropBack(1).all!(c => isAlphaNum(c) || c.among!('-', '_')),
                "Tag handle contains invalid characters")
        {
            return handle;
        }

        ///Prepare tag directive prefix for output.
        static string prepareTagPrefix(const string prefix) @safe
            in(prefix != "", "Tag prefix must not be empty")
        {
            auto appender = appender!string();
            const int offset = prefix[0] == '!';
            size_t start, end;

            foreach(const size_t i, const dchar c; prefix)
            {
                const size_t idx = i + offset;
                if(isAlphaNum(c) || c.among!('-', ';', '/', '?', ':', '@', '&', '=', '+', '$', ',', '_', '.', '!', '~', '*', '\\', '\'', '(', ')', '[', ']', '%'))
                {
                    end = idx + 1;
                    continue;
                }

                if(start < idx){appender.put(prefix[start .. idx]);}
                start = end = idx + 1;

                encodeChar(appender, c);
            }

            end = min(end, prefix.length);
            if(start < end){appender.put(prefix[start .. end]);}
            return appender.data;
        }

        ///Prepare tag for output.
        string prepareTag(in string tag) @safe
            in(tag != "", "Tag must not be empty")
        {

            string tagString = tag;
            if (tagString == "!") return "!";
            string handle;
            string suffix = tagString;

            //Sort lexicographically by prefix.
            sort!"icmp(a.prefix, b.prefix) < 0"(tagDirectives_);
            foreach(ref pair; tagDirectives_)
            {
                auto prefix = pair.prefix;
                if(tagString.startsWith(prefix) &&
                   (prefix != "!" || prefix.length < tagString.length))
                {
                    handle = pair.handle;
                    suffix = tagString[prefix.length .. $];
                }
            }

            auto appender = appender!string();
            appender.put(handle !is null && handle != "" ? handle : "!<");
            size_t start, end;
            foreach(const dchar c; suffix)
            {
                if(isAlphaNum(c) || c.among!('-', ';', '/', '?', ':', '@', '&', '=', '+', '$', ',', '_', '.', '~', '*', '\\', '\'', '(', ')', '[', ']') ||
                   (c == '!' && handle != "!"))
                {
                    ++end;
                    continue;
                }
                if(start < end){appender.put(suffix[start .. end]);}
                start = end = end + 1;

                encodeChar(appender, c);
            }

            if(start < end){appender.put(suffix[start .. end]);}
            if(handle is null || handle == ""){appender.put(">");}

            return appender.data;
        }

        ///Prepare anchor for output.
        static string prepareAnchor(const string anchor) @safe
            in(anchor != "",  "Anchor must not be empty")
            in(anchor.all!isNSAnchorName, "Anchor contains invalid characters")
        {
            return anchor;
        }

        ///Analyze specifed scalar and return the analysis result.
        static ScalarAnalysis analyzeScalar(string scalar) @safe
        {
            ScalarAnalysis analysis;
            analysis.flags.isNull = false;
            analysis.scalar = scalar;

            //Empty scalar is a special case.
            if(scalar is null || scalar == "")
            {
                with(ScalarAnalysis.AnalysisFlags)
                    analysis.flags =
                        empty |
                        allowBlockPlain |
                        allowSingleQuoted |
                        allowDoubleQuoted;
                return analysis;
            }

            //Indicators and special characters (All false by default).
            bool blockIndicators, flowIndicators, lineBreaks, specialCharacters;

            //Important whitespace combinations (All false by default).
            bool leadingSpace, leadingBreak, trailingSpace, trailingBreak,
                 breakSpace, spaceBreak;

            //Check document indicators.
            if(scalar.startsWith("---", "..."))
            {
                blockIndicators = flowIndicators = true;
            }

            //First character or preceded by a whitespace.
            bool preceededByWhitespace = true;

            //Last character or followed by a whitespace.
            bool followedByWhitespace = scalar.length == 1 ||
                                        scalar[1].among!(' ', '\t', '\0', '\n', '\r', '\u0085', '\u2028', '\u2029');

            //The previous character is a space/break (false by default).
            bool previousSpace, previousBreak;

            foreach(const size_t index, const dchar c; scalar)
            {
                //Check for indicators.
                if(index == 0)
                {
                    //Leading indicators are special characters.
                    if(c.isSpecialChar)
                    {
                        flowIndicators = blockIndicators = true;
                    }
                    if(':' == c || '?' == c)
                    {
                        flowIndicators = true;
                        if(followedByWhitespace){blockIndicators = true;}
                    }
                    if(c == '-' && followedByWhitespace)
                    {
                        flowIndicators = blockIndicators = true;
                    }
                }
                else
                {
                    //Some indicators cannot appear within a scalar as well.
                    if(c.isFlowIndicator){flowIndicators = true;}
                    if(c == ':')
                    {
                        flowIndicators = true;
                        if(followedByWhitespace){blockIndicators = true;}
                    }
                    if(c == '#' && preceededByWhitespace)
                    {
                        flowIndicators = blockIndicators = true;
                    }
                }

                //Check for line breaks, special, and unicode characters.
                if(c.isNewLine){lineBreaks = true;}
                if(!(c == '\n' || (c >= '\x20' && c <= '\x7E')) &&
                   !((c == '\u0085' || (c >= '\xA0' && c <= '\uD7FF') ||
                     (c >= '\uE000' && c <= '\uFFFD')) && c != '\uFEFF'))
                {
                    specialCharacters = true;
                }

                //Detect important whitespace combinations.
                if(c == ' ')
                {
                    if(index == 0){leadingSpace = true;}
                    if(index == scalar.length - 1){trailingSpace = true;}
                    if(previousBreak){breakSpace = true;}
                    previousSpace = true;
                    previousBreak = false;
                }
                else if(c.isNewLine)
                {
                    if(index == 0){leadingBreak = true;}
                    if(index == scalar.length - 1){trailingBreak = true;}
                    if(previousSpace){spaceBreak = true;}
                    previousSpace = false;
                    previousBreak = true;
                }
                else
                {
                    previousSpace = previousBreak = false;
                }

                //Prepare for the next character.
                preceededByWhitespace = c.isSpace != 0;
                followedByWhitespace = index + 2 >= scalar.length ||
                                       scalar[index + 2].isSpace;
            }

            with(ScalarAnalysis.AnalysisFlags)
            {
                //Let's decide what styles are allowed.
                analysis.flags |= allowFlowPlain | allowBlockPlain | allowSingleQuoted |
                               allowDoubleQuoted | allowBlock;

                //Leading and trailing whitespaces are bad for plain scalars.
                if(leadingSpace || leadingBreak || trailingSpace || trailingBreak)
                {
                    analysis.flags &= ~(allowFlowPlain | allowBlockPlain);
                }

                //We do not permit trailing spaces for block scalars.
                if(trailingSpace)
                {
                    analysis.flags &= ~allowBlock;
                }

                //Spaces at the beginning of a new line are only acceptable for block
                //scalars.
                if(breakSpace)
                {
                    analysis.flags &= ~(allowFlowPlain | allowBlockPlain | allowSingleQuoted);
                }

                //Spaces followed by breaks, as well as special character are only
                //allowed for double quoted scalars.
                if(spaceBreak || specialCharacters)
                {
                    analysis.flags &= ~(allowFlowPlain | allowBlockPlain | allowSingleQuoted | allowBlock);
                }

                //Although the plain scalar writer supports breaks, we never emit
                //multiline plain scalars.
                if(lineBreaks)
                {
                    analysis.flags &= ~(allowFlowPlain | allowBlockPlain);
                    analysis.flags |= multiline;
                }

                //Flow indicators are forbidden for flow plain scalars.
                if(flowIndicators)
                {
                    analysis.flags &= ~allowFlowPlain;
                }

                //Block indicators are forbidden for block plain scalars.
                if(blockIndicators)
                {
                    analysis.flags &= ~allowBlockPlain;
                }
            }
            return analysis;
        }

        @safe unittest
        {
            with(analyzeScalar("").flags)
            {
                // workaround for empty being std.range.primitives.empty here
                alias empty = ScalarAnalysis.AnalysisFlags.empty;
                assert(empty && allowBlockPlain && allowSingleQuoted && allowDoubleQuoted);
            }
            with(analyzeScalar("a").flags)
            {
                assert(allowFlowPlain && allowBlockPlain && allowSingleQuoted && allowDoubleQuoted && allowBlock);
            }
            with(analyzeScalar(" ").flags)
            {
                assert(allowSingleQuoted && allowDoubleQuoted);
            }
            with(analyzeScalar(" a").flags)
            {
                assert(allowSingleQuoted && allowDoubleQuoted);
            }
            with(analyzeScalar("a ").flags)
            {
                assert(allowSingleQuoted && allowDoubleQuoted);
            }
            with(analyzeScalar("\na").flags)
            {
                assert(allowSingleQuoted && allowDoubleQuoted);
            }
            with(analyzeScalar("a\n").flags)
            {
                assert(allowSingleQuoted && allowDoubleQuoted);
            }
            with(analyzeScalar("\n").flags)
            {
                assert(multiline && allowSingleQuoted && allowDoubleQuoted && allowBlock);
            }
            with(analyzeScalar(" \n").flags)
            {
                assert(multiline && allowDoubleQuoted);
            }
            with(analyzeScalar("\n a").flags)
            {
                assert(multiline && allowDoubleQuoted && allowBlock);
            }
        }

        //Writers.

        ///Start the YAML stream (write the unicode byte order mark).
        void writeStreamStart() @safe
        {
            //Write BOM (except for UTF-8)
            static if(is(CharType == wchar) || is(CharType == dchar))
            {
                stream_.put(cast(CharType)'\uFEFF');
            }
        }

        ///End the YAML stream.
        void writeStreamEnd() @safe {}

        ///Write an indicator (e.g. ":", "[", ">", etc.).
        void writeIndicator(const scope char[] indicator,
                            const Flag!"needWhitespace" needWhitespace,
                            const Flag!"whitespace" whitespace = No.whitespace,
                            const Flag!"indentation" indentation = No.indentation) @safe
        {
            const bool prefixSpace = !whitespace_ && needWhitespace;
            whitespace_  = whitespace;
            indentation_ = indentation_ && indentation;
            openEnded_   = false;
            column_ += indicator.length;
            if(prefixSpace)
            {
                ++column_;
                writeString(" ");
            }
            writeString(indicator);
        }

        ///Write indentation.
        void writeIndent() @safe
        {
            const indent = indent_ == -1 ? 0 : indent_;

            if(!indentation_ || column_ > indent || (column_ == indent && !whitespace_))
            {
                writeLineBreak();
            }
            if(column_ < indent)
            {
                whitespace_ = true;

                //Used to avoid allocation of arbitrary length strings.
                static immutable spaces = "    ";
                size_t numSpaces = indent - column_;
                column_ = indent;
                while(numSpaces >= spaces.length)
                {
                    writeString(spaces);
                    numSpaces -= spaces.length;
                }
                writeString(spaces[0 .. numSpaces]);
            }
        }

        ///Start new line.
        void writeLineBreak(const scope char[] data = null) @safe
        {
            whitespace_ = indentation_ = true;
            ++line_;
            column_ = 0;
            writeString(data is null ? lineBreak(bestLineBreak_) : data);
        }

        ///Write a YAML version directive.
        void writeVersionDirective(const string versionText) @safe
        {
            writeString("%YAML ");
            writeString(versionText);
            writeLineBreak();
        }

        ///Write a tag directive.
        void writeTagDirective(const string handle, const string prefix) @safe
        {
            writeString("%TAG ");
            writeString(handle);
            writeString(" ");
            writeString(prefix);
            writeLineBreak();
        }
        void nextExpected(string D)() @safe
        {
            state_ = mixin("function(typeof(this)* self) { self."~D~"(); }");
        }
        void nextExpected(EmitterFunction f) @safe
        {
            state_ = f;
        }
        void callNext() @safe
        {
            state_(&this);
        }
}


private:

///RAII struct used to write out scalar values.
struct ScalarWriter(Range, CharType)
{
    invariant()
    {
        assert(emitter_.bestIndent_ > 0 && emitter_.bestIndent_ < 10,
               "Emitter bestIndent must be 1 to 9 for one-character indent hint");
    }

    private:
        @disable int opCmp(ref Emitter!(Range, CharType));
        @disable bool opEquals(ref Emitter!(Range, CharType));

        ///Used as "null" UTF-32 character.
        static immutable dcharNone = dchar.max;

        ///Emitter used to emit the scalar.
        Emitter!(Range, CharType)* emitter_;

        ///UTF-8 encoded text of the scalar to write.
        string text_;

        ///Can we split the scalar into multiple lines?
        bool split_;
        ///Are we currently going over spaces in the text?
        bool spaces_;
        ///Are we currently going over line breaks in the text?
        bool breaks_;

        ///Start and end byte of the text range we're currently working with.
        size_t startByte_, endByte_;
        ///End byte of the text range including the currently processed character.
        size_t nextEndByte_;
        ///Start and end character of the text range we're currently working with.
        long startChar_, endChar_;

    public:
        ///Construct a ScalarWriter using emitter to output text.
        this(Emitter!(Range, CharType)* emitter, string text, const bool split = true) @safe nothrow
        {
            emitter_ = emitter;
            text_ = text;
            split_ = split;
        }

        ///Write text as single quoted scalar.
        void writeSingleQuoted() @safe
        {
            emitter_.writeIndicator("\'", Yes.needWhitespace);
            spaces_ = breaks_ = false;
            resetTextPosition();

            do
            {
                const dchar c = nextChar();
                if(spaces_)
                {
                    if(c != ' ' && tooWide() && split_ &&
                       startByte_ != 0 && endByte_ != text_.length)
                    {
                        writeIndent(Flag!"ResetSpace".no);
                        updateRangeStart();
                    }
                    else if(c != ' ')
                    {
                        writeCurrentRange(Flag!"UpdateColumn".yes);
                    }
                }
                else if(breaks_)
                {
                    if(!c.isNewLine)
                    {
                        writeStartLineBreak();
                        writeLineBreaks();
                        emitter_.writeIndent();
                    }
                }
                else if((c == dcharNone || c == '\'' || c == ' ' || c.isNewLine)
                        && startChar_ < endChar_)
                {
                    writeCurrentRange(Flag!"UpdateColumn".yes);
                }
                if(c == '\'')
                {
                    emitter_.column_ += 2;
                    emitter_.writeString("\'\'");
                    startByte_ = endByte_ + 1;
                    startChar_ = endChar_ + 1;
                }
                updateBreaks(c, Flag!"UpdateSpaces".yes);
            }while(endByte_ < text_.length);

            emitter_.writeIndicator("\'", No.needWhitespace);
        }

        ///Write text as double quoted scalar.
        void writeDoubleQuoted() @safe
        {
            resetTextPosition();
            emitter_.writeIndicator("\"", Yes.needWhitespace);
            do
            {
                const dchar c = nextChar();
                //handle special characters
                if(c == dcharNone || c.among!('\"', '\\', '\u0085', '\u2028', '\u2029', '\uFEFF') ||
                   !((c >= '\x20' && c <= '\x7E') ||
                     ((c >= '\xA0' && c <= '\uD7FF') || (c >= '\uE000' && c <= '\uFFFD'))))
                {
                    if(startChar_ < endChar_)
                    {
                        writeCurrentRange(Flag!"UpdateColumn".yes);
                    }
                    if(c != dcharNone)
                    {
                        auto appender = appender!string();
                        if(const dchar es = toEscape(c))
                        {
                            appender.put('\\');
                            appender.put(es);
                        }
                        else
                        {
                            //Write an escaped Unicode character.
                            const format = c <= 255   ? "\\x%02X":
                                           c <= 65535 ? "\\u%04X": "\\U%08X";
                            formattedWrite(appender, format, cast(uint)c);
                        }

                        emitter_.column_ += appender.data.length;
                        emitter_.writeString(appender.data);
                        startChar_ = endChar_ + 1;
                        startByte_ = nextEndByte_;
                    }
                }
                if((endByte_ > 0 && endByte_ < text_.length - strideBack(text_, text_.length))
                   && (c == ' ' || startChar_ >= endChar_)
                   && (emitter_.column_ + endChar_ - startChar_ > emitter_.bestWidth_)
                   && split_)
                {
                    //text_[2:1] is ok in Python but not in D, so we have to use min()
                    emitter_.writeString(text_[min(startByte_, endByte_) .. endByte_]);
                    emitter_.writeString("\\");
                    emitter_.column_ += startChar_ - endChar_ + 1;
                    startChar_ = max(startChar_, endChar_);
                    startByte_ = max(startByte_, endByte_);

                    writeIndent(Flag!"ResetSpace".yes);
                    if(charAtStart() == ' ')
                    {
                        emitter_.writeString("\\");
                        ++emitter_.column_;
                    }
                }
            }while(endByte_ < text_.length);
            emitter_.writeIndicator("\"", No.needWhitespace);
        }

        ///Write text as folded block scalar.
        void writeFolded() @safe
        {
            initBlock('>');
            bool leadingSpace = true;
            spaces_ = false;
            breaks_ = true;
            resetTextPosition();

            do
            {
                const dchar c = nextChar();
                if(breaks_)
                {
                    if(!c.isNewLine)
                    {
                        if(!leadingSpace && c != dcharNone && c != ' ')
                        {
                            writeStartLineBreak();
                        }
                        leadingSpace = (c == ' ');
                        writeLineBreaks();
                        if(c != dcharNone){emitter_.writeIndent();}
                    }
                }
                else if(spaces_)
                {
                    if(c != ' ' && tooWide())
                    {
                        writeIndent(Flag!"ResetSpace".no);
                        updateRangeStart();
                    }
                    else if(c != ' ')
                    {
                        writeCurrentRange(Flag!"UpdateColumn".yes);
                    }
                }
                else if(c == dcharNone || c.isNewLine || c == ' ')
                {
                    writeCurrentRange(Flag!"UpdateColumn".yes);
                    if(c == dcharNone){emitter_.writeLineBreak();}
                }
                updateBreaks(c, Flag!"UpdateSpaces".yes);
            }while(endByte_ < text_.length);
        }

        ///Write text as literal block scalar.
        void writeLiteral() @safe
        {
            initBlock('|');
            breaks_ = true;
            resetTextPosition();

            do
            {
                const dchar c = nextChar();
                if(breaks_)
                {
                    if(!c.isNewLine)
                    {
                        writeLineBreaks();
                        if(c != dcharNone){emitter_.writeIndent();}
                    }
                }
                else if(c == dcharNone || c.isNewLine)
                {
                    writeCurrentRange(Flag!"UpdateColumn".no);
                    if(c == dcharNone){emitter_.writeLineBreak();}
                }
                updateBreaks(c, Flag!"UpdateSpaces".no);
            }while(endByte_ < text_.length);
        }

        ///Write text as plain scalar.
        void writePlain() @safe
        {
            if(emitter_.context_ == Emitter!(Range, CharType).Context.root){emitter_.openEnded_ = true;}
            if(text_ == ""){return;}
            if(!emitter_.whitespace_)
            {
                ++emitter_.column_;
                emitter_.writeString(" ");
            }
            emitter_.whitespace_ = emitter_.indentation_ = false;
            spaces_ = breaks_ = false;
            resetTextPosition();

            do
            {
                const dchar c = nextChar();
                if(spaces_)
                {
                    if(c != ' ' && tooWide() && split_)
                    {
                        writeIndent(Flag!"ResetSpace".yes);
                        updateRangeStart();
                    }
                    else if(c != ' ')
                    {
                        writeCurrentRange(Flag!"UpdateColumn".yes);
                    }
                }
                else if(breaks_)
                {
                    if(!c.isNewLine)
                    {
                        writeStartLineBreak();
                        writeLineBreaks();
                        writeIndent(Flag!"ResetSpace".yes);
                    }
                }
                else if(c == dcharNone || c.isNewLine || c == ' ')
                {
                    writeCurrentRange(Flag!"UpdateColumn".yes);
                }
                updateBreaks(c, Flag!"UpdateSpaces".yes);
            }while(endByte_ < text_.length);
        }

    private:
        ///Get next character and move end of the text range to it.
        @property dchar nextChar() pure @safe
        {
            ++endChar_;
            endByte_ = nextEndByte_;
            if(endByte_ >= text_.length){return dcharNone;}
            const c = text_[nextEndByte_];
            //c is ascii, no need to decode.
            if(c < 0x80)
            {
                ++nextEndByte_;
                return c;
            }
            return decode(text_, nextEndByte_);
        }

        ///Get character at start of the text range.
        @property dchar charAtStart() const pure @safe
        {
            size_t idx = startByte_;
            return decode(text_, idx);
        }

        ///Is the current line too wide?
        @property bool tooWide() const pure @safe nothrow
        {
            return startChar_ + 1 == endChar_ &&
                   emitter_.column_ > emitter_.bestWidth_;
        }

        ///Determine hints (indicators) for block scalar.
        size_t determineBlockHints(char[] hints, uint bestIndent) const pure @safe
        {
            size_t hintsIdx;
            if(text_.length == 0)
                return hintsIdx;

            dchar lastChar(const string str, ref size_t end)
            {
                size_t idx = end = end - strideBack(str, end);
                return decode(text_, idx);
            }

            size_t end = text_.length;
            const last = lastChar(text_, end);
            const secondLast = end > 0 ? lastChar(text_, end) : 0;

            if(text_[0].isNewLine || text_[0] == ' ')
            {
                hints[hintsIdx++] = cast(char)('0' + bestIndent);
            }
            if(!last.isNewLine)
            {
                hints[hintsIdx++] = '-';
            }
            else if(std.utf.count(text_) == 1 || secondLast.isNewLine)
            {
                hints[hintsIdx++] = '+';
            }
            return hintsIdx;
        }

        ///Initialize for block scalar writing with specified indicator.
        void initBlock(const char indicator) @safe
        {
            char[4] hints;
            hints[0] = indicator;
            const hintsLength = 1 + determineBlockHints(hints[1 .. $], emitter_.bestIndent_);
            emitter_.writeIndicator(hints[0 .. hintsLength], Yes.needWhitespace);
            if(hints.length > 0 && hints[$ - 1] == '+')
            {
                emitter_.openEnded_ = true;
            }
            emitter_.writeLineBreak();
        }

        ///Write out the current text range.
        void writeCurrentRange(const Flag!"UpdateColumn" updateColumn) @safe
        {
            emitter_.writeString(text_[startByte_ .. endByte_]);
            if(updateColumn){emitter_.column_ += endChar_ - startChar_;}
            updateRangeStart();
        }

        ///Write line breaks in the text range.
        void writeLineBreaks() @safe
        {
            foreach(const dchar br; text_[startByte_ .. endByte_])
            {
                if(br == '\n'){emitter_.writeLineBreak();}
                else
                {
                    char[4] brString;
                    const bytes = encode(brString, br);
                    emitter_.writeLineBreak(brString[0 .. bytes]);
                }
            }
            updateRangeStart();
        }

        ///Write line break if start of the text range is a newline.
        void writeStartLineBreak() @safe
        {
            if(charAtStart == '\n'){emitter_.writeLineBreak();}
        }

        ///Write indentation, optionally resetting whitespace/indentation flags.
        void writeIndent(const Flag!"ResetSpace" resetSpace) @safe
        {
            emitter_.writeIndent();
            if(resetSpace)
            {
                emitter_.whitespace_ = emitter_.indentation_ = false;
            }
        }

        ///Move start of text range to its end.
        void updateRangeStart() pure @safe nothrow
        {
            startByte_ = endByte_;
            startChar_ = endChar_;
        }

        ///Update the line breaks_ flag, optionally updating the spaces_ flag.
        void updateBreaks(in dchar c, const Flag!"UpdateSpaces" updateSpaces) pure @safe
        {
            if(c == dcharNone){return;}
            breaks_ = (c.isNewLine != 0);
            if(updateSpaces){spaces_ = c == ' ';}
        }

        ///Move to the beginning of text.
        void resetTextPosition() pure @safe nothrow
        {
            startByte_ = endByte_ = nextEndByte_ = 0;
            startChar_ = endChar_ = -1;
        }
}
