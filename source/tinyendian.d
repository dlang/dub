//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// A minimal library providing functionality for changing the endianness of data.
module tinyendian;

import std.system : Endian, endian;

/// Unicode UTF encodings.
enum UTFEncoding : ubyte
{
    UTF_8,
    UTF_16,
    UTF_32
}
///
@safe unittest
{
    const ints = [314, -101];
    int[2] intsSwapBuffer = ints;
    swapByteOrder(intsSwapBuffer[]);
    swapByteOrder(intsSwapBuffer[]);
    assert(ints == intsSwapBuffer, "Lost information when swapping byte order");

    const floats = [3.14f, 10.1f];
    float[2] floatsSwapBuffer = floats;
    swapByteOrder(floatsSwapBuffer[]);
    swapByteOrder(floatsSwapBuffer[]);
    assert(floats == floatsSwapBuffer, "Lost information when swapping byte order");
}

/** Swap byte order of items in an array in place.
 *
 * Params:
 *
 * T     = Item type. Must be either 2 or 4 bytes long.
 * array = Buffer with values to fix byte order of.
 */
void swapByteOrder(T)(T[] array) @trusted @nogc pure nothrow
if (T.sizeof == 2 || T.sizeof == 4)
{
    // Swap the byte order of all read characters.
    foreach (ref item; array)
    {
        static if (T.sizeof == 2)
        {
            import std.algorithm.mutation : swap;
            swap(*cast(ubyte*)&item, *(cast(ubyte*)&item + 1));
        }
        else static if (T.sizeof == 4)
        {
            import core.bitop : bswap;
            const swapped = bswap(*cast(uint*)&item);
            item = *cast(const(T)*)&swapped;
        }
        else static assert(false, "Unsupported T: " ~ T.stringof);
    }
}

/// See fixUTFByteOrder.
struct FixUTFByteOrderResult
{
    ubyte[] array;
    UTFEncoding encoding;
    Endian endian;
    uint bytesStripped = 0;
}

/** Convert byte order of an array encoded in UTF(8/16/32) to system endianness in place.
 *
 * Uses the UTF byte-order-mark (BOM) to determine UTF encoding. If there is no BOM
 * at the beginning of array, UTF-8 is assumed (this is compatible with ASCII). The
 * BOM, if any, will be removed from the buffer.
 *
 * If the encoding is determined to be UTF-16 or UTF-32 and there aren't enough bytes
 * for the last code unit (i.e. if array.length is odd for UTF-16 or not divisible by
 * 4 for UTF-32), the extra bytes (1 for UTF-16, 1-3 for UTF-32) are stripped.
 *
 * Note that this function does $(B not) check if the array is a valid UTF string. It
 * only works with the BOM and 1,2 or 4-byte items.
 *
 * Params:
 *
 * array = The array with UTF-data.
 *
 * Returns:
 *
 * A struct with the following members:
 *
 * $(D ubyte[] array)            A slice of the input array containing data in correct
 *                               byte order, without BOM and in case of UTF-16/UTF-32,
 *                               without stripped bytes, if any.
 * $(D UTFEncoding encoding)     Encoding of the result (UTF-8, UTF-16 or UTF-32)
 * $(D std.system.Endian endian) Endianness of the original array.
 * $(D uint bytesStripped)       Number of bytes stripped from a UTF-16/UTF-32 array, if
 *                               any. This is non-zero only if array.length was not
 *                               divisible by 2 or 4 for UTF-16 and UTF-32, respectively.
 *
 * Complexity: (BIGOH array.length)
 */
auto fixUTFByteOrder(ubyte[] array) @safe @nogc pure nothrow
{
    // Enumerates UTF BOMs, matching indices to byteOrderMarks/bomEndian.
    enum BOM: ubyte
    {
        UTF_8     = 0,
        UTF_16_LE = 1,
        UTF_16_BE = 2,
        UTF_32_LE = 3,
        UTF_32_BE = 4,
        None      = ubyte.max
    }

    // These 2 are from std.stream
    static immutable ubyte[][5] byteOrderMarks = [ [0xEF, 0xBB, 0xBF],
                                                   [0xFF, 0xFE],
                                                   [0xFE, 0xFF],
                                                   [0xFF, 0xFE, 0x00, 0x00],
                                                   [0x00, 0x00, 0xFE, 0xFF] ];
    static immutable Endian[5] bomEndian = [ endian,
                                             Endian.littleEndian,
                                             Endian.bigEndian,
                                             Endian.littleEndian, 
                                             Endian.bigEndian ];

    // Documented in function ddoc.

    FixUTFByteOrderResult result;

    // Detect BOM, if any, in the bytes we've read. -1 means no BOM.
    // Need the last match: First 2 bytes of UTF-32LE BOM match the UTF-16LE BOM. If we
    // used the first match, UTF-16LE would be detected when we have a UTF-32LE BOM.
    import std.algorithm.searching : startsWith;
    BOM bomId = BOM.None;
    foreach (i, bom; byteOrderMarks)
        if (array.startsWith(bom))
            bomId = cast(BOM)i;

    result.endian = (bomId != BOM.None) ? bomEndian[bomId] : Endian.init;

    // Start of UTF data (after BOM, if any)
    size_t start = 0;
    // If we've read more than just the BOM, put the rest into the array.
    with(BOM) final switch(bomId)
    {
        case None: result.encoding = UTFEncoding.UTF_8; break;
        case UTF_8:
            start = 3;
            result.encoding = UTFEncoding.UTF_8;
            break;
        case UTF_16_LE, UTF_16_BE:
            result.bytesStripped = array.length % 2;
            start = 2;
            result.encoding = UTFEncoding.UTF_16;
            break;
        case UTF_32_LE, UTF_32_BE:
            result.bytesStripped = array.length % 4;
            start = 4;
            result.encoding = UTFEncoding.UTF_32;
            break;
    }

    // If there's a BOM, we need to move data back to ensure it starts at array[0]
    if (start != 0)
    {
        array = array[start .. $  - result.bytesStripped];
    }

    // We enforce above that array.length is divisible by 2/4 for UTF-16/32
    if (endian != result.endian)
    {
        if (result.encoding == UTFEncoding.UTF_16)
            swapByteOrder(cast(wchar[])array);
        else if (result.encoding == UTFEncoding.UTF_32)
            swapByteOrder(cast(dchar[])array);
    }

    result.array = array;
    return result;
}
///
@safe unittest
{
    {
        ubyte[] s = [0xEF, 0xBB, 0xBF, 'a'];
        FixUTFByteOrderResult r = fixUTFByteOrder(s);
        assert(r.encoding == UTFEncoding.UTF_8);
        assert(r.array.length == 1);
        assert(r.array == ['a']);
        assert(r.endian == Endian.littleEndian);
    }

    {
        ubyte[] s = ['a'];
        FixUTFByteOrderResult r = fixUTFByteOrder(s);
        assert(r.encoding == UTFEncoding.UTF_8);
        assert(r.array.length == 1);
        assert(r.array == ['a']);
        assert(r.endian == Endian.bigEndian);
    }

    {
        // strip 'a' b/c not complete unit
        ubyte[] s = [0xFE, 0xFF, 'a'];
        FixUTFByteOrderResult r = fixUTFByteOrder(s);
        assert(r.encoding == UTFEncoding.UTF_16);
        assert(r.array.length == 0);
        assert(r.endian == Endian.bigEndian);
    }

}
