

//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.escapes;

package:

import std.meta : AliasSeq;
alias escapes = AliasSeq!('0', 'a', 'b', 't', '\t', 'n', 'v', 'f', 'r', 'e', ' ',
                             '\"', '\\', 'N', '_', 'L', 'P');

/// YAML hex codes specifying the length of the hex number.
alias escapeHexCodeList = AliasSeq!('x', 'u', 'U');

/// Convert a YAML escape to a dchar.
dchar fromEscape(dchar escape) @safe pure nothrow @nogc
{
    switch(escape)
    {
        case '0':  return '\0';
        case 'a':  return '\x07';
        case 'b':  return '\x08';
        case 't':  return '\x09';
        case '\t': return '\x09';
        case 'n':  return '\x0A';
        case 'v':  return '\x0B';
        case 'f':  return '\x0C';
        case 'r':  return '\x0D';
        case 'e':  return '\x1B';
        case ' ':  return '\x20';
        case '\"': return '\"';
        case '\\': return '\\';
        case 'N':  return '\x85'; //'\u0085';
        case '_':  return '\xA0';
        case 'L':  return '\u2028';
        case 'P':  return '\u2029';
        default:   assert(false, "No such YAML escape");
    }
}

/**
 * Convert a dchar to a YAML escape.
 *
 * Params:
 *      value = The possibly escapable character.
 *
 * Returns:
 *      If the character passed as parameter can be escaped, returns the matching
 *      escape, otherwise returns a null character.
 */
dchar toEscape(dchar value) @safe pure nothrow @nogc
{
    switch(value)
    {
        case '\0':   return '0';
        case '\x07': return 'a';
        case '\x08': return 'b';
        case '\x09': return 't';
        case '\x0A': return 'n';
        case '\x0B': return 'v';
        case '\x0C': return 'f';
        case '\x0D': return 'r';
        case '\x1B': return 'e';
        case '\"':   return '\"';
        case '\\':   return '\\';
        case '\xA0': return '_';
        case '\x85': return 'N';
        case '\u2028': return 'L';
        case '\u2029': return 'P';
        default: return 0;
    }
}

/// Get the length of a hexadecimal number determined by its hex code.
///
/// Need a function as associative arrays don't work with @nogc.
/// (And this may be even faster with a function.)
uint escapeHexLength(dchar hexCode) @safe pure nothrow @nogc
{
    switch(hexCode)
    {
        case 'x': return 2;
        case 'u': return 4;
        case 'U': return 8;
        default:  assert(false, "No such YAML hex code");
    }
}

