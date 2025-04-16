/**
 * Expose GenericPath & other symbols
 *
 * Becase `vibe.core.path` defines `NativePath` & co and we redefine it,
 * we need this extra module to avoid symbol conflicts.
 */
module dub.internal.vibecompat.inet.path2;

version (Have_vibe_core) public import vibe.core.path;
else:

import std.algorithm.searching : commonPrefix, endsWith, startsWith;
import std.algorithm.comparison : equal, min;
import std.algorithm.iteration : map;
import std.exception : enforce;
import std.range : empty, front, popFront, popFrontExactly, takeExactly;
import std.range.primitives : ElementType, isInputRange, isOutputRange, isForwardRange, save;
import std.traits : isArray, isInstanceOf, isSomeChar;
import std.utf : byChar;

public alias WindowsPath = GenericPath!WindowsPathFormat;
public alias PosixPath = GenericPath!PosixPathFormat;
public alias InetPath = GenericPath!InetPathFormat;
version (Windows)
    public alias NativePath = WindowsPath;
else
    public alias NativePath = PosixPath;

// for testing only, real one in path
public string toNativeString(T)(T path)
{
    return (cast(NativePath)path).toString();
}

/** Computes the relative path from `base_path` to this path.

	Params:
		path = The destination path
		base_path = The path from which the relative path starts

	See_also: `relativeToWeb`
*/
Path relativeTo(Path)(in Path path, in Path base_path) @safe
	if (isInstanceOf!(GenericPath, Path))
{
	import std.array : array, replicate;
	import std.range : chain, drop, take;

	assert(base_path.absolute, "Base path must be absolute for relativeTo.");
	assert(path.absolute, "Path must be absolute for relativeTo.");

	if (is(Path.Format == WindowsPathFormat)) { // FIXME: this shouldn't be a special case here!
		bool samePrefix(size_t n)
		{
			return path.bySegment.map!(n => n.encodedName).take(n).equal(base_path.bySegment.map!(n => n.encodedName).take(n));
		}
		// a path such as ..\C:\windows is not valid, so force the path to stay absolute in this case
		auto pref = path.bySegment;
		if (!pref.empty && pref.front.encodedName == "") {
			pref.popFront();
			if (!pref.empty) {
				// different drive?
				if (pref.front.encodedName.endsWith(':') && !samePrefix(2))
					return path;
				// different UNC path?
				if (pref.front.encodedName == "" && !samePrefix(4))
					return path;
			}
		}
	}

	auto nodes = path.bySegment;
	auto base_nodes = base_path.bySegment;

	// skip and count common prefix
	size_t base = 0;
	while (!nodes.empty && !base_nodes.empty && equal(nodes.front.name, base_nodes.front.name)) {
		nodes.popFront();
		base_nodes.popFront();
		base++;
	}

	enum up = Path.Segment2("..", Path.defaultSeparator);
	auto ret = Path(base_nodes.map!(p => up).chain(nodes));
	if (path.endsWithSlash) {
		if (ret.empty) return Path.fromTrustedString("." ~ path.toString()[$-1]);
		else ret.endsWithSlash = true;
	}
	return ret;
}

///
unittest {
	import std.array : array;
	import std.conv : to;
	assert(PosixPath("/some/path").relativeTo(PosixPath("/")) == PosixPath("some/path"));
	assert(PosixPath("/some/path/").relativeTo(PosixPath("/some/other/path/")) == PosixPath("../../path/"));
	assert(PosixPath("/some/path/").relativeTo(PosixPath("/some/other/path")) == PosixPath("../../path/"));

	assert(WindowsPath("C:\\some\\path").relativeTo(WindowsPath("C:\\")) == WindowsPath("some\\path"));
	assert(WindowsPath("C:\\some\\path\\").relativeTo(WindowsPath("C:\\some\\other\\path/")) == WindowsPath("..\\..\\path\\"));
	assert(WindowsPath("C:\\some\\path\\").relativeTo(WindowsPath("C:\\some\\other\\path")) == WindowsPath("..\\..\\path\\"));

	assert(WindowsPath("\\\\server\\share\\some\\path").relativeTo(WindowsPath("\\\\server\\share\\")) == WindowsPath("some\\path"));
	assert(WindowsPath("\\\\server\\share\\some\\path\\").relativeTo(WindowsPath("\\\\server\\share\\some\\other\\path/")) == WindowsPath("..\\..\\path\\"));
	assert(WindowsPath("\\\\server\\share\\some\\path\\").relativeTo(WindowsPath("\\\\server\\share\\some\\other\\path")) == WindowsPath("..\\..\\path\\"));

	assert(WindowsPath("C:\\some\\path").relativeTo(WindowsPath("D:\\")) == WindowsPath("C:\\some\\path"));
	assert(WindowsPath("C:\\some\\path\\").relativeTo(WindowsPath("\\\\server\\share")) == WindowsPath("C:\\some\\path\\"));
	assert(WindowsPath("\\\\server\\some\\path\\").relativeTo(WindowsPath("C:\\some\\other\\path")) == WindowsPath("\\\\server\\some\\path\\"));
	assert(WindowsPath("\\\\server\\some\\path\\").relativeTo(WindowsPath("\\\\otherserver\\path")) == WindowsPath("\\\\server\\some\\path\\"));
	assert(WindowsPath("\\some\\path\\").relativeTo(WindowsPath("\\other\\path")) == WindowsPath("..\\..\\some\\path\\"));

	assert(WindowsPath("\\\\server\\share\\path1").relativeTo(WindowsPath("\\\\server\\share\\path2")) == WindowsPath("..\\path1"));
	assert(WindowsPath("\\\\server\\share\\path1").relativeTo(WindowsPath("\\\\server\\share2\\path2")) == WindowsPath("\\\\server\\share\\path1"));
	assert(WindowsPath("\\\\server\\share\\path1").relativeTo(WindowsPath("\\\\server2\\share2\\path2")) == WindowsPath("\\\\server\\share\\path1"));
}

unittest {
	{
		auto parentpath = "/path/to/parent";
		auto parentpathp = PosixPath(parentpath);
		auto subpath = "/path/to/parent/sub/";
		auto subpathp = PosixPath(subpath);
		auto subpath_rel = "sub/";
		assert(subpathp.relativeTo(parentpathp).toString() == subpath_rel);
		auto subfile = "/path/to/parent/child";
		auto subfilep = PosixPath(subfile);
		auto subfile_rel = "child";
		assert(subfilep.relativeTo(parentpathp).toString() == subfile_rel);
	}

	{ // relative paths across Windows devices are not allowed
		auto p1 = WindowsPath("\\\\server\\share"); assert(p1.absolute);
		auto p2 = WindowsPath("\\\\server\\othershare"); assert(p2.absolute);
		auto p3 = WindowsPath("\\\\otherserver\\share"); assert(p3.absolute);
		auto p4 = WindowsPath("C:\\somepath"); assert(p4.absolute);
		auto p5 = WindowsPath("C:\\someotherpath"); assert(p5.absolute);
		auto p6 = WindowsPath("D:\\somepath"); assert(p6.absolute);
		auto p7 = WindowsPath("\\\\server\\share\\path"); assert(p7.absolute);
		auto p8 = WindowsPath("\\\\server\\share\\otherpath"); assert(p8.absolute);
		assert(p4.relativeTo(p5) == WindowsPath("..\\somepath"));
		assert(p4.relativeTo(p6) == WindowsPath("C:\\somepath"));
		assert(p4.relativeTo(p1) == WindowsPath("C:\\somepath"));
		assert(p1.relativeTo(p2) == WindowsPath("\\\\server\\share"));
		assert(p1.relativeTo(p3) == WindowsPath("\\\\server\\share"));
		assert(p1.relativeTo(p4) == WindowsPath("\\\\server\\share"));
		assert(p7.relativeTo(p1) == WindowsPath("path"));
		assert(p7.relativeTo(p8) == WindowsPath("..\\path"));
	}

	{ // relative path, trailing slash
		auto p1 = PosixPath("/some/path");
		auto p2 = PosixPath("/some/path/");
		assert(p1.relativeTo(p1).toString() == "");
		assert(p1.relativeTo(p2).toString() == "");
		assert(p2.relativeTo(p2).toString() == "./");
	}

    {
        immutable PosixPath p1 = PosixPath("/foo/bar");
        immutable PosixPath p2 = PosixPath("/foo");
        immutable PosixPath result = p1.relativeTo(p2);
        assert(result == PosixPath("bar"));
    }
}

nothrow unittest {
	auto p1 = PosixPath.fromTrustedString("/foo/bar/baz");
	auto p2 = PosixPath.fromTrustedString("/foo/baz/bam");
	assert(p2.relativeTo(p1).toString == "../../baz/bam");
}


/** Computes the relative path to this path from `base_path` using web path rules.

	The difference to `relativeTo` is that a path not ending in a slash
	will not be considered as a path to a directory and the parent path
	will instead be used.

	Params:
		path = The destination path
		base_path = The path from which the relative path starts

	See_also: `relativeTo`
*/
Path relativeToWeb(Path)(Path path, Path base_path) @safe
	if (isInstanceOf!(GenericPath, Path))
{
	if (!base_path.endsWithSlash) {
		assert(base_path.absolute, "Base path must be absolute for relativeToWeb.");
		if (base_path.hasParentPath) base_path = base_path.parentPath;
		else base_path = Path("/");
		assert(base_path.absolute);
	}
	return path.relativeTo(base_path);
}

///
/+unittest {
	assert(InetPath("/some/path").relativeToWeb(InetPath("/")) == InetPath("some/path"));
	assert(InetPath("/some/path/").relativeToWeb(InetPath("/some/other/path/")) == InetPath("../../path/"));
	assert(InetPath("/some/path/").relativeToWeb(InetPath("/some/other/path")) == InetPath("../path/"));
}+/

/// Provides a common interface to operate on paths of various kinds.
struct GenericPath(F) {
@safe:
	alias Format = F;

	/// vibe-core 1.x compatibility alias
	alias Segment2 = Segment;

	/** A single path segment.
	*/
	static struct Segment {
		@safe:

		private {
			string m_encodedName;
			char m_separator = 0;
		}

		/** Constructs a new path segment including an optional trailing
			separator.

			Params:
				name = The raw (unencoded) name of the path segment
				separator = Optional trailing path separator (e.g. `'/'`)

			Throws:
				A `PathValidationException` is thrown if the name contains
				characters that are invalid for the path type. In particular,
				any path separator characters may not be part of the name.
		*/
		this(string name, char separator = '\0')
		{
			import std.algorithm.searching : any;

			enforce!PathValidationException(separator == '\0' || Format.isSeparator(separator),
				"Invalid path separator.");
			auto err = Format.validateDecodedSegment(name);
			enforce!PathValidationException(err is null, err);

			m_encodedName = Format.encodeSegment(name);
			m_separator = separator;
		}

		/** Constructs a path segment without performing validation.

			Note that in debug builds, there are still assertions in place
			that verify that the provided values are valid.

			Params:
				name = The raw (unencoded) name of the path segment
				separator = Optional trailing path separator (e.g. `'/'`)
		*/
		static Segment fromTrustedString(string name, char separator = '\0')
		nothrow pure {
			import std.algorithm.searching : any;
			assert(separator == '\0' || Format.isSeparator(separator));
			assert(Format.validateDecodedSegment(name) is null, "Invalid path segment.");
			return fromTrustedEncodedString(Format.encodeSegment(name), separator);
		}

		/** Constructs a path segment without performing validation.

			Note that in debug builds, there are still assertions in place
			that verify that the provided values are valid.

			Params:
				encoded_name = The encoded name of the path segment
				separator = Optional trailing path separator (e.g. `'/'`)
		*/
		static Segment fromTrustedEncodedString(string encoded_name, char separator = '\0')
		nothrow @nogc pure {
			import std.algorithm.searching : any;
			import std.utf : byCodeUnit;

			assert(separator == '\0' || Format.isSeparator(separator));
			assert(!encoded_name.byCodeUnit.any!(c => Format.isSeparator(c)));
			assert(Format.validatePath(encoded_name) is null, "Invalid path segment.");

			Segment ret;
			ret.m_encodedName = encoded_name;
			ret.m_separator = separator;
			return ret;
		}

		/** The (file/directory) name of the path segment.

			Note: Depending on the path type, this may return a generic range
			type instead of `string`. Use `name.to!string` in that
			case if you need an actual `string`.
		*/
		@property auto name()
		const nothrow @nogc {
			auto ret = Format.decodeSingleSegment(m_encodedName);

			static if (is(typeof(ret) == string)) return ret;
			else {
				static struct R {
					private typeof(ret) m_value;

					@property bool empty() const { return m_value.empty; }
					@property R save() const { return R(m_value.save); }
					@property char front() const { return m_value.front; }
					@property void popFront() { m_value.popFront(); }
					@property char back() const { return m_value.back; }
					@property void popBack() { m_value.popBack(); }

					string toString()
					const @safe nothrow {
						import std.conv : to;
						try return m_value.save.to!string;
						catch (Exception e) assert(false, e.msg);
					}
				}

				return R(ret);
			}
		}

		unittest {
			import std.conv : to;
			auto path = InetPath("/foo%20bar");
			assert(path.head.encodedName == "foo%20bar");
			assert(path.head.name.toString() == "foo bar");
			assert(path.head.name.to!string == "foo bar");
			assert(path.head.name.equal("foo bar"));
		}


		/// The encoded representation of the path segment name
		@property string encodedName() const nothrow @nogc { return m_encodedName; }
		/// The trailing separator (e.g. `'/'`) or `'\0'`.
		@property char separator() const nothrow @nogc { return m_separator; }
		/// ditto
		@property void separator(char ch) {
			enforce!PathValidationException(ch == '\0' || Format.isSeparator(ch),
				"Character is not a valid path separator.");
			m_separator = ch;
		}
		/// Returns `true` $(I iff) the segment has a trailing path separator.
		@property bool hasSeparator() const nothrow @nogc { return m_separator != '\0'; }


		/** The extension part of the file name.

			If the file name contains an extension, this returns a forward range
			with the extension including the leading dot. Otherwise an empty
			range is returned.

			See_also: `stripExtension`
		*/
		@property auto extension()
		const nothrow @nogc {
			return .extension(this.name);
		}

		///
		unittest {
			assert(PosixPath("/foo/bar.txt").head.extension.equal(".txt"));
			assert(PosixPath("/foo/bar").head.extension.equal(""));
			assert(PosixPath("/foo/.bar").head.extension.equal(""));
			assert(PosixPath("/foo/.bar.txt").head.extension.equal(".txt"));
		}


		/** Returns the file base name, excluding the extension.

			See_also: `extension`
		*/
		@property auto withoutExtension()
		const nothrow @nogc {
			return .stripExtension(this.name);
		}

		///
		unittest {
			assert(PosixPath("/foo/bar.txt").head.withoutExtension.equal("bar"));
			assert(PosixPath("/foo/bar").head.withoutExtension.equal("bar"));
			assert(PosixPath("/foo/.bar").head.withoutExtension.equal(".bar"));
			assert(PosixPath("/foo/.bar.txt").head.withoutExtension.equal(".bar"));
		}


		/** Converts the segment to another path type.

			The segment name will be re-validated during the conversion. The
			separator, if any, will be adopted or replaced by the default
			separator of the target path type.

			Throws:
				A `PathValidationException` is thrown if the segment name cannot
				be represented in the target path format.
		*/
		GenericPath!F.Segment opCast(T : GenericPath!F.Segment, F)()
		const {
			import std.array : array;

			char dsep = '\0';
			if (m_separator) {
				if (F.isSeparator(m_separator)) dsep = m_separator;
				else dsep = F.defaultSeparator;
			}
			static if (is(typeof(this.name) == string))
				string n = this.name;
			else
				string n = this.name.array;
			return GenericPath!F.Segment(n, dsep);
		}

		/// Compares two path segment names
		bool opEquals(Segment other)
		const nothrow @nogc {
			try return equal(this.name, other.name) && this.hasSeparator == other.hasSeparator;
			catch (Exception e) assert(false, e.msg);
		}
		/// ditto
		bool opEquals(string name)
		const nothrow @nogc {
			import std.utf : byCodeUnit;
			try return equal(this.name, name.byCodeUnit);
			catch (Exception e) assert(false, e.msg);
		}
	}

	private {
		string m_path;
	}

	/// The default path segment separator character.
	enum char defaultSeparator = Format.defaultSeparator;

	/** Constructs a path from its string representation.

		Throws:
			A `PathValidationException` is thrown if the given path string
			is not valid.
	*/
	this(string p)
	{
		auto err = Format.validatePath(p);
		enforce!PathValidationException(err is null, err);
		m_path = p;
	}

	/** Constructs a path from a single path segment.

		This is equivalent to calling the range based constructor with a
		single-element range.
	*/
	this(Segment segment)
	{
		import std.range : only;
		this(only(segment));
	}

	/** Constructs a path from an input range of `Segment`s.

		Throws:
			Since path segments are pre-validated, this constructor does not
			throw an exception.
	*/
	this(R)(R segments)
		if (isInputRange!R && is(ElementType!R : Segment))
	{
		import std.array : appender;
		auto dst = appender!string;
		Format.toString(segments, dst);
		m_path = dst.data;
	}

	/** Constructs a path from its string representation.

		This is equivalent to calling the string based constructor.
	*/
	static GenericPath fromString(string p)
	{
		return GenericPath(p);
	}

	/** Constructs a path from its string representation, skipping the
		validation.

		Note that it is required to pass a pre-validated path string
		to this function. Debug builds will enforce this with an assertion.
	*/
	static GenericPath fromTrustedString(string p)
	nothrow @nogc {
		if (auto val = Format.validatePath(p)) {
            import std.stdio; debug writeln(p);
			assert(false, val);
        }

		GenericPath ret;
		ret.m_path = p;
		return ret;
	}

	/// Tests if a certain character is a path segment separator.
	static bool isSeparator(dchar ch) { return ch < 0x80 && Format.isSeparator(cast(char)ch); }

	/// Tests if the path is represented by an empty string.
	@property bool empty() const nothrow @nogc { return m_path.length == 0; }

	/// Tests if the path is absolute.
	@property bool absolute() const nothrow @nogc { return Format.getAbsolutePrefix(m_path).length > 0; }

	/// Determines whether the path ends with a path separator (i.e. represents a folder specifically).
	@property bool endsWithSlash() const nothrow @nogc { return m_path.length > 0 && Format.isSeparator(m_path[$-1]); }
	/// ditto
	@property void endsWithSlash(bool v)
	nothrow {
		bool ews = this.endsWithSlash;
		if (!ews && v) m_path ~= Format.defaultSeparator;
		else if (ews && !v) m_path = m_path[0 .. $-1]; // FIXME?: "/test//" -> "/test/"
	}

	/// vibe-core 1.x compatibility alias
	alias bySegment2 = bySegment;

	/** Iterates over the individual segments of the path.

		Returns a forward range of `Segment`s.
	*/
	@property auto bySegment()
	const {
		static struct R {
			import std.traits : ReturnType;

			private {
				string m_path;
				Segment m_front;
			}

			private this(string path)
			{
				m_path = path;
				if (m_path.length) {
					auto ap = Format.getAbsolutePrefix(m_path);
					if (ap.length && !Format.isSeparator(ap[0]))
						m_front = Segment.fromTrustedEncodedString(null, Format.defaultSeparator);
					else readFront();
				}
			}

			@property bool empty() const nothrow @nogc { return m_path.length == 0 && m_front == Segment.init; }

			@property R save() { return this; }

			@property Segment front() { return m_front; }

			void popFront()
			nothrow {
				assert(m_front != Segment.init);
				if (m_path.length) readFront();
				else m_front = Segment.init;
			}

			private void readFront()
			{
				auto n = Format.getFrontNode(m_path);
				m_path = m_path[n.length .. $];

				char sep = '\0';
				if (Format.isSeparator(n[$-1])) {
					sep = n[$-1];
					n = n[0 .. $-1];
				}
				m_front = Segment.fromTrustedEncodedString(n, sep);
				assert(m_front != Segment.init);
			}
		}

		return R(m_path);
	}

	///
	unittest {
		InetPath p = "foo/bar/baz";
		assert(p.bySegment.equal([
			InetPath.Segment("foo", '/'),
			InetPath.Segment("bar", '/'),
			InetPath.Segment("baz")
		]));
	}


	/** Iterates over the path by segment, each time returning the sub path
		leading to that segment.
	*/
	@property auto byPrefix()
	const nothrow @nogc {
		static struct R {
			import std.traits : ReturnType;

			private {
				string m_path;
				string m_remainder;
			}

			private this(string path)
			{
				m_path = path;
				m_remainder = path;
				if (m_path.length) {
					auto ap = Format.getAbsolutePrefix(m_path);
					if (ap.length && !Format.isSeparator(ap[0]))
						m_remainder = m_remainder[ap.length .. $];
					else popFront();
				}
			}

			@property bool empty() const nothrow @nogc
			{
				return m_path.length == 0;
			}

			@property R save() { return this; }

			@property GenericPath front()
			{
				return GenericPath.fromTrustedString(m_path[0 .. $-m_remainder.length]);
			}

			void popFront()
			nothrow {
				assert(m_remainder.length > 0 || m_path.length > 0);
				if (m_remainder.length) readFront();
				else m_path = "";
			}

			private void readFront()
			{
				auto n = Format.getFrontNode(m_remainder);
				m_remainder = m_remainder[n.length .. $];
			}
		}

		return R(m_path);
	}

	///
	version (none) unittest {
		assert(InetPath("foo/bar/baz").byPrefix
			.equal([
				InetPath("foo/"),
				InetPath("foo/bar/"),
				InetPath("foo/bar/baz")
			]));

		assert(InetPath("/foo/bar").byPrefix
			.equal([
				InetPath("/"),
				InetPath("/foo/"),
				InetPath("/foo/bar"),
			]));
	}

	// vibe-core 1.x compatibility alias
	alias head2 = head;

	/// Returns the trailing segment of the path.
	@property Segment head()
	const @nogc {
		auto n = Format.getBackNode(m_path);
		char sep = '\0';
		if (n.length > 0 && Format.isSeparator(n[$-1])) {
			sep = n[$-1];
			n = n[0 .. $-1];
		}
		return Segment.fromTrustedEncodedString(n, sep);
	}

	/** Determines if the `parentPath` property is valid.
	*/
	@property bool hasParentPath()
	const @nogc {
		auto b = Format.getBackNode(m_path);
		return b.length < m_path.length;
	}

	/** Returns a prefix of this path, where the last segment has been dropped.

		Throws:
			An `Exception` is thrown if this path has no parent path. Use
			`hasParentPath` to test this upfront.
	*/
	@property GenericPath parentPath()
	const @nogc {
		auto b = Format.getBackNode(m_path);
		() @trusted {
			static __gshared e = new Exception("Path has no parent path");
			if (b.length >= m_path.length) throw e;
		} ();
		return GenericPath.fromTrustedString(m_path[0 .. $ - b.length]);
	}


	/** The extension part of the file name pointed to by the path.

		If the path is not empty and its head segment has  an extension, this
		returns a forward range with the extension including the leading dot.
		Otherwise an empty range is returned.

		See `Segment.extension` for a full description.

		See_also: `Segment.extension`, `Segment.stripExtension`
	*/
	@property auto fileExtension()
	const nothrow @nogc {
		if (this.empty) return typeof(this.head.extension).init;
		return this.head.extension;
	}


	/** Returns the normalized form of the path.

		See `normalize` for a full description.
	*/
	@property GenericPath normalized()
	const {
		GenericPath ret = this;
		ret.normalize();
		return ret;
	}

	unittest {
		assert(PosixPath("foo/../bar").normalized == PosixPath("bar"));
		assert(PosixPath("foo//./bar/../baz").normalized == PosixPath("foo/baz"));
	}


	/** Removes any redundant path segments and replaces all separators by the
		default one.

		The resulting path representation is suitable for basic semantic
		comparison to other normalized paths.

		Note that there are still ways for different normalized paths to
		represent the same file. Examples of this are the tilde shortcut to the
		home directory on Unix and Linux operating systems, symbolic or hard
		links, and possibly environment variables are examples of this.

		Throws:
			Throws an `Exception` if an absolute path contains parent directory
			segments ("..") that lead to a path that is a parent path of the
			root path.
	*/
	void normalize()
	{
		import std.array : appender, join;

		Segment[] newnodes;
		bool got_non_sep = false;
		foreach (n; this.bySegment) {
			if (n.hasSeparator) n.separator = Format.defaultSeparator;
			if (!got_non_sep) {
				if (n.encodedName == "") newnodes ~= n;
				else got_non_sep = true;
			}
			switch (n.encodedName) {
				default: newnodes ~= n; break;
				case "", ".": break;
				case "..":
					enforce(!this.absolute || newnodes.length > 0, "Path goes below root node.");
					if (newnodes.length > 0 && newnodes[$-1].encodedName != "..") newnodes = newnodes[0 .. $-1];
					else newnodes ~= n;
					break;
			}
		}

		auto dst = appender!string;
		Format.toString(newnodes, dst);
		m_path = dst.data;
	}

	///
	unittest {
		auto path = WindowsPath("C:\\test/foo/./bar///../baz");
		path.normalize();
		assert(path.toString() == "C:\\test\\foo\\baz", path.toString());

		path = WindowsPath("foo/../../bar/");
		path.normalize();
		assert(path.toString() == "..\\bar\\");
	}

	/// Returns the string representation of the path.
	string toString() const nothrow @nogc { return m_path; }

	/// Computes a hash sum, enabling storage within associative arrays.
	size_t toHash() const nothrow @trusted
	{
		try return typeid(string).getHash(&m_path);
		catch (Exception e) assert(false, "getHash for string throws!?");
	}

	/** Compares two path objects.

		Note that the exact string representation of the two paths will be
		compared. To get a basic semantic comparison, the paths must be
		normalized first.
	*/
	bool opEquals(GenericPath other) const @nogc { return this.m_path == other.m_path; }

	/** Converts the path to a different path format.

		Throws:
			A `PathValidationException` will be thrown if the path is not
			representable in the requested path format. This can happen
			especially when converting Posix or Internet paths to windows paths,
			since Windows paths cannot contain a number of characters that the
			other representations can, in theory.
	*/
	P opCast(P)() const if (isInstanceOf!(.GenericPath, P)) {
		static if (is(P == GenericPath)) return this;
		else return P(this.bySegment.map!(n => cast(P.Segment)n));
	}

	/** Concatenates two paths.

		The right hand side must represent a relative path.
	*/
	GenericPath opBinary(string op : "~")(string subpath) const { return this ~ GenericPath(subpath); }
	/// ditto
	GenericPath opBinary(string op : "~")(Segment subpath) const { return this ~ GenericPath(subpath); }
	/// ditto
	GenericPath opBinary(string op : "~", F)(GenericPath!F.Segment subpath) const { return this ~ cast(Segment)(subpath); }
	/// ditto
	GenericPath opBinary(string op : "~")(GenericPath subpath) const nothrow {
		assert(!subpath.absolute || m_path.length == 0, "Cannot append absolute path.");
		if (endsWithSlash || empty) return GenericPath.fromTrustedString(m_path ~ subpath.m_path);
		else return GenericPath.fromTrustedString(m_path ~ Format.defaultSeparator ~ subpath.m_path);
	}
	/// ditto
	GenericPath opBinary(string op : "~", F)(GenericPath!F subpath) const if (!is(F == Format)) { return this ~ cast(GenericPath)subpath; }
	/// ditto
	GenericPath opBinary(string op : "~", R)(R entries) const nothrow
		if (isInputRange!R && is(ElementType!R : Segment))
	{
		return this ~ GenericPath(entries);
	}

	/// Appends a relative path to this path.
	void opOpAssign(string op : "~", T)(T op) { this = this ~ op; }

	/** Tests whether the given path is a prefix of this path.

		Any path separators will be ignored during the comparison.
	*/
	bool startsWith(GenericPath prefix)
	const nothrow {
		return bySegment.map!(n => n.name).startsWith(prefix.bySegment.map!(n => n.name));
	}
}

unittest {
	assert(PosixPath("hello/world").bySegment.equal([PosixPath.Segment("hello",'/'), PosixPath.Segment("world")]));
	assert(PosixPath("/hello/world/").bySegment.equal([PosixPath.Segment("",'/'), PosixPath.Segment("hello",'/'), PosixPath.Segment("world",'/')]));
	assert(PosixPath("hello\\world").bySegment.equal([PosixPath.Segment("hello\\world")]));
	assert(WindowsPath("hello/world").bySegment.equal([WindowsPath.Segment("hello",'/'), WindowsPath.Segment("world")]));
	assert(WindowsPath("/hello/world/").bySegment.equal([WindowsPath.Segment("",'/'), WindowsPath.Segment("hello",'/'), WindowsPath.Segment("world",'/')]));
	assert(WindowsPath("hello\\w/orld").bySegment.equal([WindowsPath.Segment("hello",'\\'), WindowsPath.Segment("w",'/'), WindowsPath.Segment("orld")]));
	assert(WindowsPath("hello/w\\orld").bySegment.equal([WindowsPath.Segment("hello",'/'), WindowsPath.Segment("w",'\\'), WindowsPath.Segment("orld")]));

    version (none) {
	assert(PosixPath("hello/world").byPrefix.equal([PosixPath("hello/"), PosixPath("hello/world")]));
	assert(PosixPath("/hello/world/").byPrefix.equal([PosixPath("/"), PosixPath("/hello/"), PosixPath("/hello/world/")]));
	assert(WindowsPath("C:\\Windows").byPrefix.equal([WindowsPath("C:\\"), WindowsPath("C:\\Windows")]));
    }
}

unittest
{
	{
		auto dotpath = "/test/../test2/././x/y";
		auto dotpathp = PosixPath(dotpath);
		assert(dotpathp.toString() == "/test/../test2/././x/y");
		dotpathp.normalize();
		assert(dotpathp.toString() == "/test2/x/y", dotpathp.toString());
	}

	{
		auto dotpath = "/test/..////test2//./x/y";
		auto dotpathp = PosixPath(dotpath);
		assert(dotpathp.toString() == "/test/..////test2//./x/y");
		dotpathp.normalize();
		assert(dotpathp.toString() == "/test2/x/y");
	}

	assert(WindowsPath("C:\\Windows").absolute);
	assert((cast(InetPath)WindowsPath("C:\\Windows")).toString() == "/C:/Windows");
	assert((WindowsPath("C:\\Windows") ~ InetPath("test/this")).toString() == "C:\\Windows\\test/this");
	assert(InetPath("/C:/Windows").absolute);
	assert((cast(WindowsPath)InetPath("/C:/Windows")).toString() == "C:/Windows");
	assert((InetPath("/C:/Windows") ~ WindowsPath("test\\this")).toString() == "/C:/Windows/test/this");
	assert((InetPath("") ~ WindowsPath("foo\\bar")).toString() == "foo/bar");
	assert((cast(InetPath)WindowsPath("C:\\Windows\\")).toString() == "/C:/Windows/");

	assert(NativePath("").empty);

	assert(PosixPath("/") ~ NativePath("foo/bar") == PosixPath("/foo/bar"));
	assert(PosixPath("") ~ NativePath("foo/bar") == PosixPath("foo/bar"));
	assert(PosixPath("foo") ~ NativePath("bar") == PosixPath("foo/bar"));
	assert(PosixPath("foo/") ~ NativePath("bar") == PosixPath("foo/bar"));

	{
		auto unc = "\\\\server\\share\\path";
		auto uncp = WindowsPath(unc);
		assert(uncp.absolute);
		uncp.normalize();
		version(Windows) assert(uncp.toNativeString() == unc);
		assert(uncp.absolute);
		assert(!uncp.endsWithSlash);
	}

	{
		auto abspath = "/test/path/";
		auto abspathp = PosixPath(abspath);
		assert(abspathp.toString() == abspath);
		version(Windows) {} else assert(abspathp.toNativeString() == abspath);
		assert(abspathp.absolute);
		assert(abspathp.endsWithSlash);
		alias S = PosixPath.Segment;
		assert(abspathp.bySegment.equal([S("", '/'), S("test", '/'), S("path", '/')]));
	}

	{
		auto relpath = "test/path/";
		auto relpathp = PosixPath(relpath);
		assert(relpathp.toString() == relpath);
		version(Windows) assert(relpathp.toNativeString() == "test/path/");
		else assert(relpathp.toNativeString() == relpath);
		assert(!relpathp.absolute);
		assert(relpathp.endsWithSlash);
		alias S = PosixPath.Segment;
		assert(relpathp.bySegment.equal([S("test", '/'), S("path", '/')]));
	}

	{
		auto winpath = "C:\\windows\\test";
		auto winpathp = WindowsPath(winpath);
		assert(winpathp.toString() == "C:\\windows\\test");
		assert((cast(PosixPath)winpathp).toString() == "/C:/windows/test", (cast(PosixPath)winpathp).toString());
		version(Windows) assert(winpathp.toNativeString() == winpath);
		else assert(winpathp.toNativeString() == "/C:/windows/test", winpathp.toNativeString());
		assert(winpathp.absolute);
		assert(!winpathp.endsWithSlash);
		alias S = WindowsPath.Segment;
		assert(winpathp.bySegment.equal([S("", '/'), S("C:", '\\'), S("windows", '\\'), S("test")]));
	}
}

@safe unittest {
	import std.array : appender;
	auto app = appender!(PosixPath[]);
	void test1(PosixPath p) { app.put(p); }
	void test2(PosixPath[] ps) { app.put(ps); }
	//void test3(const(PosixPath) p) { app.put(p); } // DMD issue 17251
	//void test4(const(PosixPath)[] ps) { app.put(ps); }
}

unittest {
	import std.exception : assertThrown, assertNotThrown;

	assertThrown!PathValidationException(WindowsPath.Segment("foo/bar"));
	assertThrown!PathValidationException(PosixPath.Segment("foo/bar"));
	assertNotThrown!PathValidationException(InetPath.Segment("foo/bar"));

	auto p = InetPath("/foo%2fbar/");
	import std.conv : to;
	assert(p.bySegment.equal([InetPath.Segment("",'/'), InetPath.Segment("foo/bar",'/')]), p.bySegment.to!string);
	p ~= InetPath.Segment("baz/bam");
	assert(p.toString() == "/foo%2fbar/baz%2Fbam", p.toString);
}

unittest {
	assert(!PosixPath("").hasParentPath);
	assert(!PosixPath("/").hasParentPath);
	assert(!PosixPath("foo\\bar").hasParentPath);
	assert(PosixPath("foo/bar").parentPath.toString() == "foo/");
	assert(PosixPath("./foo").parentPath.toString() == "./");
	assert(PosixPath("./foo").parentPath.toString() == "./");

	assert(!WindowsPath("").hasParentPath);
	assert(!WindowsPath("/").hasParentPath);
	assert(WindowsPath("foo\\bar").parentPath.toString() == "foo\\");
	assert(WindowsPath("foo/bar").parentPath.toString() == "foo/");
	assert(WindowsPath("./foo").parentPath.toString() == "./");
	assert(WindowsPath("./foo").parentPath.toString() == "./");

	assert(!InetPath("").hasParentPath);
	assert(!InetPath("/").hasParentPath);
	assert(InetPath("foo/bar").parentPath.toString() == "foo/");
	assert(InetPath("foo/bar%2Fbaz").parentPath.toString() == "foo/");
	assert(InetPath("./foo").parentPath.toString() == "./");
	assert(InetPath("./foo").parentPath.toString() == "./");
}

unittest {
	assert(WindowsPath([WindowsPath.Segment("foo"), WindowsPath.Segment("bar")]).toString() == "foo\\bar");
}

unittest {
	assert(WindowsPath([WindowsPath.Segment("foo"), WindowsPath.Segment("bar")]).toString() == "foo\\bar");
}

/// Thrown when an invalid string representation of a path is detected.
class PathValidationException : Exception {
	this(string text, string file = __FILE__, size_t line = cast(size_t)__LINE__, Throwable next = null)
		pure nothrow @nogc @safe
	{
		super(text, file, line, next);
	}
}

/** Implements Windows path semantics.

	See_also: `WindowsPath`
*/
struct WindowsPathFormat {
	static void toString(I, O)(I segments, O dst)
		if (isInputRange!I && isOutputRange!(O, char))
	{
		char sep(char s) { return isSeparator(s) ? s : defaultSeparator; }

		if (segments.empty) return;

		if (segments.front.name == "" && segments.front.separator) {
			auto s = segments.front.separator;
			segments.popFront();
			if (segments.empty || !segments.front.name.endsWith(":"))
				dst.put(sep(s));
		}

		char lastsep = '\0';
		bool first = true;
		foreach (s; segments) {
			if (!first || lastsep) dst.put(sep(lastsep));
			else first = false;
			dst.put(s.name);
			lastsep = s.separator;
		}
		if (lastsep) dst.put(sep(lastsep));
	}

	unittest {
		import std.array : appender;
		struct Segment { string name; char separator = 0; static Segment fromTrustedString(string str, char sep = 0) pure nothrow @nogc { return Segment(str, sep); }}
		string str(Segment[] segs...) { auto ret = appender!string; toString(segs, ret); return ret.data; }

		assert(str() == "");
		assert(str(Segment("",'/')) == "/");
		assert(str(Segment("",'/'), Segment("foo")) == "/foo");
		assert(str(Segment("",'\\')) == "\\");
		assert(str(Segment("foo",'/'), Segment("bar",'/')) == "foo/bar/");
		assert(str(Segment("",'/'), Segment("foo",'\0')) == "/foo");
		assert(str(Segment("",'\\'), Segment("foo",'\\')) == "\\foo\\");
		assert(str(Segment("f oo")) == "f oo");
		assert(str(Segment("",'\\'), Segment("C:")) == "C:");
		assert(str(Segment("",'\\'), Segment("C:", '/')) == "C:/");
		assert(str(Segment("foo",'\\'), Segment("C:")) == "foo\\C:");
		assert(str(Segment("foo"), Segment("bar")) == "foo\\bar");
	}

@safe nothrow pure:
	enum defaultSeparator = '\\';

	static bool isSeparator(dchar ch)
	@nogc {
		return ch == '\\' || ch == '/';
	}

	static string getAbsolutePrefix(string path)
	@nogc {
		if (!path.length) return null;

		if (isSeparator(path[0])) {
			return path[0 .. 1];
		}

		foreach (i; 1 .. path.length)
			if (isSeparator(path[i])) {
				if (path[i-1] == ':') return path[0 .. i+1];
				break;
			}

		return path[$-1] == ':' ? path : null;
	}

	unittest {
		assert(getAbsolutePrefix("test") == "");
		assert(getAbsolutePrefix("test/") == "");
		assert(getAbsolutePrefix("/test") == "/");
		assert(getAbsolutePrefix("\\test") == "\\");
		assert(getAbsolutePrefix("C:\\") == "C:\\");
		assert(getAbsolutePrefix("C:") == "C:");
		assert(getAbsolutePrefix("C:\\test") == "C:\\");
		assert(getAbsolutePrefix("C:\\test\\") == "C:\\");
		assert(getAbsolutePrefix("C:/") == "C:/");
		assert(getAbsolutePrefix("C:/test") == "C:/");
		assert(getAbsolutePrefix("C:/test/") == "C:/");
		assert(getAbsolutePrefix("\\\\server") == "\\");
		assert(getAbsolutePrefix("\\\\server\\") == "\\");
		assert(getAbsolutePrefix("\\\\.\\") == "\\");
		assert(getAbsolutePrefix("\\\\?\\") == "\\");
	}

	static string getFrontNode(string path)
	@nogc {
		foreach (i; 0 .. path.length)
			if (isSeparator(path[i]))
				return path[0 .. i+1];
		return path;
	}

	unittest {
		assert(getFrontNode("") == "");
		assert(getFrontNode("/bar") == "/");
		assert(getFrontNode("foo/bar") == "foo/");
		assert(getFrontNode("foo/") == "foo/");
		assert(getFrontNode("foo") == "foo");
		assert(getFrontNode("\\bar") == "\\");
		assert(getFrontNode("foo\\bar") == "foo\\");
		assert(getFrontNode("foo\\") == "foo\\");
	}

	static string getBackNode(string path)
	@nogc {
		if (!path.length) return path;
		foreach_reverse (i; 0 .. path.length-1)
			if (isSeparator(path[i]))
				return path[i+1 .. $];
		return path;
	}

	unittest {
		assert(getBackNode("") == "");
		assert(getBackNode("/bar") == "bar");
		assert(getBackNode("foo/bar") == "bar");
		assert(getBackNode("foo/") == "foo/");
		assert(getBackNode("foo") == "foo");
		assert(getBackNode("\\bar") == "bar");
		assert(getBackNode("foo\\bar") == "bar");
		assert(getBackNode("foo\\") == "foo\\");
	}

	static string decodeSingleSegment(string segment)
	@nogc {
		assert(segment.length == 0 || segment[$-1] != '/');
		return segment;
	}

	unittest {
		struct Segment { string name; char separator = 0; static Segment fromTrustedString(string str, char sep = 0) pure nothrow @nogc { return Segment(str, sep); }}
		assert(decodeSingleSegment("foo") == "foo");
		assert(decodeSingleSegment("fo%20o") == "fo%20o");
		assert(decodeSingleSegment("C:") == "C:");
		assert(decodeSingleSegment("bar:") == "bar:");
	}

	static string validatePath(string path)
	@nogc {
		import std.algorithm.comparison : among;

		// skip UNC prefix
		if (path.startsWith("\\\\")) {
			path = path[2 .. $];
			while (path.length && !isSeparator(path[0])) {
				if (path[0] < 32 || path[0].among('<', '>', '|'))
					return "Invalid character in UNC host name.";
				path = path[1 .. $];
			}
			if (path.length) path = path[1 .. $];
		}

		// stricter validation for the rest
		bool had_sep = false;
		foreach (i, char c; path) {
			if (c < 32 || c.among!('<', '>', '|', '?'))
				return "Invalid character in path.";
			if (isSeparator(c)) had_sep = true;
			else if (c == ':' && (had_sep || i+1 < path.length && !isSeparator(path[i+1])))
				return "Colon in path that is not part of a drive name.";

		}
		return null;
	}

	static string validateDecodedSegment(string segment)
	@nogc {
		auto pe = validatePath(segment);
		if (pe) return pe;
		foreach (char c; segment)
			if (isSeparator(c))
				return "Path segment contains separator character.";
		return null;
	}

	unittest {
		assert(validatePath("c:\\foo") is null);
		assert(validatePath("\\\\?\\c:\\foo") is null);
		assert(validatePath("//?\\c:\\foo") !is null);
		assert(validatePath("-foo/bar\\*\\baz") is null);
		assert(validatePath("foo\0bar") !is null);
		assert(validatePath("foo\tbar") !is null);
		assert(validatePath("\\c:\\foo") !is null);
		assert(validatePath("c:d\\foo") !is null);
		assert(validatePath("foo\\b:ar") !is null);
		assert(validatePath("foo\\bar:\\baz") !is null);
	}

	static string encodeSegment(string segment)
	{
		assert(segment.length == 0 || segment[$-1] != '/');
		return segment;
	}
}


/** Implements Unix/Linux path semantics.

	See_also: `WindowsPath`
*/
struct PosixPathFormat {
	static void toString(I, O)(I segments, O dst)
	{
		char lastsep = '\0';
		bool first = true;
		foreach (s; segments) {
			if (!first || lastsep) dst.put('/');
			else first = false;
			dst.put(s.name);
			lastsep = s.separator;
		}
		if (lastsep) dst.put('/');
	}

	unittest {
		import std.array : appender;
		struct Segment { string name; char separator = 0; static Segment fromTrustedString(string str, char sep = 0) pure nothrow @nogc { return Segment(str, sep); }}
		string str(Segment[] segs...) { auto ret = appender!string; toString(segs, ret); return ret.data; }

		assert(str() == "");
		assert(str(Segment("",'/')) == "/");
		assert(str(Segment("foo",'/'), Segment("bar",'/')) == "foo/bar/");
		assert(str(Segment("",'/'), Segment("foo",'\0')) == "/foo");
		assert(str(Segment("",'\\'), Segment("foo",'\\')) == "/foo/");
		assert(str(Segment("f oo")) == "f oo");
		assert(str(Segment("foo"), Segment("bar")) == "foo/bar");
	}

@safe nothrow pure:
	enum defaultSeparator = '/';

	static bool isSeparator(dchar ch)
	@nogc {
		return ch == '/';
	}

	static string getAbsolutePrefix(string path)
	@nogc {
		if (path.length > 0 && path[0] == '/')
			return path[0 .. 1];
		return null;
	}

	unittest {
		assert(getAbsolutePrefix("/") == "/");
		assert(getAbsolutePrefix("/test") == "/");
		assert(getAbsolutePrefix("/test/") == "/");
		assert(getAbsolutePrefix("test/") == "");
		assert(getAbsolutePrefix("") == "");
		assert(getAbsolutePrefix("./") == "");
	}

	static string getFrontNode(string path)
	@nogc {
		import std.string : indexOf;
		auto idx = path.indexOf('/');
		return idx < 0 ? path : path[0 .. idx+1];
	}

	unittest {
		assert(getFrontNode("") == "");
		assert(getFrontNode("/bar") == "/");
		assert(getFrontNode("foo/bar") == "foo/");
		assert(getFrontNode("foo/") == "foo/");
		assert(getFrontNode("foo") == "foo");
	}

	static string getBackNode(string path)
	@nogc {
		if (!path.length) return path;
		foreach_reverse (i; 0 .. path.length-1)
			if (path[i] == '/')
				return path[i+1 .. $];
		return path;
	}

	unittest {
		assert(getBackNode("") == "");
		assert(getBackNode("/bar") == "bar");
		assert(getBackNode("foo/bar") == "bar");
		assert(getBackNode("foo/") == "foo/");
		assert(getBackNode("foo") == "foo");
	}

	static string validatePath(string path)
	@nogc {
		foreach (char c; path)
			if (c == '\0')
				return "Invalid NUL character in file name";
		return null;
	}

	static string validateDecodedSegment(string segment)
	@nogc {
		auto pe = validatePath(segment);
		if (pe) return pe;
		foreach (char c; segment)
			if (isSeparator(c))
				return "Path segment contains separator character.";
		return null;
	}

	unittest {
		assert(validatePath("-foo/bar*/baz?") is null);
		assert(validatePath("foo\0bar") !is null);
	}

	static string decodeSingleSegment(string segment)
	@nogc {
		assert(segment.length == 0 || segment[$-1] != '/');
		return segment;
	}

	unittest {
		struct Segment { string name; char separator = 0; static Segment fromTrustedString(string str, char sep = 0) pure nothrow @nogc { return Segment(str, sep); }}
		assert(decodeSingleSegment("foo") == "foo");
		assert(decodeSingleSegment("fo%20o\\") == "fo%20o\\");
	}

	static string encodeSegment(string segment)
	{
		assert(segment.length == 0 || segment[$-1] != '/');
		return segment;
	}
}


/** Implements URI/Internet path semantics.

	See_also: `WindowsPath`
*/
struct InetPathFormat {
	static void toString(I, O)(I segments, O dst)
	{
		char lastsep = '\0';
		bool first = true;
		foreach (e; segments) {
			if (!first || lastsep) dst.put('/');
			else first = false;
			static if (is(typeof(e.encodedName)))
				dst.put(e.encodedName);
			else encodeSegment(dst, e.name);
			lastsep = e.separator;
		}
		if (lastsep) dst.put('/');
	}

	unittest {
		import std.array : appender;
		struct Segment { string name; char separator = 0; static Segment fromTrustedString(string str, char sep = 0) pure nothrow @nogc { return Segment(str, sep); }}
		string str(Segment[] segs...) { auto ret = appender!string; toString(segs, ret); return ret.data; }
		assert(str() == "");
		assert(str(Segment("",'/')) == "/");
		assert(str(Segment("foo",'/'), Segment("bar",'/')) == "foo/bar/");
		assert(str(Segment("",'/'), Segment("foo",'\0')) == "/foo");
		assert(str(Segment("",'\\'), Segment("foo",'\\')) == "/foo/");
		assert(str(Segment("f oo")) == "f%20oo");
		assert(str(Segment("foo"), Segment("bar")) == "foo/bar");
	}

@safe pure nothrow:
	enum defaultSeparator = '/';

	static bool isSeparator(dchar ch)
	@nogc {
		return ch == '/';
	}

	static string getAbsolutePrefix(string path)
	@nogc {
		if (path.length > 0 && path[0] == '/')
			return path[0 .. 1];
		return null;
	}

	unittest {
		assert(getAbsolutePrefix("/") == "/");
		assert(getAbsolutePrefix("/test") == "/");
		assert(getAbsolutePrefix("/test/") == "/");
		assert(getAbsolutePrefix("test/") == "");
		assert(getAbsolutePrefix("") == "");
		assert(getAbsolutePrefix("./") == "");
	}

	static string getFrontNode(string path)
	@nogc {
		import std.string : indexOf;
		auto idx = path.indexOf('/');
		return idx < 0 ? path : path[0 .. idx+1];
	}

	unittest {
		assert(getFrontNode("") == "");
		assert(getFrontNode("/bar") == "/");
		assert(getFrontNode("foo/bar") == "foo/");
		assert(getFrontNode("foo/") == "foo/");
		assert(getFrontNode("foo") == "foo");
	}

	static string getBackNode(string path)
	@nogc {
		import std.string : lastIndexOf;

		if (!path.length) return path;
		ptrdiff_t idx;
		try idx = path[0 .. $-1].lastIndexOf('/');
		catch (Exception e) assert(false, e.msg);
		if (idx >= 0) return path[idx+1 .. $];
		return path;
	}

	unittest {
		assert(getBackNode("") == "");
		assert(getBackNode("/bar") == "bar");
		assert(getBackNode("foo/bar") == "bar");
		assert(getBackNode("foo/") == "foo/");
		assert(getBackNode("foo") == "foo");
	}

	static string validatePath(string path)
	@nogc {
		for (size_t i = 0; i < path.length; i++) {
			if (isAsciiAlphaNum(path[i]))
				continue;

			switch (path[i]) {
				default:
					return "Invalid character in internet path.";
				// unreserved
				case '-', '.', '_', '~':
				// subdelims
				case '!', '$', '&', '\'', '(', ')', '*', '+', ',', ';', '=':
            	// additional delims
            	case ':', '@':
            	// segment delimiter
            	case '/':
            		break;
            	case '%': // pct encoding
            		if (path.length < i+3)
            			return "Unterminated percent encoding sequence in internet path.";
            		foreach (j; 0 .. 2) {
            			switch (path[++i]) {
            				default: return "Invalid percent encoding sequence in internet path.";
            				case '0': .. case '9':
            				case 'a': .. case 'f':
            				case 'A': .. case 'F':
            					break;
            			}
            		}
            		break;
			}
		}
		return null;
	}

	static string validateDecodedSegment(string seg)
	@nogc {
		return null;
	}

	unittest {
		assert(validatePath("") is null);
		assert(validatePath("/") is null);
		assert(validatePath("/test") is null);
		assert(validatePath("test") is null);
		assert(validatePath("/C:/test") is null);
		assert(validatePath("/test%ab") is null);
		assert(validatePath("/test%ag") !is null);
		assert(validatePath("/test%a") !is null);
		assert(validatePath("/test%") !is null);
		assert(validatePath("/test§") !is null);
		assert(validatePath("föö") !is null);
	}

	static auto decodeSingleSegment(string segment)
	@nogc {
		import std.string : indexOf;

		static int hexDigit(char ch) @safe nothrow @nogc {
			assert(ch >= '0' && ch <= '9' || ch >= 'A' && ch <= 'F' || ch >= 'a' && ch <= 'f');
			if (ch >= '0' && ch <= '9') return ch - '0';
			else if (ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
			else return ch - 'A' + 10;
		}

		static struct R {
			@safe pure nothrow @nogc:

			private {
				string m_str;
			}

			this(string s)
			{
				m_str = s;
			}

			@property bool empty() const { return m_str.length == 0; }

			@property R save() const { return this; }

			@property char front()
			const {
				auto ch = m_str[0];
				if (ch != '%') return ch;

				auto a = m_str[1];
				auto b = m_str[2];
				return cast(char)(16 * hexDigit(a) + hexDigit(b));
			}

			@property void popFront()
			{
				assert(!empty);
				if (m_str[0] == '%') m_str = m_str[3 .. $];
				else m_str = m_str[1 .. $];
			}

			@property char back()
			const {
				if (m_str.length >= 3 && m_str[$-3] == '%') {
					auto a = m_str[$-2];
					auto b = m_str[$-1];
					return cast(char)(16 * hexDigit(a) + hexDigit(b));
				} else return m_str[$-1];
			}

			void popBack()
			{
				assert(!empty);
				if (m_str.length >= 3 && m_str[$-3] == '%') m_str = m_str[0 .. $-3];
				else m_str = m_str[0 .. $-1];
			}
		}

		return R(segment);
	}

	unittest {
		import std.range : retro;

		scope (failure) assert(false);

		assert(decodeSingleSegment("foo").equal("foo"));
		assert(decodeSingleSegment("fo%20o\\").equal("fo o\\"));
		assert(decodeSingleSegment("foo%20").equal("foo "));
		assert(decodeSingleSegment("foo").retro.equal("oof"));
		assert(decodeSingleSegment("fo%20o\\").retro.equal("\\o of"));
		assert(decodeSingleSegment("foo%20").retro.equal(" oof"));
	}


	static string encodeSegment(string segment)
	{
		import std.array : appender;

		foreach (i, char c; segment) {
			if (isAsciiAlphaNum(c)) continue;
			switch (c) {
				default:
					auto ret = appender!string;
					ret.put(segment[0 .. i]);
					encodeSegment(ret, segment[i .. $]);
					return ret.data;
				case '-', '.', '_', '~':
				case '!', '$', '&', '\'', '(', ')', '*', '+', ',', ';', '=':
        		case ':', '@':
					break;
			}
		}

		return segment;
	}

	unittest {
		assert(encodeSegment("foo") == "foo");
		assert(encodeSegment("foo bar") == "foo%20bar");
	}

	static void encodeSegment(R)(ref R dst, string segment)
	{
		static immutable char[16] digit = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'];

		foreach (char c; segment) {
			switch (c) {
				default:
					dst.put('%');
					dst.put(digit[uint(c) / 16]);
					dst.put(digit[uint(c) % 16]);
					break;
				case 'a': .. case 'z':
				case 'A': .. case 'Z':
				case '0': .. case '9':
				case '-', '.', '_', '~':
				case '!', '$', '&', '\'', '(', ')', '*', '+', ',', ';', '=':
        		case ':', '@':
					dst.put(c);
					break;
			}
		}
	}
}

private auto extension(R)(R filename)
	if (isForwardRange!R && isSomeChar!(ElementType!R))
{
	if (filename.empty) return filename;

	static if (isArray!R) { // avoid auto decoding
		filename = filename[1 .. $]; // ignore leading dot

		R candidate;
		while (filename.length) {
			if (filename[0] == '.')
				candidate = filename;
			filename = filename[1 .. $];
		}
		return candidate;
	} else {
		filename.popFront(); // ignore leading dot

		R candidate;
		while (!filename.empty) {
			if (filename.front == '.')
				candidate = filename.save;
			filename.popFront();
		}
		return candidate;
	}
}

@safe nothrow unittest {
	assert(extension("foo") == "");
	assert(extension("foo.txt") == ".txt");
	assert(extension(".foo") == "");
	assert(extension(".foo.txt") == ".txt");
	assert(extension("foo.bar.txt") == ".txt");
}

unittest {
	assert(extension(InetPath("foo").head.name).equal(""));
	assert(extension(InetPath("foo.txt").head.name).equal(".txt"));
	assert(extension(InetPath(".foo").head.name).equal(""));
	assert(extension(InetPath(".foo.txt").head.name).equal(".txt"));
	assert(extension(InetPath("foo.bar.txt").head.name).equal(".txt"));
}


private auto stripExtension(R)(R filename)
	if (isForwardRange!R && isSomeChar!(ElementType!R))
{
	static if (isArray!R) { // make sure to return a slice
		if (!filename.length) return filename;
		R r = filename;
		r = r[1 .. $]; // ignore leading dot
		size_t cnt = 0, rcnt = r.length;
		while (r.length) {
			if (r[0] == '.')
				rcnt = cnt;
			cnt++;
			r = r[1 .. $];
		}
		return filename[0 .. rcnt + 1];
	} else {
		if (filename.empty) return filename.takeExactly(0);
		R r = filename.save;
		size_t cnt = 0, rcnt = size_t.max;
		r.popFront(); // ignore leading dot
		while (!r.empty) {
			if (r.front == '.')
				rcnt = cnt;
			cnt++;
			r.popFront();
		}
		if (rcnt == size_t.max) return filename.takeExactly(cnt + 1);
		return filename.takeExactly(rcnt + 1);
	}
}

@safe nothrow unittest {
	assert(stripExtension("foo") == "foo");
	assert(stripExtension("foo.txt") == "foo");
	assert(stripExtension(".foo") == ".foo");
	assert(stripExtension(".foo.txt") == ".foo");
	assert(stripExtension("foo.bar.txt") == "foo.bar");
}

unittest { // test range based path
	import std.utf : byWchar;

	assert(stripExtension("foo".byWchar).equal("foo"));
	assert(stripExtension("foo.txt".byWchar).equal("foo"));
	assert(stripExtension(".foo".byWchar).equal(".foo"));
	assert(stripExtension(".foo.txt".byWchar).equal(".foo"));
	assert(stripExtension("foo.bar.txt".byWchar).equal("foo.bar"));

	assert(stripExtension(InetPath("foo").head.name).equal("foo"));
	assert(stripExtension(InetPath("foo.txt").head.name).equal("foo"));
	assert(stripExtension(InetPath(".foo").head.name).equal(".foo"));
	assert(stripExtension(InetPath(".foo.txt").head.name).equal(".foo"));
	assert(stripExtension(InetPath("foo.bar.txt").head.name).equal("foo.bar"));
}

private static bool isAsciiAlphaNum(char ch)
@safe nothrow pure @nogc {
	return (uint(ch) & 0xDF) - 0x41 < 26 || uint(ch) - '0' <= 9;
}

unittest {
	assert(!isAsciiAlphaNum('@'));
	assert(isAsciiAlphaNum('A'));
	assert(isAsciiAlphaNum('Z'));
	assert(!isAsciiAlphaNum('['));
	assert(!isAsciiAlphaNum('`'));
	assert(isAsciiAlphaNum('a'));
	assert(isAsciiAlphaNum('z'));
	assert(!isAsciiAlphaNum('{'));
	assert(!isAsciiAlphaNum('/'));
	assert(isAsciiAlphaNum('0'));
	assert(isAsciiAlphaNum('9'));
	assert(!isAsciiAlphaNum(':'));
}

unittest { // regression tests
	assert(NativePath("").bySegment.empty);
}
