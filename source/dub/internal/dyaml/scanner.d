
//          Copyright Ferdinand Majerech 2011-2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// YAML scanner.
/// Code based on PyYAML: http://www.pyyaml.org
module dub.internal.dyaml.scanner;


import core.stdc.string;

import std.algorithm;
import std.array;
import std.conv;
import std.ascii : isAlphaNum, isDigit, isHexDigit;
import std.exception;
import std.string;
import std.typecons;
import std.traits : Unqual;
import std.utf;

import dub.internal.dyaml.escapes;
import dub.internal.dyaml.exception;
import dub.internal.dyaml.queue;
import dub.internal.dyaml.reader;
import dub.internal.dyaml.style;
import dub.internal.dyaml.token;

package:
/// Scanner produces tokens of the following types:
/// STREAM-START
/// STREAM-END
/// DIRECTIVE(name, value)
/// DOCUMENT-START
/// DOCUMENT-END
/// BLOCK-SEQUENCE-START
/// BLOCK-MAPPING-START
/// BLOCK-END
/// FLOW-SEQUENCE-START
/// FLOW-MAPPING-START
/// FLOW-SEQUENCE-END
/// FLOW-MAPPING-END
/// BLOCK-ENTRY
/// FLOW-ENTRY
/// KEY
/// VALUE
/// ALIAS(value)
/// ANCHOR(value)
/// TAG(value)
/// SCALAR(value, plain, style)

alias isBreak = among!('\0', '\n', '\r', '\u0085', '\u2028', '\u2029');

alias isBreakOrSpace = among!(' ', '\0', '\n', '\r', '\u0085', '\u2028', '\u2029');

alias isWhiteSpace = among!(' ', '\t', '\0', '\n', '\r', '\u0085', '\u2028', '\u2029');

alias isNonLinebreakWhitespace = among!(' ', '\t');

alias isNonScalarStartCharacter = among!('-', '?', ':', ',', '[', ']', '{', '}',
    '#', '&', '*', '!', '|', '>', '\'', '"', '%', '@', '`', ' ', '\t', '\0', '\n',
    '\r', '\u0085', '\u2028', '\u2029');

alias isURIChar = among!('-', ';', '/', '?', ':', '@', '&', '=', '+', '$', ',',
    '_', '.', '!', '~', '*', '\'', '(', ')', '[', ']', '%');

alias isNSChar = among!(' ', '\n', '\r', '\u0085', '\u2028', '\u2029');

alias isBChar = among!('\n', '\r', '\u0085', '\u2028', '\u2029');

alias isFlowScalarBreakSpace = among!(' ', '\t', '\0', '\n', '\r', '\u0085', '\u2028', '\u2029', '\'', '"', '\\');

alias isNSAnchorName = c => !c.isWhiteSpace && !c.among!('[', ']', '{', '}', ',', '\uFEFF');

/// Generates tokens from data provided by a Reader.
struct Scanner
{
    private:
        /// A simple key is a key that is not denoted by the '?' indicator.
        /// For example:
        ///   ---
        ///   block simple key: value
        ///   ? not a simple key:
        ///   : { flow simple key: value }
        /// We emit the KEY token before all keys, so when we find a potential simple
        /// key, we try to locate the corresponding ':' indicator. Simple keys should be
        /// limited to a single line and 1024 characters.
        static struct SimpleKey
        {
            /// Position of the key
            Mark mark;
            /// Index of the key token from start (first token scanned being 0).
            uint tokenIndex;
            /// Is this required to be a simple key?
            bool required;
            /// Is this struct "null" (invalid)?.
            bool isNull;
        }

        /// Block chomping types.
        enum Chomping
        {
            /// Strip all trailing line breaks. '-' indicator.
            strip,
            /// Line break of the last line is preserved, others discarded. Default.
            clip,
            /// All trailing line breaks are preserved. '+' indicator.
            keep
        }

        /// Reader used to read from a file/stream.
        Reader reader_;
        /// Are we done scanning?
        bool done_;

        /// Level of nesting in flow context. If 0, we're in block context.
        uint flowLevel_;
        /// Current indentation level.
        int indent_ = -1;
        /// Past indentation levels. Used as a stack.
        Appender!(int[]) indents_;

        /// Processed tokens not yet emitted. Used as a queue.
        Queue!Token tokens_;

        /// Number of tokens emitted through the getToken method.
        uint tokensTaken_;

        /// Can a simple key start at the current position? A simple key may start:
        /// - at the beginning of the line, not counting indentation spaces
        ///       (in block context),
        /// - after '{', '[', ',' (in the flow context),
        /// - after '?', ':', '-' (in the block context).
        /// In the block context, this flag also signifies if a block collection
        /// may start at the current position.
        bool allowSimpleKey_ = true;

        /// Possible simple keys indexed by flow levels.
        SimpleKey[] possibleSimpleKeys_;

    public:
        /// Construct a Scanner using specified Reader.
        this(Reader reader) @safe nothrow
        {
            // Return the next token, but do not delete it from the queue
            reader_   = reader;
            fetchStreamStart();
        }

        /// Advance to the next token
        void popFront() @safe
        {
            ++tokensTaken_;
            tokens_.pop();
        }

        /// Return the current token
        const(Token) front() @safe
        {
            enforce(!empty, "No token left to peek");
            return tokens_.peek();
        }

        /// Return whether there are any more tokens left.
        bool empty() @safe
        {
            while (needMoreTokens())
            {
                fetchToken();
            }
            return tokens_.empty;
        }

        /// Set file name.
        ref inout(string) name() inout @safe return pure nothrow @nogc
        {
            return reader_.name;
        }
        /// Get a mark from the current reader position
        Mark mark() const @safe pure nothrow @nogc
        {
            return reader_.mark;
        }

    private:
        /// Most scanning error messages have the same format; so build them with this
        /// function.
        string expected(T)(string expected, T found)
        {
            return text(expected, ", but found ", found);
        }

        /// Determine whether or not we need to fetch more tokens before peeking/getting a token.
        bool needMoreTokens() @safe pure
        {
            if(done_)         { return false; }
            if(tokens_.empty) { return true; }

            /// The current token may be a potential simple key, so we need to look further.
            stalePossibleSimpleKeys();
            return nextPossibleSimpleKey() == tokensTaken_;
        }

        /// Fetch at token, adding it to tokens_.
        void fetchToken() @safe
        {
            // Eat whitespaces and comments until we reach the next token.
            scanToNextToken();

            // Remove obsolete possible simple keys.
            stalePossibleSimpleKeys();

            // Compare current indentation and column. It may add some tokens
            // and decrease the current indentation level.
            unwindIndent(reader_.column);

            // Get the next character.
            const dchar c = reader_.peekByte();

            // Fetch the token.
            if(c == '\0')            { return fetchStreamEnd();     }
            if(checkDirective())     { return fetchDirective();     }
            if(checkDocumentStart()) { return fetchDocumentStart(); }
            if(checkDocumentEnd())   { return fetchDocumentEnd();   }
            // Order of the following checks is NOT significant.
            switch(c)
            {
                case '[':  return fetchFlowSequenceStart();
                case '{':  return fetchFlowMappingStart();
                case ']':  return fetchFlowSequenceEnd();
                case '}':  return fetchFlowMappingEnd();
                case ',':  return fetchFlowEntry();
                case '!':  return fetchTag();
                case '\'': return fetchSingle();
                case '\"': return fetchDouble();
                case '*':  return fetchAlias();
                case '&':  return fetchAnchor();
                case '?':  if(checkKey())        { return fetchKey();        } goto default;
                case ':':  if(checkValue())      { return fetchValue();      } goto default;
                case '-':  if(checkBlockEntry()) { return fetchBlockEntry(); } goto default;
                case '|':  if(flowLevel_ == 0)   { return fetchLiteral();    } break;
                case '>':  if(flowLevel_ == 0)   { return fetchFolded();     } break;
                default:   if(checkPlain())      { return fetchPlain();      }
            }

            throw new ScannerException("While scanning for the next token, found character " ~
                                       "\'%s\', index %s that cannot start any token"
                                       .format(c, to!int(c)), reader_.mark);
        }


        /// Return the token number of the nearest possible simple key.
        uint nextPossibleSimpleKey() @safe pure nothrow @nogc
        {
            uint minTokenNumber = uint.max;
            foreach(k, ref simpleKey; possibleSimpleKeys_)
            {
                if(simpleKey.isNull) { continue; }
                minTokenNumber = min(minTokenNumber, simpleKey.tokenIndex);
            }
            return minTokenNumber;
        }

        /// Remove entries that are no longer possible simple keys.
        ///
        /// According to the YAML specification, simple keys
        /// - should be limited to a single line,
        /// - should be no longer than 1024 characters.
        /// Disabling this will allow simple keys of any length and
        /// height (may cause problems if indentation is broken though).
        void stalePossibleSimpleKeys() @safe pure
        {
            foreach(level, ref key; possibleSimpleKeys_)
            {
                if(key.isNull) { continue; }
                if(key.mark.line != reader_.mark.line || reader_.mark.column - key.mark.column > 1024)
                {
                    enforce(!key.required,
                        new ScannerException("While scanning a simple key, could not find expected ':'",
                            reader_.mark, "key started here", key.mark));
                    key.isNull = true;
                }
            }
        }

        /// Check if the next token starts a possible simple key and if so, save its position.
        ///
        /// This function is called for ALIAS, ANCHOR, TAG, SCALAR(flow), '[', and '{'.
        void savePossibleSimpleKey() @safe pure
        {
            // Check if a simple key is required at the current position.
            const required = (flowLevel_ == 0 && indent_ == reader_.column);
            assert(allowSimpleKey_ || !required, "A simple key is required only if it is " ~
                   "the first token in the current line. Therefore it is always allowed.");

            if(!allowSimpleKey_) { return; }

            // The next token might be a simple key, so save its number and position.
            removePossibleSimpleKey();
            const tokenCount = tokensTaken_ + cast(uint)tokens_.length;

            const line = reader_.line;
            const column = reader_.column;
            const key = SimpleKey(reader_.mark, tokenCount, required);

            if(possibleSimpleKeys_.length <= flowLevel_)
            {
                const oldLength = possibleSimpleKeys_.length;
                possibleSimpleKeys_.length = flowLevel_ + 1;
                // Make sure all the empty keys are null
                foreach (ref emptyKey; possibleSimpleKeys_[oldLength .. flowLevel_])
                {
                    emptyKey.isNull = true;
                }
            }
            possibleSimpleKeys_[flowLevel_] = key;
        }

        /// Remove the saved possible key position at the current flow level.
        void removePossibleSimpleKey() @safe pure
        {
            if(possibleSimpleKeys_.length <= flowLevel_) { return; }

            if(!possibleSimpleKeys_[flowLevel_].isNull)
            {
                const key = possibleSimpleKeys_[flowLevel_];
                enforce(!key.required,
                    new ScannerException("While scanning a simple key, could not find expected ':'",
                         reader_.mark, "key started here", key.mark));
                possibleSimpleKeys_[flowLevel_].isNull = true;
            }
        }

        /// Decrease indentation, removing entries in indents_.
        ///
        /// Params:  column = Current column in the file/stream.
        void unwindIndent(const int column) @safe
        {
            if(flowLevel_ > 0)
            {
                // In flow context, tokens should respect indentation.
                // The condition should be `indent >= column` according to the spec.
                // But this condition will prohibit intuitively correct
                // constructions such as
                // key : {
                // }

                // In the flow context, indentation is ignored. We make the scanner less
                // restrictive than what the specification requires.
                // if(pedantic_ && flowLevel_ > 0 && indent_ > column)
                // {
                //     throw new ScannerException("Invalid intendation or unclosed '[' or '{'",
                //                                reader_.mark)
                // }
                return;
            }

            // In block context, we may need to issue the BLOCK-END tokens.
            while(indent_ > column)
            {
                indent_ = indents_.data.back;
                assert(indents_.data.length);
                indents_.shrinkTo(indents_.data.length - 1);
                tokens_.push(blockEndToken(reader_.mark, reader_.mark));
            }
        }

        /// Increase indentation if needed.
        ///
        /// Params:  column = Current column in the file/stream.
        ///
        /// Returns: true if the indentation was increased, false otherwise.
        bool addIndent(int column) @safe
        {
            if(indent_ >= column){return false;}
            indents_ ~= indent_;
            indent_ = column;
            return true;
        }


        /// Add STREAM-START token.
        void fetchStreamStart() @safe nothrow
        {
            tokens_.push(streamStartToken(reader_.mark, reader_.mark, reader_.encoding));
        }

        ///Add STREAM-END token.
        void fetchStreamEnd() @safe
        {
            //Set intendation to -1 .
            unwindIndent(-1);
            removePossibleSimpleKey();
            allowSimpleKey_ = false;
            possibleSimpleKeys_.destroy;

            tokens_.push(streamEndToken(reader_.mark, reader_.mark));
            done_ = true;
        }

        /// Add DIRECTIVE token.
        void fetchDirective() @safe
        {
            // Set intendation to -1 .
            unwindIndent(-1);
            // Reset simple keys.
            removePossibleSimpleKey();
            allowSimpleKey_ = false;

            auto directive = scanDirective();
            tokens_.push(directive);
        }

        /// Add DOCUMENT-START or DOCUMENT-END token.
        void fetchDocumentIndicator(TokenID id)()
            if(id == TokenID.documentStart || id == TokenID.documentEnd)
        {
            // Set indentation to -1 .
            unwindIndent(-1);
            // Reset simple keys. Note that there can't be a block collection after '---'.
            removePossibleSimpleKey();
            allowSimpleKey_ = false;

            Mark startMark = reader_.mark;
            reader_.forward(3);
            tokens_.push(simpleToken!id(startMark, reader_.mark));
        }

        /// Aliases to add DOCUMENT-START or DOCUMENT-END token.
        alias fetchDocumentStart = fetchDocumentIndicator!(TokenID.documentStart);
        alias fetchDocumentEnd = fetchDocumentIndicator!(TokenID.documentEnd);

        /// Add FLOW-SEQUENCE-START or FLOW-MAPPING-START token.
        void fetchFlowCollectionStart(TokenID id)() @safe
        {
            // '[' and '{' may start a simple key.
            savePossibleSimpleKey();
            // Simple keys are allowed after '[' and '{'.
            allowSimpleKey_ = true;
            ++flowLevel_;

            Mark startMark = reader_.mark;
            reader_.forward();
            tokens_.push(simpleToken!id(startMark, reader_.mark));
        }

        /// Aliases to add FLOW-SEQUENCE-START or FLOW-MAPPING-START token.
        alias fetchFlowSequenceStart = fetchFlowCollectionStart!(TokenID.flowSequenceStart);
        alias fetchFlowMappingStart = fetchFlowCollectionStart!(TokenID.flowMappingStart);

        /// Add FLOW-SEQUENCE-START or FLOW-MAPPING-START token.
        void fetchFlowCollectionEnd(TokenID id)()
        {
            // Reset possible simple key on the current level.
            removePossibleSimpleKey();
            // No simple keys after ']' and '}'.
            allowSimpleKey_ = false;
            --flowLevel_;

            Mark startMark = reader_.mark;
            reader_.forward();
            tokens_.push(simpleToken!id(startMark, reader_.mark));
        }

        /// Aliases to add FLOW-SEQUENCE-START or FLOW-MAPPING-START token/
        alias fetchFlowSequenceEnd = fetchFlowCollectionEnd!(TokenID.flowSequenceEnd);
        alias fetchFlowMappingEnd = fetchFlowCollectionEnd!(TokenID.flowMappingEnd);

        /// Add FLOW-ENTRY token;
        void fetchFlowEntry() @safe
        {
            // Reset possible simple key on the current level.
            removePossibleSimpleKey();
            // Simple keys are allowed after ','.
            allowSimpleKey_ = true;

            Mark startMark = reader_.mark;
            reader_.forward();
            tokens_.push(flowEntryToken(startMark, reader_.mark));
        }

        /// Additional checks used in block context in fetchBlockEntry and fetchKey.
        ///
        /// Params:  type = String representing the token type we might need to add.
        ///          id   = Token type we might need to add.
        void blockChecks(string type, TokenID id)()
        {
            enum context = type ~ " keys are not allowed here";
            // Are we allowed to start a key (not neccesarily a simple one)?
            enforce(allowSimpleKey_, new ScannerException(context, reader_.mark));

            if(addIndent(reader_.column))
            {
                tokens_.push(simpleToken!id(reader_.mark, reader_.mark));
            }
        }

        /// Add BLOCK-ENTRY token. Might add BLOCK-SEQUENCE-START in the process.
        void fetchBlockEntry() @safe
        {
            if(flowLevel_ == 0) { blockChecks!("Sequence", TokenID.blockSequenceStart)(); }

            // It's an error for the block entry to occur in the flow context,
            // but we let the parser detect this.

            // Reset possible simple key on the current level.
            removePossibleSimpleKey();
            // Simple keys are allowed after '-'.
            allowSimpleKey_ = true;

            Mark startMark = reader_.mark;
            reader_.forward();
            tokens_.push(blockEntryToken(startMark, reader_.mark));
        }

        /// Add KEY token. Might add BLOCK-MAPPING-START in the process.
        void fetchKey() @safe
        {
            if(flowLevel_ == 0) { blockChecks!("Mapping", TokenID.blockMappingStart)(); }

            // Reset possible simple key on the current level.
            removePossibleSimpleKey();
            // Simple keys are allowed after '?' in the block context.
            allowSimpleKey_ = (flowLevel_ == 0);

            Mark startMark = reader_.mark;
            reader_.forward();
            tokens_.push(keyToken(startMark, reader_.mark));
        }

        /// Add VALUE token. Might add KEY and/or BLOCK-MAPPING-START in the process.
        void fetchValue() @safe
        {
            //Do we determine a simple key?
            if(possibleSimpleKeys_.length > flowLevel_ &&
               !possibleSimpleKeys_[flowLevel_].isNull)
            {
                const key = possibleSimpleKeys_[flowLevel_];
                assert(key.tokenIndex >= tokensTaken_);

                possibleSimpleKeys_[flowLevel_].isNull = true;
                Mark keyMark = key.mark;
                const idx = key.tokenIndex - tokensTaken_;

                // Add KEY.
                // Manually inserting since tokens are immutable (need linked list).
                tokens_.insert(keyToken(keyMark, keyMark), idx);

                // If this key starts a new block mapping, we need to add BLOCK-MAPPING-START.
                if(flowLevel_ == 0 && addIndent(key.mark.column))
                {
                    tokens_.insert(blockMappingStartToken(keyMark, keyMark), idx);
                }

                // There cannot be two simple keys in a row.
                allowSimpleKey_ = false;
            }
            // Part of a complex key
            else
            {
                // We can start a complex value if and only if we can start a simple key.
                enforce(flowLevel_ > 0 || allowSimpleKey_,
                        new ScannerException("Mapping values are not allowed here", reader_.mark));

                // If this value starts a new block mapping, we need to add
                // BLOCK-MAPPING-START. It'll be detected as an error later by the parser.
                if(flowLevel_ == 0 && addIndent(reader_.column))
                {
                    tokens_.push(blockMappingStartToken(reader_.mark, reader_.mark));
                }

                // Reset possible simple key on the current level.
                removePossibleSimpleKey();
                // Simple keys are allowed after ':' in the block context.
                allowSimpleKey_ = (flowLevel_ == 0);
            }

            // Add VALUE.
            Mark startMark = reader_.mark;
            reader_.forward();
            tokens_.push(valueToken(startMark, reader_.mark));
        }

        /// Add ALIAS or ANCHOR token.
        void fetchAnchor_(TokenID id)() @safe
            if(id == TokenID.alias_ || id == TokenID.anchor)
        {
            // ALIAS/ANCHOR could be a simple key.
            savePossibleSimpleKey();
            // No simple keys after ALIAS/ANCHOR.
            allowSimpleKey_ = false;

            auto anchor = scanAnchor(id);
            tokens_.push(anchor);
        }

        /// Aliases to add ALIAS or ANCHOR token.
        alias fetchAlias = fetchAnchor_!(TokenID.alias_);
        alias fetchAnchor = fetchAnchor_!(TokenID.anchor);

        /// Add TAG token.
        void fetchTag() @safe
        {
            //TAG could start a simple key.
            savePossibleSimpleKey();
            //No simple keys after TAG.
            allowSimpleKey_ = false;

            tokens_.push(scanTag());
        }

        /// Add block SCALAR token.
        void fetchBlockScalar(ScalarStyle style)() @safe
            if(style == ScalarStyle.literal || style == ScalarStyle.folded)
        {
            // Reset possible simple key on the current level.
            removePossibleSimpleKey();
            // A simple key may follow a block scalar.
            allowSimpleKey_ = true;

            auto blockScalar = scanBlockScalar(style);
            tokens_.push(blockScalar);
        }

        /// Aliases to add literal or folded block scalar.
        alias fetchLiteral = fetchBlockScalar!(ScalarStyle.literal);
        alias fetchFolded = fetchBlockScalar!(ScalarStyle.folded);

        /// Add quoted flow SCALAR token.
        void fetchFlowScalar(ScalarStyle quotes)()
        {
            // A flow scalar could be a simple key.
            savePossibleSimpleKey();
            // No simple keys after flow scalars.
            allowSimpleKey_ = false;

            // Scan and add SCALAR.
            auto scalar = scanFlowScalar(quotes);
            tokens_.push(scalar);
        }

        /// Aliases to add single or double quoted block scalar.
        alias fetchSingle = fetchFlowScalar!(ScalarStyle.singleQuoted);
        alias fetchDouble = fetchFlowScalar!(ScalarStyle.doubleQuoted);

        /// Add plain SCALAR token.
        void fetchPlain() @safe
        {
            // A plain scalar could be a simple key
            savePossibleSimpleKey();
            // No simple keys after plain scalars. But note that scanPlain() will
            // change this flag if the scan is finished at the beginning of the line.
            allowSimpleKey_ = false;
            auto plain = scanPlain();

            // Scan and add SCALAR. May change allowSimpleKey_
            tokens_.push(plain);
        }

    pure:

        ///Check if the next token is DIRECTIVE:        ^ '%' ...
        bool checkDirective() @safe
        {
            return reader_.peekByte() == '%' && reader_.column == 0;
        }

        /// Check if the next token is DOCUMENT-START:   ^ '---' (' '|'\n')
        bool checkDocumentStart() @safe
        {
            // Check one char first, then all 3, to prevent reading outside the buffer.
            return reader_.column     == 0     &&
                   reader_.peekByte() == '-'   &&
                   reader_.prefix(3)  == "---" &&
                   reader_.peek(3).isWhiteSpace;
        }

        /// Check if the next token is DOCUMENT-END:     ^ '...' (' '|'\n')
        bool checkDocumentEnd() @safe
        {
            // Check one char first, then all 3, to prevent reading outside the buffer.
            return reader_.column     == 0     &&
                   reader_.peekByte() == '.'   &&
                   reader_.prefix(3)  == "..." &&
                   reader_.peek(3).isWhiteSpace;
        }

        /// Check if the next token is BLOCK-ENTRY:      '-' (' '|'\n')
        bool checkBlockEntry() @safe
        {
            return !!reader_.peek(1).isWhiteSpace;
        }

        /// Check if the next token is KEY(flow context):    '?'
        ///
        /// or KEY(block context):   '?' (' '|'\n')
        bool checkKey() @safe
        {
            return (flowLevel_ > 0 || reader_.peek(1).isWhiteSpace);
        }

        /// Check if the next token is VALUE(flow context):  ':'
        ///
        /// or VALUE(block context): ':' (' '|'\n')
        bool checkValue() @safe
        {
            return flowLevel_ > 0 || reader_.peek(1).isWhiteSpace;
        }

        /// Check if the next token is a plain scalar.
        ///
        /// A plain scalar may start with any non-space character except:
        ///   '-', '?', ':', ',', '[', ']', '{', '}',
        ///   '#', '&', '*', '!', '|', '>', '\'', '\"',
        ///   '%', '@', '`'.
        ///
        /// It may also start with
        ///   '-', '?', ':'
        /// if it is followed by a non-space character.
        ///
        /// Note that we limit the last rule to the block context (except the
        /// '-' character) because we want the flow context to be space
        /// independent.
        bool checkPlain() @safe
        {
            const c = reader_.peek();
            if(!c.isNonScalarStartCharacter)
            {
                return true;
            }
            return !reader_.peek(1).isWhiteSpace &&
                   (c == '-' || (flowLevel_ == 0 && (c == '?' || c == ':')));
        }

        /// Move to the next non-space character.
        void findNextNonSpace() @safe
        {
            while(reader_.peekByte() == ' ') { reader_.forward(); }
        }

        /// Scan a string of alphanumeric or "-_" characters.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        void scanAlphaNumericToSlice(string name)(ref char[] slice, const Mark startMark)
        {
            size_t length;
            dchar c = reader_.peek();
            while(c.isAlphaNum || c.among!('-', '_')) { c = reader_.peek(++length); }

            enforce(length > 0, new ScannerException(expected("While scanning a " ~ name ~ ", expected alphanumeric, '-' or '_'", c),
                reader_.mark, name~" started here", startMark));

            slice ~= reader_.get(length);
        }

        /// Scan a string.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        char[] readAnchorAlias(const Mark startMark) @safe
        {
            size_t length;
            dchar c = reader_.peek();
            while (c.isNSAnchorName)
            {
                c = reader_.peek(++length);
            }

            enforce(length > 0, new ScannerException(
                expected("While scanning an anchor or alias, expected a printable character besides '[', ']', '{', '}' and ','", c),
                reader_.mark, "started here", startMark));

            return reader_.get(length);
        }

        /// Scan and throw away all characters until next line break.
        void scanToNextBreak() @safe
        {
            while(!reader_.peek().isBreak) { reader_.forward(); }
        }

        /// Scan all characters until next line break.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        void scanToNextBreakToSlice(ref char[] slice) @safe
        {
            uint length;
            while(!reader_.peek(length).isBreak)
            {
                ++length;
            }
            slice ~= reader_.get(length);
        }


        /// Move to next token in the file/stream.
        ///
        /// We ignore spaces, line breaks and comments.
        /// If we find a line break in the block context, we set
        /// allowSimpleKey` on.
        ///
        /// We do not yet support BOM inside the stream as the
        /// specification requires. Any such mark will be considered as a part
        /// of the document.
        void scanToNextToken() @safe
        {
            // TODO(PyYAML): We need to make tab handling rules more sane. A good rule is:
            //   Tabs cannot precede tokens
            //   BLOCK-SEQUENCE-START, BLOCK-MAPPING-START, BLOCK-END,
            //   KEY(block), VALUE(block), BLOCK-ENTRY
            // So the checking code is
            //   if <TAB>:
            //       allowSimpleKey_ = false
            // We also need to add the check for `allowSimpleKey_ == true` to
            // `unwindIndent` before issuing BLOCK-END.
            // Scanners for block, flow, and plain scalars need to be modified.

            for(;;)
            {
                //All whitespace in flow context is ignored, even whitespace
                // not allowed in other contexts
                if (flowLevel_ > 0)
                {
                    while(reader_.peekByte().isNonLinebreakWhitespace) { reader_.forward(); }
                }
                else
                {
                    findNextNonSpace();
                }
                if(reader_.peekByte() == '#') { scanToNextBreak(); }
                if(scanLineBreak() != '\0')
                {
                    if(flowLevel_ == 0) { allowSimpleKey_ = true; }
                }
                else
                {
                    break;
                }
            }
        }

        /// Scan directive token.
        Token scanDirective() @safe
        {
            Mark startMark = reader_.mark;
            // Skip the '%'.
            reader_.forward();

            // Scan directive name
            char[] name;
            scanDirectiveNameToSlice(name, startMark);

            char[] value;

            // Index where tag handle ends and suffix starts in a tag directive value.
            uint tagHandleEnd = uint.max;
            if(name == "YAML")     { scanYAMLDirectiveValueToSlice(value, startMark); }
            else if(name == "TAG") { tagHandleEnd = scanTagDirectiveValueToSlice(value, startMark); }

            Mark endMark = reader_.mark;

            DirectiveType directive;
            if(name == "YAML")     { directive = DirectiveType.yaml; }
            else if(name == "TAG") { directive = DirectiveType.tag; }
            else
            {
                directive = DirectiveType.reserved;
                scanToNextBreak();
            }

            scanDirectiveIgnoredLine(startMark);

            return directiveToken(startMark, endMark, value, directive, tagHandleEnd);
        }

        /// Scan name of a directive token.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        void scanDirectiveNameToSlice(ref char[] slice, const Mark startMark) @safe
        {
            // Scan directive name.
            scanAlphaNumericToSlice!"directive"(slice, startMark);

            enforce(reader_.peek().among!(' ', '\0', '\n', '\r', '\u0085', '\u2028', '\u2029'),
                new ScannerException(expected("While scanning a directive, expected alphanumeric, '-' or '_'", reader_.peek()),
                    reader_.mark, "directive started here", startMark));
        }

        /// Scan value of a YAML directive token. Returns major, minor version separated by '.'.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        void scanYAMLDirectiveValueToSlice(ref char[] slice, const Mark startMark) @safe
        {
            findNextNonSpace();

            scanYAMLDirectiveNumberToSlice(slice, startMark);

            enforce(reader_.peekByte() == '.',
                new ScannerException(expected("While scanning a directive, expected digit or '.'", reader_.peek()),
                    reader_.mark, "directive started here", startMark));
            // Skip the '.'.
            reader_.forward();

            slice ~= '.';
            scanYAMLDirectiveNumberToSlice(slice, startMark);

            enforce(reader_.peek().among!(' ', '\0', '\n', '\r', '\u0085', '\u2028', '\u2029'),
                new ScannerException(expected("While scanning a directive, expected digit or '.'", reader_.peek()),
                    reader_.mark, "directive started here", startMark));
        }

        /// Scan a number from a YAML directive.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        void scanYAMLDirectiveNumberToSlice(ref char[] slice, const Mark startMark) @safe
        {
            enforce(isDigit(reader_.peek()),
                new ScannerException(expected("While scanning a directive, expected a digit", reader_.peek()),
                    reader_.mark, "directive started here", startMark));

            // Already found the first digit in the enforce(), so set length to 1.
            uint length = 1;
            while(reader_.peek(length).isDigit) { ++length; }

            slice ~= reader_.get(length);
        }

        /// Scan value of a tag directive.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        ///
        /// Returns: Length of tag handle (which is before tag prefix) in scanned data
        uint scanTagDirectiveValueToSlice(ref char[] slice, const Mark startMark) @safe
        {
            findNextNonSpace();
            const startLength = slice.length;
            scanTagDirectiveHandleToSlice(slice, startMark);
            const handleLength = cast(uint)(slice.length  - startLength);
            findNextNonSpace();
            scanTagDirectivePrefixToSlice(slice, startMark);

            return handleLength;
        }

        /// Scan handle of a tag directive.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        void scanTagDirectiveHandleToSlice(ref char[] slice, const Mark startMark) @safe
        {
            scanTagHandleToSlice!"directive"(slice, startMark);
            enforce(reader_.peekByte() == ' ',
                new ScannerException(expected("While scanning a directive handle, expected ' '", reader_.peek()),
                    reader_.mark, "directive started here", startMark));
        }

        /// Scan prefix of a tag directive.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        void scanTagDirectivePrefixToSlice(ref char[] slice, const Mark startMark) @safe
        {
            scanTagURIToSlice!"directive"(slice, startMark);
            enforce(reader_.peek().among!(' ', '\0', '\n', '\r', '\u0085', '\u2028', '\u2029'),
                new ScannerException(expected("While scanning a directive prefix, expected ' '", reader_.peek()),
                    reader_.mark, "directive started here", startMark));
        }

        /// Scan (and ignore) ignored line after a directive.
        void scanDirectiveIgnoredLine(const Mark startMark) @safe
        {
            findNextNonSpace();
            if(reader_.peekByte() == '#') { scanToNextBreak(); }
            enforce(reader_.peek().isBreak,
                new ScannerException(expected("While scanning a directive, expected a comment or a line break", reader_.peek()),
                    reader_.mark, "directive started here", startMark));
            scanLineBreak();
        }


        /// Scan an alias or an anchor.
        ///
        /// The specification does not restrict characters for anchors and
        /// aliases. This may lead to problems, for instance, the document:
        ///   [ *alias, value ]
        /// can be interpteted in two ways, as
        ///   [ "value" ]
        /// and
        ///   [ *alias , "value" ]
        /// Therefore we restrict aliases to ASCII alphanumeric characters.
        Token scanAnchor(const TokenID id) @safe
        {
            const startMark = reader_.mark;
            reader_.forward(); // The */& character was only peeked, so we drop it now

            char[] value = readAnchorAlias(startMark);

            assert(!reader_.peek().isNSAnchorName, "Anchor/alias name not fully scanned");

            if(id == TokenID.alias_)
            {
                return aliasToken(startMark, reader_.mark, value);
            }
            if(id == TokenID.anchor)
            {
                return anchorToken(startMark, reader_.mark, value);
            }
            assert(false, "This code should never be reached");
        }

        /// Scan a tag token.
        Token scanTag() @safe
        {
            const startMark = reader_.mark;
            dchar c = reader_.peek(1);

            char[] slice;
            // Index where tag handle ends and tag suffix starts in the tag value
            // (slice) we will produce.
            uint handleEnd;

            if(c == '<')
            {
                reader_.forward(2);

                handleEnd = 0;
                scanTagURIToSlice!"tag"(slice, startMark);
                enforce(reader_.peekByte() == '>',
                    new ScannerException(expected("While scanning a tag, expected a '>'", reader_.peek()),
                        reader_.mark, "tag started here", startMark));
                reader_.forward();
            }
            else if(c.isWhiteSpace)
            {
                reader_.forward();
                handleEnd = 0;
                slice ~= '!';
            }
            else
            {
                uint length = 1;
                bool useHandle;

                while(!c.isBreakOrSpace)
                {
                    if(c == '!')
                    {
                        useHandle = true;
                        break;
                    }
                    ++length;
                    c = reader_.peek(length);
                }

                if(useHandle)
                {
                    scanTagHandleToSlice!"tag"(slice, startMark);
                    handleEnd = cast(uint)slice.length;
                }
                else
                {
                    reader_.forward();
                    slice ~= '!';
                    handleEnd = cast(uint)slice.length;
                }

                scanTagURIToSlice!"tag"(slice, startMark);
            }

            enforce(reader_.peek().isBreakOrSpace,
                new ScannerException(expected("While scanning a tag, expected a ' '", reader_.peek()),
                    reader_.mark, "tag started here", startMark));

            return tagToken(startMark, reader_.mark, slice, handleEnd);
        }

        /// Scan a block scalar token with specified style.
        Token scanBlockScalar(const ScalarStyle style) @safe
        {
            const startMark = reader_.mark;

            // Scan the header.
            reader_.forward();

            const indicators = scanBlockScalarIndicators(startMark);

            const chomping   = indicators[0];
            const increment  = indicators[1];
            scanBlockScalarIgnoredLine(startMark);

            // Determine the indentation level and go to the first non-empty line.
            Mark endMark;
            uint indent = max(1, indent_ + 1);

            char[] slice;
            // Used to strip the last line breaks written to the slice at the end of the
            // scalar, which may be needed based on chomping.
            char[] newBreakSlice;
            // Read the first indentation/line breaks before the scalar.
            size_t startLen = newBreakSlice.length;
            if(increment == int.min)
            {
                auto indentation = scanBlockScalarIndentationToSlice(newBreakSlice);
                endMark = indentation[1];
                indent  = max(indent, indentation[0]);
            }
            else
            {
                indent += increment - 1;
                endMark = scanBlockScalarBreaksToSlice(newBreakSlice, indent);
            }

            // int.max means there's no line break (int.max is outside UTF-32).
            dchar lineBreak = cast(dchar)int.max;

            // Scan the inner part of the block scalar.
            while(reader_.column == indent && reader_.peekByte() != '\0')
            {
                slice ~= newBreakSlice;
                const bool leadingNonSpace = !reader_.peekByte().among!(' ', '\t');
                // This is where the 'interesting' non-whitespace data gets read.
                scanToNextBreakToSlice(slice);
                lineBreak = scanLineBreak();


                // This transaction serves to rollback data read in the
                // scanBlockScalarBreaksToSlice() call.
                newBreakSlice = [];
                startLen = slice.length;
                // The line breaks should actually be written _after_ the if() block
                // below. We work around that by inserting
                endMark = scanBlockScalarBreaksToSlice(newBreakSlice, indent);

                // This will not run during the last iteration
                if(reader_.column == indent && reader_.peekByte() != '\0')
                {
                    // Unfortunately, folding rules are ambiguous.

                    // This is the folding according to the specification:
                    if(style == ScalarStyle.folded && lineBreak == '\n' &&
                       leadingNonSpace && !reader_.peekByte().among!(' ', '\t'))
                    {
                        // No breaks were scanned; no need to insert the space in the
                        // middle of slice.
                        if(startLen == slice.length + newBreakSlice.length)
                        {
                            newBreakSlice ~= ' ';
                        }
                    }
                    else
                    {
                        // We need to insert in the middle of the slice in case any line
                        // breaks were scanned.
                        newBreakSlice.insert(lineBreak, 0);
                    }

                    ////this is Clark Evans's interpretation (also in the spec
                    ////examples):
                    //
                    //if(style == ScalarStyle.folded && lineBreak == '\n')
                    //{
                    //    if(startLen == endLen)
                    //    {
                    //        if(!" \t"d.canFind(reader_.peekByte()))
                    //        {
                    //            reader_.sliceBuilder.write(' ');
                    //        }
                    //        else
                    //        {
                    //            chunks ~= lineBreak;
                    //        }
                    //    }
                    //}
                    //else
                    //{
                    //    reader_.sliceBuilder.insertBack(lineBreak, endLen - startLen);
                    //}
                }
                else
                {
                    break;
                }
            }

            // If chompint is Keep, we keep (commit) the last scanned line breaks
            // (which are at the end of the scalar). Otherwise re remove them (end the
            // transaction).
            if(chomping == Chomping.keep)  { slice ~= newBreakSlice; }
            if(chomping != Chomping.strip && lineBreak != int.max)
            {
                // If chomping is Keep, we keep the line break but the first line break
                // that isn't stripped (since chomping isn't Strip in this branch) must
                // be inserted _before_ the other line breaks.
                if(chomping == Chomping.keep)
                {
                    slice.insert(lineBreak, startLen);
                }
                // If chomping is not Keep, discard the line break
                else
                {
                    if (lineBreak != '\0')
                    {
                        slice ~= lineBreak;
                    }
                }
            }

            return scalarToken(startMark, endMark, slice, style);
        }

        /// Scan chomping and indentation indicators of a scalar token.
        Tuple!(Chomping, int) scanBlockScalarIndicators(const Mark startMark) @safe
        {
            auto chomping = Chomping.clip;
            int increment = int.min;
            dchar c       = reader_.peek();

            /// Indicators can be in any order.
            if(getChomping(c, chomping))
            {
                getIncrement(c, increment, startMark);
            }
            else
            {
                const gotIncrement = getIncrement(c, increment, startMark);
                if(gotIncrement) { getChomping(c, chomping); }
            }

            enforce(c.among!(' ', '\0', '\n', '\r', '\u0085', '\u2028', '\u2029'),
                new ScannerException(expected("While scanning a block scalar, expected a chomping or indentation indicator", c),
                    reader_.mark, "scalar started here", startMark));

            return tuple(chomping, increment);
        }

        /// Get chomping indicator, if detected. Return false otherwise.
        ///
        /// Used in scanBlockScalarIndicators.
        ///
        /// Params:
        ///
        /// c        = The character that may be a chomping indicator.
        /// chomping = Write the chomping value here, if detected.
        bool getChomping(ref dchar c, ref Chomping chomping) @safe
        {
            if(!c.among!('+', '-')) { return false; }
            chomping = c == '+' ? Chomping.keep : Chomping.strip;
            reader_.forward();
            c = reader_.peek();
            return true;
        }

        /// Get increment indicator, if detected. Return false otherwise.
        ///
        /// Used in scanBlockScalarIndicators.
        ///
        /// Params:
        ///
        /// c         = The character that may be an increment indicator.
        ///             If an increment indicator is detected, this will be updated to
        ///             the next character in the Reader.
        /// increment = Write the increment value here, if detected.
        /// startMark = Mark for error messages.
        bool getIncrement(ref dchar c, ref int increment, const Mark startMark) @safe
        {
            if(!c.isDigit) { return false; }
            // Convert a digit to integer.
            increment = c - '0';
            assert(increment < 10 && increment >= 0, "Digit has invalid value");

            enforce(increment > 0,
                new ScannerException(expected("While scanning a block scalar, expected an indentation indicator in range 1-9", "0"),
                    reader_.mark, "scalar started here", startMark));

            reader_.forward();
            c = reader_.peek();
            return true;
        }

        /// Scan (and ignore) ignored line in a block scalar.
        void scanBlockScalarIgnoredLine(const Mark startMark) @safe
        {
            findNextNonSpace();
            if(reader_.peekByte()== '#') { scanToNextBreak(); }

            enforce(reader_.peek().isBreak,
                new ScannerException(expected("While scanning a block scalar, expected a comment or line break", reader_.peek()),
                    reader_.mark, "scalar started here", startMark));

            scanLineBreak();
        }

        /// Scan indentation in a block scalar, returning line breaks, max indent and end mark.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        Tuple!(uint, Mark) scanBlockScalarIndentationToSlice(ref char[] slice) @safe
        {
            uint maxIndent;
            Mark endMark = reader_.mark;

            while(reader_.peek().among!(' ', '\n', '\r', '\u0085', '\u2028', '\u2029'))
            {
                if(reader_.peekByte() != ' ')
                {
                    slice ~= scanLineBreak();
                    endMark = reader_.mark;
                    continue;
                }
                reader_.forward();
                maxIndent = max(reader_.column, maxIndent);
            }

            return tuple(maxIndent, endMark);
        }

        /// Scan line breaks at lower or specified indentation in a block scalar.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        Mark scanBlockScalarBreaksToSlice(ref char[] slice, const uint indent) @safe
        {
            Mark endMark = reader_.mark;

            for(;;)
            {
                while(reader_.column < indent && reader_.peekByte() == ' ') { reader_.forward(); }
                if(!reader_.peek().among!('\n', '\r', '\u0085', '\u2028', '\u2029'))  { break; }
                slice ~= scanLineBreak();
                endMark = reader_.mark;
            }

            return endMark;
        }

        /// Scan a qouted flow scalar token with specified quotes.
        Token scanFlowScalar(const ScalarStyle quotes) @safe
        {
            const startMark = reader_.mark;
            const quote     = reader_.get();

            char[] slice;

            scanFlowScalarNonSpacesToSlice(slice, quotes, startMark);

            while(reader_.peek() != quote)
            {
                scanFlowScalarSpacesToSlice(slice, startMark);
                scanFlowScalarNonSpacesToSlice(slice, quotes, startMark);
            }
            reader_.forward();

            return scalarToken(startMark, reader_.mark, slice, quotes);
        }

        /// Scan nonspace characters in a flow scalar.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        void scanFlowScalarNonSpacesToSlice(ref char[] slice, const ScalarStyle quotes, const Mark startMark)
            @safe
        {
            for(;;)
            {
                dchar c = reader_.peek();

                size_t numCodePoints;
                while(!reader_.peek(numCodePoints).isFlowScalarBreakSpace) { ++numCodePoints; }

                if (numCodePoints > 0) { slice ~= reader_.get(numCodePoints); }

                c = reader_.peek();
                if(quotes == ScalarStyle.singleQuoted && c == '\'' && reader_.peek(1) == '\'')
                {
                    reader_.forward(2);
                    slice ~= '\'';
                }
                else if((quotes == ScalarStyle.doubleQuoted && c == '\'') ||
                        (quotes == ScalarStyle.singleQuoted && c.among!('"', '\\')))
                {
                    reader_.forward();
                    slice ~= c;
                }
                else if(quotes == ScalarStyle.doubleQuoted && c == '\\')
                {
                    reader_.forward();
                    c = reader_.peek();
                    if(c.among!(escapes))
                    {
                        reader_.forward();
                        // Escaping has been moved to Parser as it can't be done in
                        // place (in a slice) in case of '\P' and '\L' (very uncommon,
                        // but we don't want to break the spec)
                        char[2] escapeSequence = ['\\', cast(char)c];
                        slice ~= escapeSequence;
                    }
                    else if(c.among!(escapeHexCodeList))
                    {
                        const hexLength = dub.internal.dyaml.escapes.escapeHexLength(c);
                        reader_.forward();

                        foreach(i; 0 .. hexLength) {
                            enforce(reader_.peek(i).isHexDigit,
                                new ScannerException(expected("While scanning a double quoted scalar, expected an escape sequence of hexadecimal numbers", reader_.peek(i)),
                                    reader_.mark, "scalar started here", startMark));
                        }
                        char[] hex = reader_.get(hexLength);

                        assert((hex.length > 0) && (hex.length <= 8), "Hex escape overflow");

                        char[2] escapeStart = ['\\', cast(char) c];
                        slice ~= escapeStart;
                        slice ~= hex;

                    }
                    else if(c.among!('\n', '\r', '\u0085', '\u2028', '\u2029'))
                    {
                        scanLineBreak();
                        scanFlowScalarBreaksToSlice(slice, startMark);
                    }
                    else
                    {
                        throw new ScannerException(text("While scanning a double quoted scalar, found unsupported escape character ", c),
                            reader_.mark, "scalar started here", startMark);
                    }
                }
                else { return; }
            }
        }

        /// Scan space characters in a flow scalar.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// spaces into that slice.
        void scanFlowScalarSpacesToSlice(ref char[] slice, const Mark startMark) @safe
        {
            // Increase length as long as we see whitespace.
            size_t length;
            while(reader_.peekByte(length).among!(' ', '\t')) { ++length; }
            auto whitespaces = reader_.prefixBytes(length);

            // Can check the last byte without striding because '\0' is ASCII
            const c = reader_.peek(length);
            enforce(c != '\0',
                new ScannerException("While scanning a quoted scalar, found unexpected end of buffer",
                    reader_.mark, "scalar started here", startMark));

            // Spaces not followed by a line break.
            if(!c.among!('\n', '\r', '\u0085', '\u2028', '\u2029'))
            {
                reader_.forward(length);
                slice ~= whitespaces;
                return;
            }

            // There's a line break after the spaces.
            reader_.forward(length);
            const lineBreak = scanLineBreak();

            if(lineBreak != '\n') { slice ~= lineBreak; }

            // If we have extra line breaks after the first, scan them into the
            // slice.
            const bool extraBreaks = scanFlowScalarBreaksToSlice(slice, startMark);

            // No extra breaks, one normal line break. Replace it with a space.
            if(lineBreak == '\n' && !extraBreaks) { slice ~= ' '; }
        }

        /// Scan line breaks in a flow scalar.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// line breaks into that slice.
        bool scanFlowScalarBreaksToSlice(ref char[] slice, const Mark startMark) @safe
        {
            // True if at least one line break was found.
            bool anyBreaks;
            for(;;)
            {
                // Instead of checking indentation, we check for document separators.
                const prefix = reader_.prefix(3);
                enforce(!(prefix == "---" || prefix == "...") ||
                    !reader_.peek(3).isWhiteSpace,
                    new ScannerException("While scanning a quoted scalar, found unexpected document separator",
                        reader_.mark, "scalar started here", startMark));

                // Skip any whitespaces.
                while(reader_.peekByte().among!(' ', '\t')) { reader_.forward(); }

                // Encountered a non-whitespace non-linebreak character, so we're done.
                if(!reader_.peek().among!(' ', '\n', '\r', '\u0085', '\u2028', '\u2029')) { break; }

                const lineBreak = scanLineBreak();
                anyBreaks = true;
                slice ~= lineBreak;
            }
            return anyBreaks;
        }

        /// Scan plain scalar token (no block, no quotes).
        Token scanPlain() @safe
        {
            // We keep track of the allowSimpleKey_ flag here.
            // Indentation rules are loosed for the flow context
            const startMark = reader_.mark;
            Mark endMark = startMark;
            const indent = indent_ + 1;

            // We allow zero indentation for scalars, but then we need to check for
            // document separators at the beginning of the line.
            // if(indent == 0) { indent = 1; }

            char[] slice;

            char[] newSpacesSlice;
            // Stop at a comment.
            while(reader_.peekByte() != '#')
            {
                // Scan the entire plain scalar.
                size_t length;
                dchar c = reader_.peek(length);
                for(;;)
                {
                    const cNext = reader_.peek(length + 1);
                    if(c.isWhiteSpace ||
                       (flowLevel_ == 0 && c == ':' && cNext.isWhiteSpace) ||
                       (flowLevel_ > 0 && c == ':' && (cNext.isWhiteSpace || cNext.among!(',', '[', ']', '{', '}'))) ||
                       (flowLevel_ > 0 && c.among!(',', '[', ']', '{', '}')))
                    {
                        break;
                    }
                    ++length;
                    c = cNext;
                }

                if(length == 0) { break; }

                allowSimpleKey_ = false;

                newSpacesSlice ~= reader_.get(length);

                endMark = reader_.mark;

                slice ~= newSpacesSlice;
                newSpacesSlice = [];

                const startLength = slice.length;
                scanPlainSpacesToSlice(newSpacesSlice);
                if(startLength == slice.length + newSpacesSlice.length ||
                   (flowLevel_ == 0 && reader_.column < indent))
                {
                    break;
                }
            }

            return scalarToken(startMark, endMark, slice, ScalarStyle.plain);
        }

        /// Scan spaces in a plain scalar.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the spaces
        /// into that slice.
        void scanPlainSpacesToSlice(ref char[] slice) @trusted
        {
            // The specification is really confusing about tabs in plain scalars.
            // We just forbid them completely. Do not use tabs in YAML!

            // Get as many plain spaces as there are.
            size_t length;
            while(reader_.peekByte(length) == ' ') { ++length; }
            char[] whitespaces = reader_.prefixBytes(length);
            reader_.forward(length);

            const dchar c = reader_.peek();
            if(!c.isNSChar)
            {
                // We have spaces, but no newline.
                if(whitespaces.length > 0) { slice ~= whitespaces; }
                return;
            }

            // Newline after the spaces (if any)
            const lineBreak = scanLineBreak();
            allowSimpleKey_ = true;

            static bool end(Reader reader_) @safe pure
            {
                const prefix = reader_.prefix(3);
                return ("---" == prefix || "..." == prefix)
                        && reader_.peek(3).among!(' ', '\t', '\0', '\n', '\r', '\u0085', '\u2028', '\u2029');
            }

            if(end(reader_)) { return; }

            bool extraBreaks;

            char[] newSlice;
            if(lineBreak != '\n') { newSlice ~= lineBreak; }
            while(reader_.peek().isNSChar)
            {
                if(reader_.peekByte() == ' ') { reader_.forward(); }
                else
                {
                    const lBreak = scanLineBreak();
                    extraBreaks  = true;
                    newSlice ~= lBreak;

                    if(end(reader_)) { return; }
                }
            }
            slice ~= newSlice;

            // No line breaks, only a space.
            if(lineBreak == '\n' && !extraBreaks) { slice ~= ' '; }
        }

        /// Scan handle of a tag token.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        void scanTagHandleToSlice(string name)(ref char[] slice, const Mark startMark)
        {
            dchar c = reader_.peek();
            enum contextMsg = "While scanning a " ~ name ~ ", expected a !";
            // should this be an assert?
            enforce(c == '!',
                new ScannerException(expected(contextMsg, c), reader_.mark, "tag started here", startMark));

            uint length = 1;
            c = reader_.peek(length);
            if(c != ' ')
            {
                while(c.isAlphaNum || c.among!('-', '_'))
                {
                    ++length;
                    c = reader_.peek(length);
                }
                enforce(c == '!',
                    new ScannerException(expected(contextMsg, c), reader_.mark(length), "tag started here", startMark));
                ++length;
            }

            slice ~= reader_.get(length);
        }

        /// Scan URI in a tag token.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        void scanTagURIToSlice(string name)(ref char[] slice, const Mark startMark)
        {
            // Note: we do not check if URI is well-formed.
            dchar c = reader_.peek();
            const startLen = slice.length;
            {
                uint length;
                while(c.isAlphaNum || c.isURIChar)
                {
                    if(c == '%')
                    {
                        auto chars = reader_.get(length);
                        slice ~= chars;
                        length = 0;
                        scanURIEscapesToSlice!name(slice, startMark);
                    }
                    else { ++length; }
                    c = reader_.peek(length);
                }
                if(length > 0)
                {
                    auto chars = reader_.get(length);
                    slice ~= chars;
                    length = 0;
                }
            }
            // OK if we scanned something, error otherwise.
            enum contextMsg = "While parsing a " ~ name ~ ", expected a URI";
            enforce(slice.length > startLen,
                new ScannerException(expected(contextMsg, c), reader_.mark, "tag started here", startMark));
        }

        // Not @nogc yet because std.utf.decode is not @nogc
        /// Scan URI escape sequences.
        ///
        /// Assumes that the caller is building a slice in Reader, and puts the scanned
        /// characters into that slice.
        void scanURIEscapesToSlice(string name)(ref char[] slice, const Mark startMark)
        {
            import core.exception : UnicodeException;
            // URI escapes encode a UTF-8 string. We store UTF-8 code units here for
            // decoding into UTF-32.
            Appender!string buffer;


            enum contextMsg = "While scanning a " ~ name;
            while(reader_.peekByte() == '%')
            {
                reader_.forward();
                char[2] nextByte = [reader_.peekByte(), reader_.peekByte(1)];

                enforce(nextByte[0].isHexDigit && nextByte[1].isHexDigit,
                    new ScannerException(expected(contextMsg ~ ", expected a URI escape sequence of 2 hexadecimal numbers", nextByte),
                        reader_.mark, "tag started here", startMark));

                buffer ~= nextByte[].to!ubyte(16);

                reader_.forward(2);
            }
            try
            {
                foreach (dchar chr; buffer.data)
                {
                    slice ~= chr;
                }
            }
            catch (UnicodeException)
            {
                throw new ScannerException(contextMsg ~ ", found invalid UTF-8 data encoded in URI escape sequence",
                    reader_.mark, "tag started here", startMark);
            }
        }


        /// Scan a line break, if any.
        ///
        /// Transforms:
        ///   '\r\n'      :   '\n'
        ///   '\r'        :   '\n'
        ///   '\n'        :   '\n'
        ///   '\u0085'    :   '\n'
        ///   '\u2028'    :   '\u2028'
        ///   '\u2029     :   '\u2029'
        ///   no break    :   '\0'
        dchar scanLineBreak() @safe
        {
            // Fast path for ASCII line breaks.
            const b = reader_.peekByte();
            if(b < 0x80)
            {
                if(b == '\n' || b == '\r')
                {
                    if(reader_.prefix(2) == "\r\n") { reader_.forward(2); }
                    else { reader_.forward(); }
                    return '\n';
                }
                return '\0';
            }

            const c = reader_.peek();
            if(c == '\x85')
            {
                reader_.forward();
                return '\n';
            }
            if(c == '\u2028' || c == '\u2029')
            {
                reader_.forward();
                return c;
            }
            return '\0';
        }
}

// Issue 309 - https://github.com/dlang-community/D-YAML/issues/309
@safe unittest
{
    enum str = q"EOS
exp: |
  foobar
EOS".chomp;

    auto r = Reader(cast(ubyte[])str.dup);
    auto s = Scanner(r);
    auto elems = s.map!"a.value".filter!"a.length > 0".array;
    assert(elems[1] == "foobar");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `test: key: value`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: Mapping values are not allowed here\n" ~
       "<unknown>:1,10");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `test: ? foo
      : bar`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: Mapping keys are not allowed here\n" ~
       "<unknown>:1,7");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `@`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning for the next token, found character '@', index 64 that cannot start any token\n" ~
       "<unknown>:1,1");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `foo: bar
meh`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a simple key, could not find expected ':'\n" ~
       "<unknown>:2,4\nkey started here: <unknown>:2,1");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `foo: &A bar
*A ]`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a simple key, could not find expected ':'\n" ~
       "<unknown>:2,4\nkey started here: <unknown>:2,1");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `foo: &[`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning an anchor or alias, expected a printable character besides '[', ']', '{', '}' and ',', but found [\n" ~
       "<unknown>:1,7\nstarted here: <unknown>:1,6");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `%?`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a directive, expected alphanumeric, '-' or '_', but found ?\n" ~
       "<unknown>:1,2\ndirective started here: <unknown>:1,1");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `%b?`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a directive, expected alphanumeric, '-' or '_', but found ?\n" ~
       "<unknown>:1,3\ndirective started here: <unknown>:1,1");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `%YAML 1?`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a directive, expected digit or '.', but found ?\n" ~
       "<unknown>:1,8\ndirective started here: <unknown>:1,1");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `%YAML 1.1?`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a directive, expected digit or '.', but found ?\n" ~
       "<unknown>:1,10\ndirective started here: <unknown>:1,1");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `%YAML ?`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a directive, expected a digit, but found ?\n" ~
       "<unknown>:1,7\ndirective started here: <unknown>:1,1");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `%TAG !a!<`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a directive handle, expected ' ', but found <\n" ~
       "<unknown>:1,9\ndirective started here: <unknown>:1,1");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `%TAG !a! !>`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a directive prefix, expected ' ', but found >\n" ~
       "<unknown>:1,11\ndirective started here: <unknown>:1,1");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `%YAML 1.0 ?`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a directive, expected a comment or a line break, but found ?\n" ~
       "<unknown>:1,11\ndirective started here: <unknown>:1,1");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `foo: !<a#`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a tag, expected a '>', but found #\n" ~
       "<unknown>:1,9\ntag started here: <unknown>:1,6");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `foo: !<a>#`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a tag, expected a ' ', but found #\n" ~
       "<unknown>:1,10\ntag started here: <unknown>:1,6");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `foo: !<#`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While parsing a tag, expected a URI, but found #\n" ~
       "<unknown>:1,8\ntag started here: <unknown>:1,6");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `foo: |b`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a block scalar, expected a chomping or indentation indicator, but found b\n" ~
       "<unknown>:1,7\nscalar started here: <unknown>:1,6");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `foo: |0`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a block scalar, expected an indentation indicator in range 1-9, but found 0\n" ~
       "<unknown>:1,7\nscalar started here: <unknown>:1,6");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `"\x"`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a double quoted scalar, expected an escape sequence of hexadecimal numbers, but found \"\n" ~
       "<unknown>:1,4\nscalar started here: <unknown>:1,1");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `"\:"`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a double quoted scalar, found unsupported escape character :\n" ~
       "<unknown>:1,3\nscalar started here: <unknown>:1,1");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `"an unfinished scal`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a quoted scalar, found unexpected end of buffer\n" ~
       "<unknown>:1,20\nscalar started here: <unknown>:1,1");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `"an unfinished scal
---`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a quoted scalar, found unexpected document separator\n" ~
       "<unknown>:2,1\nscalar started here: <unknown>:1,1");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `Error: !a:!`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a tag, expected a !, but found :\n" ~
       "<unknown>:1,10\ntag started here: <unknown>:1,8");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `Error: !e!tag%:)`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a tag, expected a URI escape sequence of 2 hexadecimal numbers, but found :)\n" ~
       "<unknown>:1,15\ntag started here: <unknown>:1,8");
}

@safe unittest
{
    import dub.internal.dyaml.loader : Loader;

    const str = `Error: !e!tag%99%99`;

    const exc = collectException!LoaderException(Loader.fromString(str).load());
    assert(exc);
    assert(exc.message() ==
       "Unable to load <unknown>: While scanning a tag, found invalid UTF-8 data encoded in URI escape sequence\n" ~
       "<unknown>:1,20\ntag started here: <unknown>:1,8");
}

private void insert(ref char[] slice, const dchar c, const size_t position) @safe pure
in(position <= slice.length, text("Trying to insert after the end of the slice (", position, " > ", slice.length, ")"))
{
    const point       = position;
    const movedLength = slice.length - point;

    // Encode c into UTF-8
    char[4] encodeBuf;
    if(c < 0x80) { encodeBuf[0] = cast(char)c; }
    const size_t bytes = c < 0x80 ? 1 : encode(encodeBuf, c);

    slice.length += bytes;
    if(movedLength > 0)
    {
        copy(slice[point..point + movedLength * char.sizeof],
                slice[point + bytes .. point + bytes + movedLength * char.sizeof]);
    }
    slice[point .. point + bytes] = encodeBuf[0 .. bytes];
}
