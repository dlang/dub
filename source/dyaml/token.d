
//          Copyright Ferdinand Majerech 2011-2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// YAML tokens.
/// Code based on PyYAML: http://www.pyyaml.org
module dyaml.token;


import std.conv;

import dyaml.encoding;
import dyaml.exception;
import dyaml.reader;
import dyaml.style;


package:

/// Token types.
enum TokenID : ubyte
{
    // Invalid (uninitialized) token
    invalid = 0,
    directive,
    documentStart,
    documentEnd,
    streamStart,
    streamEnd,
    blockSequenceStart,
    blockMappingStart,
    blockEnd,
    flowSequenceStart,
    flowMappingStart,
    flowSequenceEnd,
    flowMappingEnd,
    key,
    value,
    blockEntry,
    flowEntry,
    alias_,
    anchor,
    tag,
    scalar
}

/// Specifies the type of a tag directive token.
enum DirectiveType : ubyte
{
    // YAML version directive.
    yaml,
    // Tag directive.
    tag,
    // Any other directive is "reserved" for future YAML versions.
    reserved
}

/// Token produced by scanner.
///
/// 32 bytes on 64-bit.
struct Token
{
    @disable int opCmp(ref Token);

    // 16B
    /// Value of the token, if any.
    ///
    /// Values are char[] instead of string, as Parser may still change them in a few
    /// cases. Parser casts values to strings when producing Events.
    char[] value;
    // 4B
    /// Start position of the token in file/stream.
    Mark startMark;
    // 4B
    /// End position of the token in file/stream.
    Mark endMark;
    // 1B
    /// Token type.
    TokenID id;
    // 1B
    /// Style of scalar token, if this is a scalar token.
    ScalarStyle style;
    // 1B
    /// Encoding, if this is a stream start token.
    Encoding encoding;
    // 1B
    /// Type of directive for directiveToken.
    DirectiveType directive;
    // 4B
    /// Used to split value into 2 substrings for tokens that need 2 values (tagToken)
    uint valueDivider;

    /// Get string representation of the token ID.
    @property string idString() @safe pure const {return id.to!string;}
}

/// Construct a directive token.
///
/// Params:  start     = Start position of the token.
///          end       = End position of the token.
///          value     = Value of the token.
///          directive = Directive type (YAML or TAG in YAML 1.1).
///          nameEnd = Position of the end of the name
Token directiveToken(const Mark start, const Mark end, char[] value,
                     DirectiveType directive, const uint nameEnd) @safe pure nothrow @nogc
{
    return Token(value, start, end, TokenID.directive, ScalarStyle.init, Encoding.init,
                 directive, nameEnd);
}

/// Construct a simple (no value) token with specified type.
///
/// Params:  id    = Type of the token.
///          start = Start position of the token.
///          end   = End position of the token.
Token simpleToken(TokenID id)(const Mark start, const Mark end)
{
    return Token(null, start, end, id);
}

/// Construct a stream start token.
///
/// Params:  start    = Start position of the token.
///          end      = End position of the token.
///          encoding = Encoding of the stream.
Token streamStartToken(const Mark start, const Mark end, const Encoding encoding) @safe pure nothrow @nogc
{
    return Token(null, start, end, TokenID.streamStart, ScalarStyle.invalid, encoding);
}

/// Aliases for construction of simple token types.
alias streamEndToken = simpleToken!(TokenID.streamEnd);
alias blockSequenceStartToken = simpleToken!(TokenID.blockSequenceStart);
alias blockMappingStartToken = simpleToken!(TokenID.blockMappingStart);
alias blockEndToken = simpleToken!(TokenID.blockEnd);
alias keyToken = simpleToken!(TokenID.key);
alias valueToken = simpleToken!(TokenID.value);
alias blockEntryToken = simpleToken!(TokenID.blockEntry);
alias flowEntryToken = simpleToken!(TokenID.flowEntry);

/// Construct a simple token with value with specified type.
///
/// Params:  id           = Type of the token.
///          start        = Start position of the token.
///          end          = End position of the token.
///          value        = Value of the token.
///          valueDivider = A hack for TagToken to store 2 values in value; the first
///                         value goes up to valueDivider, the second after it.
Token simpleValueToken(TokenID id)(const Mark start, const Mark end, char[] value,
                                   const uint valueDivider = uint.max)
{
    return Token(value, start, end, id, ScalarStyle.invalid, Encoding.init,
                 DirectiveType.init, valueDivider);
}

/// Alias for construction of tag token.
alias tagToken = simpleValueToken!(TokenID.tag);
alias aliasToken = simpleValueToken!(TokenID.alias_);
alias anchorToken = simpleValueToken!(TokenID.anchor);

/// Construct a scalar token.
///
/// Params:  start = Start position of the token.
///          end   = End position of the token.
///          value = Value of the token.
///          style = Style of the token.
Token scalarToken(const Mark start, const Mark end, char[] value, const ScalarStyle style) @safe pure nothrow @nogc
{
    return Token(value, start, end, TokenID.scalar, style);
}
