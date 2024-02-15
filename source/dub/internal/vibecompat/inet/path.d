/**
	Contains routines for high level path handling.

	Copyright: © 2012 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.internal.vibecompat.inet.path;

version (Have_vibe_core) public import vibe.core.path;
else:

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.string;


deprecated("Use NativePath instead.")
alias Path = NativePath;

/**
	Represents an absolute or relative file system path.

	This struct allows to do safe operations on paths, such as concatenation and sub paths. Checks
	are done to disallow invalid operations such as concatenating two absolute paths. It also
	validates path strings and allows for easy checking of malicious relative paths.
*/
struct NativePath {
	private {
		immutable(PathEntry)[] m_nodes;
		bool m_absolute = false;
		bool m_endsWithSlash = false;
	}

	alias Segment = PathEntry;

	alias bySegment = nodes;

	/// Constructs a NativePath object by parsing a path string.
	this(string pathstr)
	{
		m_nodes = splitPath(pathstr);
		m_absolute = (pathstr.startsWith("/") || m_nodes.length > 0 && (m_nodes[0].toString().countUntil(':')>0 || m_nodes[0] == "\\"));
		m_endsWithSlash = pathstr.endsWith("/");
	}

	/// Constructs a path object from a list of PathEntry objects.
	this(immutable(PathEntry)[] nodes, bool absolute = false)
	{
		m_nodes = nodes;
		m_absolute = absolute;
	}

	/// Constructs a relative path with one path entry.
	this(PathEntry entry){
		m_nodes = [entry];
		m_absolute = false;
	}

	/// Determines if the path is absolute.
	@property bool absolute() const scope @safe pure nothrow @nogc { return m_absolute; }

	/// Resolves all '.' and '..' path entries as far as possible.
	void normalize()
	{
		immutable(PathEntry)[] newnodes;
		foreach( n; m_nodes ){
			switch(n.toString()){
				default:
					newnodes ~= n;
					break;
				case "", ".": break;
				case "..":
					enforce(!m_absolute || newnodes.length > 0, "Path goes below root node.");
					if( newnodes.length > 0 && newnodes[$-1] != ".." ) newnodes = newnodes[0 .. $-1];
					else newnodes ~= n;
					break;
			}
		}
		m_nodes = newnodes;
	}

	/// Converts the Path back to a string representation using slashes.
	string toString()
	const @safe {
		if( m_nodes.empty ) return absolute ? "/" : "";

		Appender!string ret;

		// for absolute paths start with /
		version(Windows)
		{
			// Make sure windows path isn't "DRIVE:"
			if( absolute && !m_nodes[0].toString().endsWith(':') )
				ret.put('/');
		}
		else
		{
			if( absolute )
			{
				ret.put('/');
			}
		}

		foreach( i, f; m_nodes ){
			if( i > 0 ) ret.put('/');
			ret.put(f.toString());
		}

		if( m_nodes.length > 0 && m_endsWithSlash )
			ret.put('/');

		return ret.data;
	}

	/// Converts the NativePath object to a native path string (backslash as path separator on Windows).
	string toNativeString()
	const {
		if (m_nodes.empty) {
			version(Windows) {
				assert(!absolute, "Empty absolute path detected.");
				return m_endsWithSlash ? ".\\" : ".";
			} else return absolute ? "/" : m_endsWithSlash ? "./" : ".";
		}

		Appender!string ret;

		// for absolute unix paths start with /
		version(Posix) { if(absolute) ret.put('/'); }

		foreach( i, f; m_nodes ){
			version(Windows) { if( i > 0 ) ret.put('\\'); }
			else version(Posix) { if( i > 0 ) ret.put('/'); }
			else { static assert(0, "Unsupported OS"); }
			ret.put(f.toString());
		}

		if( m_nodes.length > 0 && m_endsWithSlash ){
			version(Windows) { ret.put('\\'); }
			version(Posix) { ret.put('/'); }
		}

		return ret.data;
	}

	/// Tests if `rhs` is an ancestor or the same as this path.
	bool startsWith(const NativePath rhs) const {
		if( rhs.m_nodes.length > m_nodes.length ) return false;
		foreach( i; 0 .. rhs.m_nodes.length )
			if( m_nodes[i] != rhs.m_nodes[i] )
				return false;
		return true;
	}

	/// Computes the relative path from `parentPath` to this path.
	NativePath relativeTo(const NativePath parentPath) const {
		assert(this.absolute && parentPath.absolute, "Determining relative path between non-absolute paths.");
		version(Windows){
			// a path such as ..\C:\windows is not valid, so force the path to stay absolute in this case
			if( this.absolute && !this.empty &&
				(m_nodes[0].toString().endsWith(":") && !parentPath.startsWith(this[0 .. 1]) ||
				m_nodes[0] == "\\" && !parentPath.startsWith(this[0 .. min(2, $)])))
			{
				return this;
			}
		}
		int nup = 0;
		while( parentPath.length > nup && !startsWith(parentPath[0 .. parentPath.length-nup]) ){
			nup++;
		}
		assert(m_nodes.length >= parentPath.length - nup);
		NativePath ret = NativePath(null, false);
		assert(m_nodes.length >= parentPath.length - nup);
		ret.m_endsWithSlash = true;
		foreach( i; 0 .. nup ) ret ~= "..";
		ret ~= NativePath(m_nodes[parentPath.length-nup .. $], false);
		ret.m_endsWithSlash = this.m_endsWithSlash;
		return ret;
	}

	/// The last entry of the path
	@property ref immutable(PathEntry) head() const { enforce(m_nodes.length > 0, "Getting head of empty path."); return m_nodes[$-1]; }

	/// The parent path
	@property NativePath parentPath() const { return this[0 .. length-1]; }
	/// Forward compatibility with vibe-d
	@property bool hasParentPath() const { return length > 1; }

	/// The list of path entries of which this path is composed
	@property immutable(PathEntry)[] nodes() const { return m_nodes; }

	/// The number of path entries of which this path is composed
	@property size_t length() const scope @safe pure nothrow @nogc { return m_nodes.length; }

	/// True if the path contains no entries
	@property bool empty() const scope @safe pure nothrow @nogc { return m_nodes.length == 0; }

	/// Determines if the path ends with a slash (i.e. is a directory)
	@property bool endsWithSlash() const { return m_endsWithSlash; }
	/// ditto
	@property void endsWithSlash(bool v) { m_endsWithSlash = v; }

	/// Determines if this path goes outside of its base path (i.e. begins with '..').
	@property bool external() const { return !m_absolute && m_nodes.length > 0 && m_nodes[0].m_name == ".."; }

	ref immutable(PathEntry) opIndex(size_t idx) const { return m_nodes[idx]; }
	NativePath opSlice(size_t start, size_t end) const {
		auto ret = NativePath(m_nodes[start .. end], start == 0 ? absolute : false);
		if( end == m_nodes.length ) ret.m_endsWithSlash = m_endsWithSlash;
		return ret;
	}
	size_t opDollar(int dim)() const if(dim == 0) { return m_nodes.length; }


	NativePath opBinary(string OP)(const NativePath rhs) const if( OP == "~" ) {
		NativePath ret;
		ret.m_nodes = m_nodes;
		ret.m_absolute = m_absolute;
		ret.m_endsWithSlash = rhs.m_endsWithSlash;
		ret.normalize(); // needed to avoid "."~".." become "" instead of ".."

		assert(!rhs.absolute, "Trying to append absolute path.");
		foreach(folder; rhs.m_nodes){
			switch(folder.toString()){
				default: ret.m_nodes = ret.m_nodes ~ folder; break;
				case "", ".": break;
				case "..":
					enforce(!ret.absolute || ret.m_nodes.length > 0, "Relative path goes below root node!");
					if( ret.m_nodes.length > 0 && ret.m_nodes[$-1].toString() != ".." )
						ret.m_nodes = ret.m_nodes[0 .. $-1];
					else ret.m_nodes = ret.m_nodes ~ folder;
					break;
			}
		}
		return ret;
	}

	NativePath opBinary(string OP)(string rhs) const if( OP == "~" ) { assert(rhs.length > 0, "Cannot append empty path string."); return opBinary!"~"(NativePath(rhs)); }
	NativePath opBinary(string OP)(PathEntry rhs) const if( OP == "~" ) { assert(rhs.toString().length > 0, "Cannot append empty path string."); return opBinary!"~"(NativePath(rhs)); }
	void opOpAssign(string OP)(string rhs) if( OP == "~" ) { assert(rhs.length > 0, "Cannot append empty path string."); opOpAssign!"~"(NativePath(rhs)); }
	void opOpAssign(string OP)(PathEntry rhs) if( OP == "~" ) { assert(rhs.toString().length > 0, "Cannot append empty path string."); opOpAssign!"~"(NativePath(rhs)); }
	void opOpAssign(string OP)(NativePath rhs) if( OP == "~" ) { auto p = this ~ rhs; m_nodes = p.m_nodes; m_endsWithSlash = rhs.m_endsWithSlash; }

	/// Tests two paths for equality using '=='.
	bool opEquals(scope ref const NativePath rhs) const scope @safe {
		if( m_absolute != rhs.m_absolute ) return false;
		if( m_endsWithSlash != rhs.m_endsWithSlash ) return false;
		if( m_nodes.length != rhs.length ) return false;
		foreach( i; 0 .. m_nodes.length )
			if( m_nodes[i] != rhs.m_nodes[i] )
				return false;
		return true;
	}
	/// ditto
	bool opEquals(scope const NativePath other) const scope @safe { return opEquals(other); }

	int opCmp(ref const NativePath rhs) const {
		if( m_absolute != rhs.m_absolute ) return cast(int)m_absolute - cast(int)rhs.m_absolute;
		foreach( i; 0 .. min(m_nodes.length, rhs.m_nodes.length) )
			if( m_nodes[i] != rhs.m_nodes[i] )
				return m_nodes[i].opCmp(rhs.m_nodes[i]);
		if( m_nodes.length > rhs.m_nodes.length ) return 1;
		if( m_nodes.length < rhs.m_nodes.length ) return -1;
		return 0;
	}

	size_t toHash()
	const nothrow @trusted {
		size_t ret;
		auto strhash = &typeid(string).getHash;
		try foreach (n; nodes) ret ^= strhash(&n.m_name);
		catch (Exception) assert(false);
		if (m_absolute) ret ^= 0xfe3c1738;
		if (m_endsWithSlash) ret ^= 0x6aa4352d;
		return ret;
	}
}

struct PathEntry {
	private {
		string m_name;
	}

	this(string str)
	pure {
		assert(str.countUntil('/') < 0 && (str.countUntil('\\') < 0 || str.length == 1));
		m_name = str;
	}

	string toString() const return scope @safe pure nothrow @nogc { return m_name; }

	@property string name() const return scope @safe pure nothrow @nogc { return m_name; }

	NativePath opBinary(string OP)(PathEntry rhs) const if( OP == "~" ) { return NativePath([this, rhs], false); }

	bool opEquals(scope ref const PathEntry rhs) const scope @safe pure nothrow @nogc { return m_name == rhs.m_name; }
	bool opEquals(scope PathEntry rhs) const scope @safe pure nothrow @nogc { return m_name == rhs.m_name; }
	bool opEquals(string rhs) const scope @safe pure nothrow @nogc { return m_name == rhs; }
	int opCmp(scope ref const PathEntry rhs) const scope @safe pure nothrow @nogc { return m_name.cmp(rhs.m_name); }
	int opCmp(string rhs) const scope @safe pure nothrow @nogc { return m_name.cmp(rhs); }
}

/// Joins two path strings. sub-path must be relative.
string joinPath(string basepath, string subpath)
{
	NativePath p1 = NativePath(basepath);
	NativePath p2 = NativePath(subpath);
	return (p1 ~ p2).toString();
}

/// Splits up a path string into its elements/folders
PathEntry[] splitPath(string path)
pure {
	if( path.startsWith("/") || path.startsWith("\\") ) path = path[1 .. $];
	if( path.empty ) return null;
	if( path.endsWith("/") || path.endsWith("\\") ) path = path[0 .. $-1];

	// count the number of path nodes
	size_t nelements = 0;
	foreach( i, char ch; path )
		if( ch == '\\' || ch == '/' )
			nelements++;
	nelements++;

	// reserve space for the elements
	auto elements = new PathEntry[nelements];
	size_t eidx = 0;

	// detect UNC path
	if(path.startsWith("\\"))
	{
		elements[eidx++] = PathEntry(path[0 .. 1]);
		path = path[1 .. $];
	}

	// read and return the elements
	size_t startidx = 0;
	foreach( i, char ch; path )
		if( ch == '\\' || ch == '/' ){
			elements[eidx++] = PathEntry(path[startidx .. i]);
			startidx = i+1;
		}
	elements[eidx++] = PathEntry(path[startidx .. $]);
	assert(eidx == nelements);
	return elements;
}

unittest
{
	NativePath p;
	assert(p.toNativeString() == ".");
	p.endsWithSlash = true;
	version(Windows) assert(p.toNativeString() == ".\\");
	else assert(p.toNativeString() == "./");

	p = NativePath("test/");
	version(Windows) assert(p.toNativeString() == "test\\");
	else assert(p.toNativeString() == "test/");
	p.endsWithSlash = false;
	assert(p.toNativeString() == "test");
}

unittest
{
	{
		auto unc = "\\\\server\\share\\path";
		auto uncp = NativePath(unc);
		uncp.normalize();
		version(Windows) assert(uncp.toNativeString() == unc);
		assert(uncp.absolute);
		assert(!uncp.endsWithSlash);
	}

	{
		auto abspath = "/test/path/";
		auto abspathp = NativePath(abspath);
		assert(abspathp.toString() == abspath);
		version(Windows) {} else assert(abspathp.toNativeString() == abspath);
		assert(abspathp.absolute);
		assert(abspathp.endsWithSlash);
		assert(abspathp.length == 2);
		assert(abspathp[0] == "test");
		assert(abspathp[1] == "path");
	}

	{
		auto relpath = "test/path/";
		auto relpathp = NativePath(relpath);
		assert(relpathp.toString() == relpath);
		version(Windows) assert(relpathp.toNativeString() == "test\\path\\");
		else assert(relpathp.toNativeString() == relpath);
		assert(!relpathp.absolute);
		assert(relpathp.endsWithSlash);
		assert(relpathp.length == 2);
		assert(relpathp[0] == "test");
		assert(relpathp[1] == "path");
	}

	{
		auto winpath = "C:\\windows\\test";
		auto winpathp = NativePath(winpath);
		version(Windows) {
			assert(winpathp.toString() == "C:/windows/test", winpathp.toString());
			assert(winpathp.toNativeString() == winpath);
		} else {
			assert(winpathp.toString() == "/C:/windows/test", winpathp.toString());
			assert(winpathp.toNativeString() == "/C:/windows/test");
		}
		assert(winpathp.absolute);
		assert(!winpathp.endsWithSlash);
		assert(winpathp.length == 3);
		assert(winpathp[0] == "C:");
		assert(winpathp[1] == "windows");
		assert(winpathp[2] == "test");
	}

	{
		auto dotpath = "/test/../test2/././x/y";
		auto dotpathp = NativePath(dotpath);
		assert(dotpathp.toString() == "/test/../test2/././x/y");
		dotpathp.normalize();
		assert(dotpathp.toString() == "/test2/x/y");
	}

	{
		auto dotpath = "/test/..////test2//./x/y";
		auto dotpathp = NativePath(dotpath);
		assert(dotpathp.toString() == "/test/..////test2//./x/y");
		dotpathp.normalize();
		assert(dotpathp.toString() == "/test2/x/y");
	}

	{
		auto parentpath = "/path/to/parent";
		auto parentpathp = NativePath(parentpath);
		auto subpath = "/path/to/parent/sub/";
		auto subpathp = NativePath(subpath);
		auto subpath_rel = "sub/";
		assert(subpathp.relativeTo(parentpathp).toString() == subpath_rel);
		auto subfile = "/path/to/parent/child";
		auto subfilep = NativePath(subfile);
		auto subfile_rel = "child";
		assert(subfilep.relativeTo(parentpathp).toString() == subfile_rel);
	}

	{ // relative paths across Windows devices are not allowed
		version (Windows) {
			auto p1 = NativePath("\\\\server\\share"); assert(p1.absolute);
			auto p2 = NativePath("\\\\server\\othershare"); assert(p2.absolute);
			auto p3 = NativePath("\\\\otherserver\\share"); assert(p3.absolute);
			auto p4 = NativePath("C:\\somepath"); assert(p4.absolute);
			auto p5 = NativePath("C:\\someotherpath"); assert(p5.absolute);
			auto p6 = NativePath("D:\\somepath"); assert(p6.absolute);
			assert(p4.relativeTo(p5) == NativePath("../somepath"));
			assert(p4.relativeTo(p6) == NativePath("C:\\somepath"));
			assert(p4.relativeTo(p1) == NativePath("C:\\somepath"));
			assert(p1.relativeTo(p2) == NativePath("../share"));
			assert(p1.relativeTo(p3) == NativePath("\\\\server\\share"));
			assert(p1.relativeTo(p4) == NativePath("\\\\server\\share"));
		}
	}
}

unittest {
	assert(NativePath("/foo/bar/baz").relativeTo(NativePath("/foo")).toString == "bar/baz");
	assert(NativePath("/foo/bar/baz/").relativeTo(NativePath("/foo")).toString == "bar/baz/");
	assert(NativePath("/foo/bar").relativeTo(NativePath("/foo")).toString == "bar");
	assert(NativePath("/foo/bar/").relativeTo(NativePath("/foo")).toString == "bar/");
	assert(NativePath("/foo").relativeTo(NativePath("/foo/bar")).toString() == "..");
	assert(NativePath("/foo/").relativeTo(NativePath("/foo/bar")).toString() == "../");
	assert(NativePath("/foo/baz").relativeTo(NativePath("/foo/bar/baz")).toString() == "../../baz");
	assert(NativePath("/foo/baz/").relativeTo(NativePath("/foo/bar/baz")).toString() == "../../baz/");
	assert(NativePath("/foo/").relativeTo(NativePath("/foo/bar/baz")).toString() == "../../");
	assert(NativePath("/foo/").relativeTo(NativePath("/foo/bar/baz/mumpitz")).toString() == "../../../");
	assert(NativePath("/foo").relativeTo(NativePath("/foo")).toString() == "");
	assert(NativePath("/foo/").relativeTo(NativePath("/foo")).toString() == "");
}
