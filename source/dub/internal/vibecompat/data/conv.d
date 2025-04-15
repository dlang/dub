module dub.internal.vibecompat.data.conv;

import std.traits : OriginalType, Unqual;

string enumToString(E)(E value)
{
	import std.conv : to;

	switch (value) {
		default: return "cast("~E.stringof~")"~(cast(OriginalType!E)value).to!string;
		static foreach (m; __traits(allMembers, E)) {
			static if (!isDeprecated!(E, m)) {
				case __traits(getMember, E, m): return m;
			}
		}
	}
}

// wraps formattedWrite in a way that allows using a `scope` range without
// deprecation warnings
void formattedWriteFixed(size_t MAX_BYTES, R, ARGS...)(ref R sink, string format, ARGS args)
@safe {
	import std.format : formattedWrite;

	FixedAppender!(char[], MAX_BYTES) app;
	app.formattedWrite(format, args);
	sink.put(app.data);
}

private enum isDeprecated(alias parent, string symbol)
	= __traits(isDeprecated, __traits(getMember, parent, symbol));


/** Determines how to handle buffer overflows in `FixedAppender`.
*/
enum BufferOverflowMode {
	none,   /// Results in an ArrayBoundsError and terminates the application
	exception,  /// Throws an exception
	ignore  /// Skips any extraneous bytes written
}

struct FixedAppender(ArrayType : E[], size_t NELEM, BufferOverflowMode OM = BufferOverflowMode.none, E) {
	alias ElemType = Unqual!E;
	private {
		ElemType[NELEM] m_data;
		size_t m_fill;
	}

	void clear()
	{
		m_fill = 0;
	}

	void put(E el)
	{
		static if (OM == BufferOverflowMode.exception) {
			if (m_fill >= m_data.length)
				throw new Exception("Writing past end of FixedAppender");
		} else static if (OM == BufferOverflowMode.ignore) {
			if (m_fill >= m_data.length)
				return;
		}

		m_data[m_fill++] = el;
	}

	static if( is(ElemType == char) ){
		void put(dchar el)
		{
			import std.utf : encode;

			if( el < 128 ) put(cast(char)el);
			else {
				char[4] buf;
				auto len = encode(buf, el);
				put(cast(ArrayType)buf[0 .. len]);
			}
		}
	}

	static if( is(ElemType == wchar) ){
		void put(dchar el)
		{
			if( el < 128 ) put(cast(wchar)el);
			else {
				wchar[3] buf;
				auto len = std.utf.encode(buf, el);
				put(cast(ArrayType)buf[0 .. len]);
			}
		}
	}

	void put(ArrayType arr)
	{
		static if (OM == BufferOverflowMode.exception) {
			if (m_fill + arr.length > m_data.length) {
				put(arr[0 .. m_data.length - m_fill]);
				throw new Exception("Writing past end of FixedAppender");
			}
		} else static if (OM == BufferOverflowMode.ignore) {
			if (m_fill + arr.length > m_data.length) {
				put(arr[0 .. m_data.length - m_fill]);
				return;
			}
		}

		m_data[m_fill .. m_fill+arr.length] = arr[];
		m_fill += arr.length;
	}

	@property ArrayType data() { return cast(ArrayType)m_data[0 .. m_fill]; }

	static if (!is(E == immutable)) {
		void reset() { m_fill = 0; }
	}
}
