/**
 * Converts binary data read from a file to UTF-8 strings.
 *
 * This code originates from DMD.
 * See_Also:
 * https://github.com/dlang/dmd/blob/a2865d74fbf43b7a4aa6a3b2db658a667cf85dc0/compiler/src/dmd/dmodule.d#L1327-L1514
 */
module dub.internal.utf;

import std.array;
import std.exception;
import std.format;

/**
 * Process the content of a text file
 *
 * Attempts to find which encoding it is using, if it has BOM,
 * and then normalize the text to UTF-8. If no encoding is required,
 * a slice of `src` will be returned without extra allocation.
 *
 * Params:
 *  src = Content of the text file to process
 *  assumeASCII = Assume the the first char must be ASCII (true by default)
 *
 * Returns:
 *   UTF-8 encoded variant of `src`, stripped of any BOM,
 *   or `null` if an error happened.
 */
package(dub) string processText (immutable(ubyte)[] src, bool assumeASCII = true)
{
    enum SourceEncoding { utf16, utf32}
    enum Endian { little, big}

    /*
     * Convert a buffer from UTF32 to UTF8
     * Params:
     *    Endian = is the buffer big/little endian
     *    buf = buffer of UTF32 data
     * Returns:
     *    input buffer reencoded as UTF8
     */

    string UTF32ToUTF8(Endian endian)(const(char)[] buf)
    {
        static if (endian == Endian.little)
            alias readNext = Port.readlongLE;
        else
            alias readNext = Port.readlongBE;

        if (buf.length & 3)
            throw new Exception(format("odd length of UTF-32 char location %s", buf.length));

        const(uint)[] eBuf = cast(const(uint)[])buf;

        Appender!string dbuf;
        dbuf.reserve(eBuf.length);

        foreach (i; 0 .. eBuf.length)
        {
            const u = readNext(&eBuf[i]);
            dbuf.writeUTF8(u);
        }
        dbuf.put('\0'); // add null terminator
        return dbuf.data;
    }

    /*
     * Convert a buffer from UTF16 to UTF8
     * Params:
     *    Endian = is the buffer big/little endian
     *    buf = buffer of UTF16 data
     * Returns:
     *    input buffer reencoded as UTF8
     */

    string UTF16ToUTF8(Endian endian)(const(char)[] buf)
    {
        static if (endian == Endian.little)
            alias readNext = Port.readwordLE;
        else
            alias readNext = Port.readwordBE;

        if (buf.length & 1)
            throw new Exception(format("odd length of UTF-16 char location %s", buf.length));

        const(ushort)[] eBuf = cast(const(ushort)[])buf;

        Appender!string dbuf;
        dbuf.reserve(eBuf.length);

        //i will be incremented in the loop for high codepoints
        foreach (ref i; 0 .. eBuf.length)
        {
            uint u = readNext(&eBuf[i]);
            if (u & ~0x7F)
            {
                if (0xD800 <= u && u < 0xDC00)
                {
                    i++;
                    if (i >= eBuf.length)
                        throw new Exception(format("surrogate UTF-16 high value %04x at end of file", u));
                    const u2 = readNext(&eBuf[i]);
                    if (u2 < 0xDC00 || 0xE000 <= u2)
                        throw new Exception(format("surrogate UTF-16 low value %04x out of range", u2));
                    u = (u - 0xD7C0) << 10;
                    u |= (u2 - 0xDC00);
                }
                else if (u >= 0xDC00 && u <= 0xDFFF)
                    throw new Exception(format("unpaired surrogate UTF-16 value %04x", u));
                else if (u == 0xFFFE || u == 0xFFFF)
                    throw new Exception(format("illegal UTF-16 value %04x", u));
                dbuf.writeUTF8(u);
            }
            else
                dbuf.put(cast(char) u);
        }
        dbuf.put('\0'); // add a terminating null byte
        return dbuf.data;
    }

    string buf = cast(string) src;

    // Assume the buffer is from memory and has not be read from disk. Assume UTF-8.
    if (buf.length < 2)
        return buf;

    /* Convert all non-UTF-8 formats to UTF-8.
     * BOM : https://www.unicode.org/faq/utf_bom.html
     * 00 00 FE FF  UTF-32BE, big-endian
     * FF FE 00 00  UTF-32LE, little-endian
     * FE FF        UTF-16BE, big-endian
     * FF FE        UTF-16LE, little-endian
     * EF BB BF     UTF-8
     */
    if (buf[0] == 0xFF && buf[1] == 0xFE)
    {
        if (buf.length >= 4 && buf[2] == 0 && buf[3] == 0)
            return UTF32ToUTF8!(Endian.little)(buf[4 .. $]);
        return UTF16ToUTF8!(Endian.little)(buf[2 .. $]);
    }

    if (buf[0] == 0xFE && buf[1] == 0xFF)
        return UTF16ToUTF8!(Endian.big)(buf[2 .. $]);

    if (buf.length >= 4 && buf[0] == 0 && buf[1] == 0 && buf[2] == 0xFE && buf[3] == 0xFF)
        return UTF32ToUTF8!(Endian.big)(buf[4 .. $]);

    if (buf.length >= 3 && buf[0] == 0xEF && buf[1] == 0xBB && buf[2] == 0xBF)
        return buf[3 .. $];

    /* There is no BOM. If `assumeASCII` is true (the DMD behavior),
     * try to detect encoding this way. Otherwise, just assume UTF-8.
     */
    if (assumeASCII)
    {
        if (buf.length >= 4 && buf[1] == 0 && buf[2] == 0 && buf[3] == 0)
            return UTF32ToUTF8!(Endian.little)(buf);
        if (buf.length >= 4 && buf[0] == 0 && buf[1] == 0 && buf[2] == 0)
            return UTF32ToUTF8!(Endian.big)(buf);
        // try to check for UTF-16
        if (buf.length >= 2 && buf[1] == 0)
            return UTF16ToUTF8!(Endian.little)(buf);
        if (buf[0] == 0)
            return UTF16ToUTF8!(Endian.big)(buf);
    }

    // It's UTF-8
    if (buf[0] >= 0x80)
        throw new Exception(format("text file must start with BOM or ASCII character, not \\x%02X", buf[0]));

    return buf;
}

private void writeUTF8 (ref Appender!string this_, uint b) @safe pure
{
    this_.reserve(6);
    if (b <= 0x7F)
    {
        this_.put(cast(ubyte)b);
    }
    else if (b <= 0x7FF)
    {
        this_.put(cast(ubyte)((b >> 6) | 0xC0));
        this_.put(cast(ubyte)((b & 0x3F) | 0x80));
    }
    else if (b <= 0xFFFF)
    {
        this_.put(cast(ubyte)((b >> 12) | 0xE0));
        this_.put(cast(ubyte)(((b >> 6) & 0x3F) | 0x80));
        this_.put(cast(ubyte)((b & 0x3F) | 0x80));
    }
    else if (b <= 0x1FFFFF)
    {
        this_.put(cast(ubyte)((b >> 18) | 0xF0));
        this_.put(cast(ubyte)(((b >> 12) & 0x3F) | 0x80));
        this_.put(cast(ubyte)(((b >> 6) & 0x3F) | 0x80));
        this_.put(cast(ubyte)((b & 0x3F) | 0x80));
    }
    else
        throw new Exception(format("UTF-32 value %08x greater than 0x10FFFF", b));
}

private struct Port
{
    nothrow @nogc:

    // Little endian
    static uint readlongLE(scope const void* buffer) pure
    {
        auto p = cast(const ubyte*)buffer;
        return (((((p[3] << 8) | p[2]) << 8) | p[1]) << 8) | p[0];
    }

    // Big endian
    static uint readlongBE(scope const void* buffer) pure
    {
        auto p = cast(const ubyte*)buffer;
        return (((((p[0] << 8) | p[1]) << 8) | p[2]) << 8) | p[3];
    }

    // Little endian
    static uint readwordLE(scope const void* buffer) pure
    {
        auto p = cast(const ubyte*)buffer;
        return (p[1] << 8) | p[0];
    }

    // Big endian
    static uint readwordBE(scope const void* buffer) pure
    {
        auto p = cast(const ubyte*)buffer;
        return (p[0] << 8) | p[1];
    }
}
