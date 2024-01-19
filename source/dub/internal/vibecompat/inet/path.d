/**
	Contains routines for high level path handling.

	Copyright: © 2012-2021 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.internal.vibecompat.inet.path;

import dub.internal.vibecompat.inet.path2;
import std.traits : isInstanceOf;
import std.range.primitives : ElementType, isInputRange;

/// Represents a path on Windows operating systems.
alias WindowsPath = Normalized!(GenericPath!WindowsPathFormat);

/// Represents a path on Unix/Posix systems.
alias PosixPath = Normalized!(GenericPath!PosixPathFormat);

/// Represents a path as part of an URI.
alias InetPath = GenericPath!InetPathFormat; // No need for normalization

/// The path type native to the target operating system.
version (Windows) alias NativePath = WindowsPath;
else alias NativePath = PosixPath;

// GenericPath no longer normalize on `opBinary!"~"` since v2. We relied on this
// behavior heavily and this clutch is used to avoid a breaking change.
private struct Normalized (PType) {
    @safe:
    public alias PathType = PType;

    private PathType data;

    public this (string data) scope @safe pure {
        this.data = PathType(data);
    }

    public this (PathType data) scope @safe pure nothrow @nogc {
        this.data = data;
    }

	this(Segment segment) { this(PathType(segment)); }

	/** Constructs a path from an input range of `Segment`s.

		Throws:
			Since path segments are pre-validated, this constructor does not
			throw an exception.
	*/
	this(R)(R segments)
		if (isInputRange!R && is(ElementType!R : Segment))
    {
        this(PathType(segments));
    }

    /// Append a path to this
	Normalized opBinary(string op : "~")(string subpath) const {
        return this ~ Normalized(subpath);
    }
	/// ditto
	Normalized opBinary(string op : "~")(Segment subpath) const {
        return this ~ Normalized(PathType(subpath));
    }
	/// ditto
	Normalized opBinary(string op : "~", OtherType)(Normalized!OtherType subpath) const {
        auto result = this.data.opBinary!"~"(subpath.data);
        result.normalize();
        return Normalized(result);
	}
	/// ditto
	Normalized opBinary(string op : "~")(InetPath subpath) const {
        auto result = this.data.opBinary!"~"(subpath);
        result.normalize();
        return Normalized(result);
	}
	/// Appends a relative path to this path.
	void opOpAssign(string op : "~", T)(T op) { this = this ~ op; }

	P opCast(P : Normalized!(GenericPath!(Format)), Format)() const {
        return P(this.data.opCast!(P.PathType));
    }
    P opCast(P : InetPath)() const {
        return this.data.opCast!(P);
    }

    // Just forward, `alias this` is hopeless
    public alias Segment = PathType.Segment;

	/// Tests if the path is represented by an empty string.
	@property bool empty() const nothrow @nogc { return this.data.empty(); }

	/// Tests if the path is absolute.
	@property bool absolute() const nothrow @nogc { return this.data.absolute(); }

	/// Determines whether the path ends with a path separator (i.e. represents a folder specifically).
	@property bool endsWithSlash() const nothrow @nogc { return this.data.endsWithSlash(); }
	/// ditto
	@property void endsWithSlash(bool v) nothrow { this.data.endsWithSlash(v); }

	/** Iterates over the individual segments of the path.

		Returns a forward range of `Segment`s.
	*/
	@property auto bySegment() const { return this.data.bySegment(); }

    ///
	string toString() const nothrow @nogc { return this.data.toString(); }

	/// Computes a hash sum, enabling storage within associative arrays.
	size_t toHash() const nothrow @trusted { return this.data.toHash(); }

	/** Compares two path objects.

		Note that the exact string representation of the two paths will be
		compared. To get a basic semantic comparison, the paths must be
		normalized first.
	*/
	bool opEquals(Normalized other) const @nogc { return this.data.opEquals(other.data); }

    ///
    @property Segment head() const @nogc { return this.data.head(); }

    ///
    @property bool hasParentPath() const @nogc { return this.data.hasParentPath(); }

    ///
    @property Normalized parentPath() const @nogc { return Normalized(this.data.parentPath()); }

    ///
    void normalize() { return this.data.normalize(); }

    ///
    Normalized normalized() const { return Normalized(this.data.normalized()); }

    ///
	bool startsWith(Normalized prefix) const nothrow { return this.data.startsWith(prefix.data); }

    ///
	static Normalized fromTrustedString(string p) nothrow @nogc {
        return Normalized(PathType.fromTrustedString(p));
    }
}

Path relativeTo(Path)(in Path path, in Path base_path) @safe
	if (isInstanceOf!(Normalized, Path))
{
    return Path(dub.internal.vibecompat.inet.path2.relativeTo(path.data, base_path.data));
}

/** Converts a path to its system native string representation.
*/
string toNativeString(T)(Normalized!T path)
{
    return (cast(NativePath)path).toString();
}
