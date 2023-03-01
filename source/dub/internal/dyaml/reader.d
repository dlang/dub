
//          Copyright Ferdinand Majerech 2011-2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dub.internal.dyaml.reader;


import core.stdc.stdlib;
import core.stdc.string;
import core.thread;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.range;
import std.string;
import std.system;
import std.typecons;
import std.utf;

import dub.internal.tinyendian;

import dub.internal.dyaml.encoding;
import dub.internal.dyaml.exception;

alias isBreak = among!('\n', '\u0085', '\u2028', '\u2029');

package:


///Exception thrown at Reader errors.
class ReaderException : YAMLException
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
        @safe pure nothrow
    {
        super("Reader error: " ~ msg, file, line);
    }
}

/// Provides an API to read characters from a UTF-8 buffer and build slices into that
/// buffer to avoid allocations (see SliceBuilder).
final class Reader
{
    private:
        // Buffer of currently loaded characters.
        char[] buffer_;

        // Current position within buffer. Only data after this position can be read.
        size_t bufferOffset_;

        // Index of the current character in the buffer.
        size_t charIndex_;
        // Number of characters (code points) in buffer_.
        size_t characterCount_;

        // File name
        string name_;
        // Current line in file.
        uint line_;
        // Current column in file.
        uint column_;

        // Original Unicode encoding of the data.
        Encoding encoding_;

        version(unittest)
        {
            // Endianness of the input before it was converted (for testing)
            Endian endian_;
        }

        // The number of consecutive ASCII characters starting at bufferOffset_.
        //
        // Used to minimize UTF-8 decoding.
        size_t upcomingASCII_;

        // Index to buffer_ where the last decoded character starts.
        size_t lastDecodedBufferOffset_;
        // Offset, relative to charIndex_, of the last decoded character,
        // in code points, not chars.
        size_t lastDecodedCharOffset_;

    public:
        /// Construct a Reader.
        ///
        /// Params:  buffer = Buffer with YAML data. This may be e.g. the entire
        ///                   contents of a file or a string. $(B will) be modified by
        ///                   the Reader and other parts of D:YAML (D:YAML tries to
        ///                   reuse the buffer to minimize memory allocations)
        ///          name   = File name if the buffer is the contents of a file or
        ///                   `"<unknown>"` if the buffer is the contents of a string.
        ///
        /// Throws:  ReaderException on a UTF decoding error or if there are
        ///          non-printable Unicode characters illegal in YAML.
        this(ubyte[] buffer, string name = "<unknown>") @safe pure
        {
            name_ = name;
            auto endianResult = fixUTFByteOrder(buffer);
            if(endianResult.bytesStripped > 0)
            {
                throw new ReaderException("Size of UTF-16 or UTF-32 input not aligned " ~
                                          "to 2 or 4 bytes, respectively");
            }

            version(unittest) { endian_ = endianResult.endian; }
            encoding_ = endianResult.encoding;

            auto utf8Result = toUTF8(endianResult.array, endianResult.encoding);
            const msg = utf8Result.errorMessage;
            if(msg !is null)
            {
                throw new ReaderException("Error when converting to UTF-8: " ~ msg);
            }

            buffer_ = utf8Result.utf8;

            characterCount_ = utf8Result.characterCount;
            // Check that all characters in buffer are printable.
            enforce(isPrintableValidUTF8(buffer_),
                    new ReaderException("Special unicode characters are not allowed"));

            this.sliceBuilder = SliceBuilder(this);
            checkASCII();
        }

        /// Get character at specified index relative to current position.
        ///
        /// Params:  index = Index of the character to get relative to current position
        ///                  in the buffer. Can point outside of the buffer; In that
        ///                  case, '\0' will be returned.
        ///
        /// Returns: Character at specified position or '\0' if outside of the buffer.
        ///
        // XXX removed; search for 'risky' to find why.
        // Throws:  ReaderException if trying to read past the end of the buffer.
        dchar peek(const size_t index) @safe pure
        {
            if(index < upcomingASCII_) { return buffer_[bufferOffset_ + index]; }
            if(characterCount_ <= charIndex_ + index)
            {
                // XXX This is risky; revert this if bugs are introduced. We rely on
                // the assumption that Reader only uses peek() to detect end of buffer.
                // The test suite passes.
                // Revert this case here and in other peek() versions if this causes
                // errors.
                // throw new ReaderException("Trying to read past the end of the buffer");
                return '\0';
            }

            // Optimized path for Scanner code that peeks chars in linear order to
            // determine the length of some sequence.
            if(index == lastDecodedCharOffset_)
            {
                ++lastDecodedCharOffset_;
                const char b = buffer_[lastDecodedBufferOffset_];
                // ASCII
                if(b < 0x80)
                {
                    ++lastDecodedBufferOffset_;
                    return b;
                }
                return decode(buffer_, lastDecodedBufferOffset_);
            }

            // 'Slow' path where we decode everything up to the requested character.
            const asciiToTake = min(upcomingASCII_, index);
            lastDecodedCharOffset_   = asciiToTake;
            lastDecodedBufferOffset_ = bufferOffset_ + asciiToTake;
            dchar d;
            while(lastDecodedCharOffset_ <= index)
            {
                d = decodeNext();
            }

            return d;
        }

        /// Optimized version of peek() for the case where peek index is 0.
        dchar peek() @safe pure
        {
            if(upcomingASCII_ > 0)            { return buffer_[bufferOffset_]; }
            if(characterCount_ <= charIndex_) { return '\0'; }

            lastDecodedCharOffset_   = 0;
            lastDecodedBufferOffset_ = bufferOffset_;
            return decodeNext();
        }

        /// Get byte at specified index relative to current position.
        ///
        /// Params:  index = Index of the byte to get relative to current position
        ///                  in the buffer. Can point outside of the buffer; In that
        ///                  case, '\0' will be returned.
        ///
        /// Returns: Byte at specified position or '\0' if outside of the buffer.
        char peekByte(const size_t index) @safe pure nothrow @nogc
        {
            return characterCount_ > (charIndex_ + index) ? buffer_[bufferOffset_ + index] : '\0';
        }

        /// Optimized version of peekByte() for the case where peek byte index is 0.
        char peekByte() @safe pure nothrow @nogc
        {
            return characterCount_ > charIndex_ ? buffer_[bufferOffset_] : '\0';
        }


        /// Get specified number of characters starting at current position.
        ///
        /// Note: This gets only a "view" into the internal buffer, which will be
        ///       invalidated after other Reader calls. Use SliceBuilder to build slices
        ///       for permanent use.
        ///
        /// Params: length = Number of characters (code points, not bytes) to get. May
        ///                  reach past the end of the buffer; in that case the returned
        ///                  slice will be shorter.
        ///
        /// Returns: Characters starting at current position or an empty slice if out of bounds.
        char[] prefix(const size_t length) @safe pure
        {
            return slice(length);
        }

        /// Get specified number of bytes, not code points, starting at current position.
        ///
        /// Note: This gets only a "view" into the internal buffer, which will be
        ///       invalidated after other Reader calls. Use SliceBuilder to build slices
        ///       for permanent use.
        ///
        /// Params: length = Number bytes (not code points) to get. May NOT reach past
        ///                  the end of the buffer; should be used with peek() to avoid
        ///                  this.
        ///
        /// Returns: Bytes starting at current position.
        char[] prefixBytes(const size_t length) @safe pure nothrow @nogc
        in(length == 0 || bufferOffset_ + length <= buffer_.length, "prefixBytes out of bounds")
        {
            return buffer_[bufferOffset_ .. bufferOffset_ + length];
        }

        /// Get a slice view of the internal buffer, starting at the current position.
        ///
        /// Note: This gets only a "view" into the internal buffer,
        ///       which get invalidated after other Reader calls.
        ///
        /// Params:  end = End of the slice relative to current position. May reach past
        ///                the end of the buffer; in that case the returned slice will
        ///                be shorter.
        ///
        /// Returns: Slice into the internal buffer or an empty slice if out of bounds.
        char[] slice(const size_t end) @safe pure
        {
            // Fast path in case the caller has already peek()ed all the way to end.
            if(end == lastDecodedCharOffset_)
            {
                return buffer_[bufferOffset_ .. lastDecodedBufferOffset_];
            }

            const asciiToTake = min(upcomingASCII_, end, buffer_.length);
            lastDecodedCharOffset_   = asciiToTake;
            lastDecodedBufferOffset_ = bufferOffset_ + asciiToTake;

            // 'Slow' path - decode everything up to end.
            while(lastDecodedCharOffset_ < end &&
                  lastDecodedBufferOffset_ < buffer_.length)
            {
                decodeNext();
            }

            return buffer_[bufferOffset_ .. lastDecodedBufferOffset_];
        }

        /// Get the next character, moving buffer position beyond it.
        ///
        /// Returns: Next character.
        ///
        /// Throws:  ReaderException if trying to read past the end of the buffer
        ///          or if invalid data is read.
        dchar get() @safe pure
        {
            const result = peek();
            forward();
            return result;
        }

        /// Get specified number of characters, moving buffer position beyond them.
        ///
        /// Params:  length = Number or characters (code points, not bytes) to get.
        ///
        /// Returns: Characters starting at current position.
        char[] get(const size_t length) @safe pure
        {
            auto result = slice(length);
            forward(length);
            return result;
        }

        /// Move current position forward.
        ///
        /// Params:  length = Number of characters to move position forward.
        void forward(size_t length) @safe pure
        {
            while(length > 0)
            {
                auto asciiToTake = min(upcomingASCII_, length);
                charIndex_     += asciiToTake;
                length         -= asciiToTake;
                upcomingASCII_ -= asciiToTake;

                for(; asciiToTake > 0; --asciiToTake)
                {
                    const c = buffer_[bufferOffset_++];
                    // c is ASCII, do we only need to check for ASCII line breaks.
                    if(c == '\n' || (c == '\r' && buffer_[bufferOffset_] != '\n'))
                    {
                        ++line_;
                        column_ = 0;
                        continue;
                    }
                    ++column_;
                }

                // If we have used up all upcoming ASCII chars, the next char is
                // non-ASCII even after this returns, so upcomingASCII_ doesn't need to
                // be updated - it's zero.
                if(length == 0) { break; }

                assert(upcomingASCII_ == 0,
                       "Running unicode handling code but we haven't run out of ASCII chars");
                assert(bufferOffset_ < buffer_.length,
                       "Attempted to decode past the end of YAML buffer");
                assert(buffer_[bufferOffset_] >= 0x80,
                       "ASCII must be handled by preceding code");

                ++charIndex_;
                const c = decode(buffer_, bufferOffset_);

                // New line. (can compare with '\n' without decoding since it's ASCII)
                if(c.isBreak || (c == '\r' && buffer_[bufferOffset_] != '\n'))
                {
                    ++line_;
                    column_ = 0;
                }
                else if(c != '\uFEFF') { ++column_; }
                --length;
                checkASCII();
            }

            lastDecodedBufferOffset_ = bufferOffset_;
            lastDecodedCharOffset_ = 0;
        }

        /// Move current position forward by one character.
        void forward() @safe pure
        {
            ++charIndex_;
            lastDecodedBufferOffset_ = bufferOffset_;
            lastDecodedCharOffset_ = 0;

            // ASCII
            if(upcomingASCII_ > 0)
            {
                --upcomingASCII_;
                const c = buffer_[bufferOffset_++];

                if(c == '\n' || (c == '\r' && buffer_[bufferOffset_] != '\n'))
                {
                    ++line_;
                    column_ = 0;
                    return;
                }
                ++column_;
                return;
            }

            // UTF-8
            assert(bufferOffset_ < buffer_.length,
                   "Attempted to decode past the end of YAML buffer");
            assert(buffer_[bufferOffset_] >= 0x80,
                   "ASCII must be handled by preceding code");

            const c = decode(buffer_, bufferOffset_);

            // New line. (can compare with '\n' without decoding since it's ASCII)
            if(c.isBreak || (c == '\r' && buffer_[bufferOffset_] != '\n'))
            {
                ++line_;
                column_ = 0;
            }
            else if(c != '\uFEFF') { ++column_; }

            checkASCII();
        }

        /// Used to build slices of read data in Reader; to avoid allocations.
        SliceBuilder sliceBuilder;

        /// Get a string describing current buffer position, used for error messages.
        Mark mark() const pure nothrow @nogc @safe { return Mark(name_, line_, column_); }

        /// Get file name.
        string name() const @safe pure nothrow @nogc { return name_; }

        /// Set file name.
        void name(string name) pure @safe nothrow @nogc { name_ = name; }

        /// Get current line number.
        uint line() const @safe pure nothrow @nogc { return line_; }

        /// Get current column number.
        uint column() const @safe pure nothrow @nogc { return column_; }

        /// Get index of the current character in the buffer.
        size_t charIndex() const @safe pure nothrow @nogc { return charIndex_; }

        /// Get encoding of the input buffer.
        Encoding encoding() const @safe pure nothrow @nogc { return encoding_; }

private:
        // Update upcomingASCII_ (should be called forward()ing over a UTF-8 sequence)
        void checkASCII() @safe pure nothrow @nogc
        {
            upcomingASCII_ = countASCII(buffer_[bufferOffset_ .. $]);
        }

        // Decode the next character relative to
        // lastDecodedCharOffset_/lastDecodedBufferOffset_ and update them.
        //
        // Does not advance the buffer position. Used in peek() and slice().
        dchar decodeNext() @safe pure
        {
            assert(lastDecodedBufferOffset_ < buffer_.length,
                   "Attempted to decode past the end of YAML buffer");
            const char b = buffer_[lastDecodedBufferOffset_];
            ++lastDecodedCharOffset_;
            // ASCII
            if(b < 0x80)
            {
                ++lastDecodedBufferOffset_;
                return b;
            }

            return decode(buffer_, lastDecodedBufferOffset_);
        }
}

/// Used to build slices of already read data in Reader buffer, avoiding allocations.
///
/// Usually these slices point to unchanged Reader data, but sometimes the data is
/// changed due to how YAML interprets certain characters/strings.
///
/// See begin() documentation.
struct SliceBuilder
{
private:
    // No copying by the user.
    @disable this(this);
    @disable void opAssign(ref SliceBuilder);

    // Reader this builder works in.
    Reader reader_;

    // Start of the slice om reader_.buffer_ (size_t.max while no slice being build)
    size_t start_ = size_t.max;
    // End of the slice om reader_.buffer_ (size_t.max while no slice being build)
    size_t end_   = size_t.max;

    // Stack of slice ends to revert to (see Transaction)
    //
    // Very few levels as we don't want arbitrarily nested transactions.
    size_t[4] endStack_;
    // The number of elements currently in endStack_.
    size_t endStackUsed_;

    @safe const pure nothrow @nogc invariant()
    {
        if(!inProgress) { return; }
        assert(end_ <= reader_.bufferOffset_, "Slice ends after buffer position");
        assert(start_ <= end_, "Slice start after slice end");
    }

    // Is a slice currently being built?
    bool inProgress() @safe const pure nothrow @nogc
    in(start_ == size_t.max ? end_ == size_t.max : end_ != size_t.max, "start_/end_ are not consistent")
    {
        return start_ != size_t.max;
    }

public:
    /// Begin building a slice.
    ///
    /// Only one slice can be built at any given time; before beginning a new slice,
    /// finish the previous one (if any).
    ///
    /// The slice starts at the current position in the Reader buffer. It can only be
    /// extended up to the current position in the buffer; Reader methods get() and
    /// forward() move the position. E.g. it is valid to extend a slice by write()-ing
    /// a string just returned by get() - but not one returned by prefix() unless the
    /// position has changed since the prefix() call.
    void begin() @safe pure nothrow @nogc
    in(!inProgress, "Beginning a slice while another slice is being built")
    in(endStackUsed_ == 0, "Slice stack not empty at slice begin")
    {

        start_ = reader_.bufferOffset_;
        end_   = reader_.bufferOffset_;
    }

    /// Finish building a slice and return it.
    ///
    /// Any Transactions on the slice must be committed or destroyed before the slice
    /// is finished.
    ///
    /// Returns a string; once a slice is finished it is definitive that its contents
    /// will not be changed.
    char[] finish() @safe pure nothrow @nogc
    in(inProgress, "finish called without begin")
    in(endStackUsed_ == 0, "Finishing a slice with running transactions.")
    {

        auto result = reader_.buffer_[start_ .. end_];
        start_ = end_ = size_t.max;
        return result;
    }

    /// Write a string to the slice being built.
    ///
    /// Data can only be written up to the current position in the Reader buffer.
    ///
    /// If str is a string returned by a Reader method, and str starts right after the
    /// end of the slice being built, the slice is extended (trivial operation).
    ///
    /// See_Also: begin
    void write(scope char[] str) @safe pure nothrow @nogc
    {
        assert(inProgress, "write called without begin");
        assert(end_ <= reader_.bufferOffset_,
               "AT START: Slice ends after buffer position");

        // Nothing? Already done.
        if (str.length == 0) { return; }
        // If str starts at the end of the slice (is a string returned by a Reader
        // method), just extend the slice to contain str.
        if(&str[0] == &reader_.buffer_[end_])
        {
            end_ += str.length;
        }
        // Even if str does not start at the end of the slice, it still may be returned
        // by a Reader method and point to buffer. So we need to memmove.
        else
        {
            copy(str, reader_.buffer_[end_..end_ + str.length * char.sizeof]);
            end_ += str.length;
        }
    }

    /// Write a character to the slice being built.
    ///
    /// Data can only be written up to the current position in the Reader buffer.
    ///
    /// See_Also: begin
    void write(dchar c) @safe pure
    in(inProgress, "write called without begin")
    {
        if(c < 0x80)
        {
            reader_.buffer_[end_++] = cast(char)c;
            return;
        }

        // We need to encode a non-ASCII dchar into UTF-8
        char[4] encodeBuf;
        const bytes = encode(encodeBuf, c);
        reader_.buffer_[end_ .. end_ + bytes] = encodeBuf[0 .. bytes];
        end_ += bytes;
    }

    /// Insert a character to a specified position in the slice.
    ///
    /// Enlarges the slice by 1 char. Note that the slice can only extend up to the
    /// current position in the Reader buffer.
    ///
    /// Params:
    ///
    /// c        = The character to insert.
    /// position = Position to insert the character at in code units, not code points.
    ///            Must be less than slice length(); a previously returned length()
    ///            can be used.
    void insert(const dchar c, const size_t position) @safe pure
    in(inProgress, "insert called without begin")
    in(start_ + position <= end_, "Trying to insert after the end of the slice")
    {

        const point       = start_ + position;
        const movedLength = end_ - point;

        // Encode c into UTF-8
        char[4] encodeBuf;
        if(c < 0x80) { encodeBuf[0] = cast(char)c; }
        const size_t bytes = c < 0x80 ? 1 : encode(encodeBuf, c);

        if(movedLength > 0)
        {
            copy(reader_.buffer_[point..point + movedLength * char.sizeof],
                    reader_.buffer_[point + bytes..point + bytes + movedLength * char.sizeof]);
        }
        reader_.buffer_[point .. point + bytes] = encodeBuf[0 .. bytes];
        end_ += bytes;
    }

    /// Get the current length of the slice.
    size_t length() @safe const pure nothrow @nogc
    {
        return end_ - start_;
    }

    /// A slice building transaction.
    ///
    /// Can be used to save and revert back to slice state.
    struct Transaction
    {
    private:
        // The slice builder affected by the transaction.
        SliceBuilder* builder_;
        // Index of the return point of the transaction in StringBuilder.endStack_.
        size_t stackLevel_;
        // True after commit() has been called.
        bool committed_;

    public:
        /// Begins a transaction on a SliceBuilder object.
        ///
        /// The transaction must end $(B after) any transactions created within the
        /// transaction but $(B before) the slice is finish()-ed. A transaction can be
        /// ended either by commit()-ing or reverting through the destructor.
        ///
        /// Saves the current state of a slice.
        this(SliceBuilder* builder) @safe pure nothrow @nogc
        {
            builder_ = builder;
            stackLevel_ = builder_.endStackUsed_;
            builder_.push();
        }

        /// Commit changes to the slice.
        ///
        /// Ends the transaction - can only be called once, and removes the possibility
        /// to revert slice state.
        ///
        /// Does nothing for a default-initialized transaction (the transaction has not
        /// been started yet).
        void commit() @safe pure nothrow @nogc
        in(!committed_, "Can't commit a transaction more than once")
        {

            if(builder_ is null) { return; }
            assert(builder_.endStackUsed_ == stackLevel_ + 1,
                   "Parent transactions don't fully contain child transactions");
            builder_.apply();
            committed_ = true;
        }

        /// Destroy the transaction and revert it if it hasn't been committed yet.
        void end() @safe pure nothrow @nogc
        in(builder_ && builder_.endStackUsed_ == stackLevel_ + 1, "Parent transactions don't fully contain child transactions")
        {
            builder_.pop();
            builder_ = null;
        }

    }

private:
    // Push the current end of the slice so we can revert to it if needed.
    //
    // Used by Transaction.
    void push() @safe pure nothrow @nogc
    in(inProgress, "push called without begin")
    in(endStackUsed_ < endStack_.length, "Slice stack overflow")
    {
        endStack_[endStackUsed_++] = end_;
    }

    // Pop the current end of endStack_ and set the end of the slice to the popped
    // value, reverting changes since the old end was pushed.
    //
    // Used by Transaction.
    void pop() @safe pure nothrow @nogc
    in(inProgress, "pop called without begin")
    in(endStackUsed_ > 0, "Trying to pop an empty slice stack")
    {
        end_ = endStack_[--endStackUsed_];
    }

    // Pop the current end of endStack_, but keep the current end of the slice, applying
    // changes made since pushing the old end.
    //
    // Used by Transaction.
    void apply() @safe pure nothrow @nogc
    in(inProgress, "apply called without begin")
    in(endStackUsed_ > 0, "Trying to apply an empty slice stack")
    {
        --endStackUsed_;
    }
}


private:

// Convert a UTF-8/16/32 buffer to UTF-8, in-place if possible.
//
// Params:
//
// input    = Buffer with UTF-8/16/32 data to decode. May be overwritten by the
//            conversion, in which case the result will be a slice of this buffer.
// encoding = Encoding of input.
//
// Returns:
//
// A struct with the following members:
//
// $(D string errorMessage)   In case of an error, the error message is stored here. If
//                            there was no error, errorMessage is NULL. Always check
//                            this first.
// $(D char[] utf8)           input converted to UTF-8. May be a slice of input.
// $(D size_t characterCount) Number of characters (code points) in input.
auto toUTF8(ubyte[] input, const UTFEncoding encoding) @safe pure nothrow
{
    // Documented in function ddoc.
    struct Result
    {
        string errorMessage;
        char[] utf8;
        size_t characterCount;
    }

    Result result;

    // Encode input_ into UTF-8 if it's encoded as UTF-16 or UTF-32.
    //
    // Params:
    //
    // buffer = The input buffer to encode.
    // result = A Result struct to put encoded result and any error messages to.
    //
    // On error, result.errorMessage will be set.
    static void encode(C)(C[] input, ref Result result) @safe pure
    {
        // We can do UTF-32->UTF-8 in place because all UTF-8 sequences are 4 or
        // less bytes.
        static if(is(C == dchar))
        {
            char[4] encodeBuf;
            auto utf8 = cast(char[])input;
            auto length = 0;
            foreach(dchar c; input)
            {
                ++result.characterCount;
                // ASCII
                if(c < 0x80)
                {
                    utf8[length++] = cast(char)c;
                    continue;
                }

                std.utf.encode(encodeBuf, c);
                const bytes = codeLength!char(c);
                utf8[length .. length + bytes] = encodeBuf[0 .. bytes];
                length += bytes;
            }
            result.utf8 = utf8[0 .. length];
        }
        // Unfortunately we can't do UTF-16 in place so we just use std.conv.to
        else
        {
            result.characterCount = std.utf.count(input);
            result.utf8 = input.to!(char[]);
        }
    }

    try final switch(encoding)
    {
        case UTFEncoding.UTF_8:
            result.utf8 = cast(char[])input;
            result.utf8.validate();
            result.characterCount = std.utf.count(result.utf8);
            break;
        case UTFEncoding.UTF_16:
            assert(input.length % 2 == 0, "UTF-16 buffer size must be even");
            encode(cast(wchar[])input, result);
            break;
        case UTFEncoding.UTF_32:
            assert(input.length % 4 == 0, "UTF-32 buffer size must be a multiple of 4");
            encode(cast(dchar[])input, result);
            break;
    }
    catch(ConvException e) { result.errorMessage = e.msg; }
    catch(UTFException e)  { result.errorMessage = e.msg; }
    catch(Exception e)
    {
        assert(false, "Unexpected exception in encode(): " ~ e.msg);
    }

    return result;
}

/// Determine if all characters (code points, not bytes) in a string are printable.
bool isPrintableValidUTF8(const char[] chars) @safe pure
{
    import std.uni : isControl, isWhite;
    foreach (dchar chr; chars)
    {
        if (!chr.isValidDchar || (chr.isControl && !chr.isWhite))
        {
            return false;
        }
    }
    return true;
}

/// Counts the number of ASCII characters in buffer until the first UTF-8 sequence.
///
/// Used to determine how many characters we can process without decoding.
size_t countASCII(const(char)[] buffer) @safe pure nothrow @nogc
{
    return buffer.byCodeUnit.until!(x => x > 0x7F).walkLength;
}
// Unittests.

void testEndian(R)()
{
    void endian_test(ubyte[] data, Encoding encoding_expected, Endian endian_expected)
    {
        auto reader = new R(data);
        assert(reader.encoding == encoding_expected);
        assert(reader.endian_ == endian_expected);
    }
    ubyte[] little_endian_utf_16 = [0xFF, 0xFE, 0x7A, 0x00];
    ubyte[] big_endian_utf_16 = [0xFE, 0xFF, 0x00, 0x7A];
    endian_test(little_endian_utf_16, Encoding.UTF_16, Endian.littleEndian);
    endian_test(big_endian_utf_16, Encoding.UTF_16, Endian.bigEndian);
}

void testPeekPrefixForward(R)()
{
    import std.encoding;
    ubyte[] data = bomTable[BOM.utf8].sequence ~ cast(ubyte[])"data";
    auto reader = new R(data);
    assert(reader.peek() == 'd');
    assert(reader.peek(1) == 'a');
    assert(reader.peek(2) == 't');
    assert(reader.peek(3) == 'a');
    assert(reader.peek(4) == '\0');
    assert(reader.prefix(4) == "data");
    // assert(reader.prefix(6) == "data\0");
    reader.forward(2);
    assert(reader.peek(1) == 'a');
    // assert(collectException(reader.peek(3)));
}

void testUTF(R)()
{
    import std.encoding;
    dchar[] data = cast(dchar[])"data";
    void utf_test(T)(T[] data, BOM bom)
    {
        ubyte[] bytes = bomTable[bom].sequence ~
                        (cast(ubyte[])data)[0 .. data.length * T.sizeof];
        auto reader = new R(bytes);
        assert(reader.peek() == 'd');
        assert(reader.peek(1) == 'a');
        assert(reader.peek(2) == 't');
        assert(reader.peek(3) == 'a');
    }
    utf_test!char(to!(char[])(data), BOM.utf8);
    utf_test!wchar(to!(wchar[])(data), endian == Endian.bigEndian ? BOM.utf16be : BOM.utf16le);
    utf_test(data, endian == Endian.bigEndian ? BOM.utf32be : BOM.utf32le);
}

void test1Byte(R)()
{
    ubyte[] data = [97];

    auto reader = new R(data);
    assert(reader.peek() == 'a');
    assert(reader.peek(1) == '\0');
    // assert(collectException(reader.peek(2)));
}

@system unittest
{
    testEndian!Reader();
    testPeekPrefixForward!Reader();
    testUTF!Reader();
    test1Byte!Reader();
}
//Issue 257 - https://github.com/dlang-community/D-YAML/issues/257
@safe unittest
{
    import dub.internal.dyaml.loader : Loader;
    auto yaml = "hello ";
    auto root = Loader.fromString(yaml).load();

    assert(root.isValid);
}
