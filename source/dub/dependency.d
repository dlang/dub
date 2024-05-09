/**
	Dependency specification functionality.

	Copyright: © 2012-2013 Matthias Dondorff, © 2012-2016 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff, Sönke Ludwig
*/
module dub.dependency;

import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.path;
import dub.semver;

import dub.internal.dyaml.stdsumtype;

import std.algorithm;
import std.array;
import std.exception;
import std.string;

/// Represents a fully-qualified package name
public struct PackageName
{
	/// The underlying full name of the package
	private string fullName;
	/// Where the separator lies, if any
	private size_t separator;

	/// Creates a new instance of this struct
	public this(string fn) @safe pure
	{
		this.fullName = fn;
		if (auto idx = fn.indexOf(':'))
			this.separator = idx > 0 ? idx : fn.length;
		else // We were given `:foo`
			assert(0, "Argument to PackageName constructor needs to be " ~
				"a fully qualified string");
	}

	/// Private constructor to have nothrow / @nogc
	private this(string fn, size_t sep) @safe pure nothrow @nogc
	{
		this.fullName = fn;
		this.separator = sep;
	}

	/// The base package name in which the subpackages may live
	public PackageName main () const return @safe pure nothrow @nogc
	{
		return PackageName(this.fullName[0 .. this.separator], this.separator);
	}

	/// The subpackage name, or an empty string if there isn't
	public string sub () const return @safe pure nothrow @nogc
	{
		// Return `null` instead of an empty string so that
		// it can be used in a boolean context, e.g.
		// `if (name.sub)` would be true with empty string
		return this.separator < this.fullName.length
			? this.fullName[this.separator + 1 .. $]
			: null;
	}

	/// Human readable representation
	public string toString () const return scope @safe pure nothrow @nogc
	{
		return this.fullName;
	}

    ///
    public int opCmp (in PackageName other) const scope @safe pure nothrow @nogc
    {
        import core.internal.string : dstrcmp;
        return dstrcmp(this.toString(), other.toString());
    }

    ///
    public bool opEquals (in PackageName other) const scope @safe pure nothrow @nogc
    {
        return this.toString() == other.toString();
    }
}

/** Encapsulates the name of a package along with its dependency specification.
*/
struct PackageDependency {
	/// Backward compatibility
	deprecated("Use the constructor that accepts a `PackageName` as first argument")
	this(string n, Dependency s = Dependency.init) @safe pure
	{
		this.name = PackageName(n);
		this.spec = s;
	}

	// Remove once deprecated overload is gone
	this(PackageName n, Dependency s = Dependency.init) @safe pure nothrow @nogc
	{
		this.name = n;
		this.spec = s;
	}

	int opCmp(in typeof(this) other) @safe const {
		return name == other.name
			? spec.opCmp(other.spec)
			: name.opCmp(other.name);
	}

	/// Name of the referenced package.
	PackageName name;

	/// Dependency specification used to select a particular version of the package.
	Dependency spec;
}

/**
	Represents a dependency specification.

	A dependency specification either represents a specific version or version
	range, or a path to a package. In addition to that it has `optional` and
	`default_` flags to control how non-mandatory dependencies are handled. The
	package name is notably not part of the dependency specification.
*/
struct Dependency {
	/// We currently support 3 'types'
	private alias Value = SumType!(VersionRange, NativePath, Repository);

	/// Used by `toString`
	private static immutable string[] BooleanOptions = [ "optional", "default" ];

	// Shortcut to create >=0.0.0
	private enum ANY_IDENT = "*";

	private Value m_value = Value(VersionRange.Invalid);
	private bool m_optional;
	private bool m_default;

	/// A Dependency, which matches every valid version.
	public static immutable Dependency Any = Dependency(VersionRange.Any);

	/// An invalid dependency (with no possible version matches).
	public static immutable Dependency Invalid = Dependency(VersionRange.Invalid);

	deprecated("Use `Dependency.Any` instead")
	static @property Dependency any() @safe { return Dependency(VersionRange.Any); }
	deprecated("Use `Dependency.Invalid` instead")
	static @property Dependency invalid() @safe
	{
		return Dependency(VersionRange.Invalid);
	}

	/** Constructs a new dependency specification that matches a specific
		path.
	*/
	this(NativePath path) @safe
	{
		this.m_value = path;
	}

	/** Constructs a new dependency specification that matches a specific
		Git reference.
	*/
	this(Repository repository) @safe
	{
		this.m_value = repository;
	}

	/** Constructs a new dependency specification from a string

		See the `versionSpec` property for a description of the accepted
		contents of that string.
	*/
	this(string spec) @safe
	{
		this(VersionRange.fromString(spec));
	}

	/** Constructs a new dependency specification that matches a specific
		version.
	*/
	this(const Version ver) @safe
	{
		this(VersionRange(ver, ver));
	}

	/// Construct a version from a range of possible values
	this (VersionRange rng) @safe
	{
		this.m_value = rng;
	}

	deprecated("Instantiate the `Repository` struct with the string directly")
	this(Repository repository, string spec) @safe
	{
		assert(repository.m_ref is null);
		repository.m_ref = spec;
		this(repository);
	}

	/// If set, overrides any version based dependency selection.
	deprecated("Construct a new `Dependency` object instead")
	@property void path(NativePath value) @trusted
	{
		this.m_value = value;
	}
	/// ditto
	@property NativePath path() const @safe
	{
		return this.m_value.match!(
			(const NativePath p) => p,
			(      any         ) => NativePath.init,
		);
	}

	/// If set, overrides any version based dependency selection.
	deprecated("Construct a new `Dependency` object instead")
	@property void repository(Repository value) @trusted
	{
		this.m_value = value;
	}
	/// ditto
	@property Repository repository() const @safe
	{
		return this.m_value.match!(
			(const Repository p) => p,
			(      any         ) => Repository.init,
		);
	}

	/// Determines if the dependency is required or optional.
	@property bool optional() const scope @safe pure nothrow @nogc
	{
		return m_optional;
	}
	/// ditto
	@property void optional(bool optional) scope @safe pure nothrow @nogc
	{
		m_optional = optional;
	}

	/// Determines if an optional dependency should be chosen by default.
	@property bool default_() const scope @safe pure nothrow @nogc
	{
		return m_default;
	}
	/// ditto
	@property void default_(bool value) scope @safe pure nothrow @nogc
	{
		m_default = value;
	}

	/// Returns true $(I iff) the version range only matches a specific version.
	@property bool isExactVersion() const scope @safe
	{
		return this.m_value.match!(
			(NativePath v) => false,
			(Repository v) => false,
			(VersionRange v) => v.isExactVersion(),
		);
	}

	/// Returns the exact version matched by the version range.
	@property Version version_() const @safe {
		auto range = this.m_value.match!(
			// Can be simplified to `=> assert(0)` once we drop support for v2.096
			(NativePath   p) { int dummy; if (dummy) return VersionRange.init; assert(0); },
			(Repository   r) { int dummy; if (dummy) return VersionRange.init; assert(0); },
			(VersionRange v) => v,
		);
		enforce(range.isExactVersion(),
				"Dependency "~range.toString()~" is no exact version.");
		return range.m_versA;
	}

	/// Sets/gets the matching version range as a specification string.
	deprecated("Create a new `Dependency` instead and provide a `VersionRange`")
	@property void versionSpec(string ves) @trusted
	{
		this.m_value = VersionRange.fromString(ves);
	}

	/// ditto
	deprecated("Use `Dependency.visit` and match `VersionRange`instead")
	@property string versionSpec() const @safe {
		return this.m_value.match!(
			(const NativePath   p) => ANY_IDENT,
			(const Repository   r) => r.m_ref,
			(const VersionRange p) => p.toString(),
		);
	}

	/** Returns a modified dependency that gets mapped to a given path.

		This function will return an unmodified `Dependency` if it is not path
		based. Otherwise, the given `path` will be prefixed to the existing
		path.
	*/
	Dependency mapToPath(NativePath path) const @trusted {
		// NOTE Path is @system in vibe.d 0.7.x and in the compatibility layer
		return this.m_value.match!(
			(NativePath v) {
				if (v.empty || v.absolute) return this;
				auto ret = Dependency(path ~ v);
				ret.m_default = m_default;
				ret.m_optional = m_optional;
				return ret;
			},
			(Repository v) => this,
			(VersionRange v) => this,
		);
	}

	/** Returns a human-readable string representation of the dependency
		specification.
	*/
	string toString() const scope @trusted {
		// Trusted because `SumType.match` doesn't seem to support `scope`

		string Stringifier (T, string pre = null) (const T v)
		{
			const bool extra = this.optional || this.default_;
			return format("%s%s%s%-(%s, %)%s",
					pre, v,
					extra ? " (" : "",
					BooleanOptions[!this.optional .. 1 + this.default_],
					extra ? ")" : "");
		}

		return this.m_value.match!(
			Stringifier!Repository,
			Stringifier!(NativePath, "@"),
			Stringifier!VersionRange
		);
	}

	/** Returns a JSON representation of the dependency specification.

		Simple specifications will be represented as a single specification
		string (`versionSpec`), while more complex specifications will be
		represented as a JSON object with optional "version", "path", "optional"
		and "default" fields.

		Params:
		  selections = We are serializing `dub.selections.json`, don't write out
			  `optional` and `default`.
	*/
	Json toJson(bool selections = false) const @safe
	{
		// NOTE Path and Json is @system in vibe.d 0.7.x and in the compatibility layer
		static void initJson(ref Json j, bool opt, bool def, bool s = selections)
		{
			j = Json.emptyObject;
			if (!s && opt) j["optional"] = true;
			if (!s && def) j["default"] = true;
		}

		Json json;
		this.m_value.match!(
			(const NativePath v) @trusted {
				initJson(json, optional, default_);
				json["path"] = v.toString();
			},

			(const Repository v) @trusted {
				initJson(json, optional, default_);
				json["repository"] = v.toString();
				json["version"] = v.m_ref;
			},

			(const VersionRange v) @trusted {
				if (!selections && (optional || default_))
				{
					initJson(json, optional, default_);
					json["version"] = v.toString();
				}
				else
					json = Json(v.toString());
			},
		);
		return json;
	}

	@trusted unittest {
		Dependency d = Dependency("==1.0.0");
		assert(d.toJson() == Json("1.0.0"), "Failed: " ~ d.toJson().toPrettyString());
		d = fromJson((fromJson(d.toJson())).toJson());
		assert(d == Dependency("1.0.0"));
		assert(d.toJson() == Json("1.0.0"), "Failed: " ~ d.toJson().toPrettyString());
	}

	@trusted unittest {
		Dependency dependency = Dependency(Repository("git+http://localhost", "1.0.0"));
		Json expected = Json([
			"repository": Json("git+http://localhost"),
			"version": Json("1.0.0")
		]);
		assert(dependency.toJson() == expected, "Failed: " ~ dependency.toJson().toPrettyString());
	}

	@trusted unittest {
		Dependency d = Dependency(NativePath("dir"));
		Json expected = Json([ "path": Json("dir") ]);
		assert(d.toJson() == expected, "Failed: " ~ d.toJson().toPrettyString());
	}

	/** Constructs a new `Dependency` from its JSON representation.

		See `toJson` for a description of the JSON format.
	*/
	static Dependency fromJson(Json verspec)
	@trusted { // NOTE Path and Json is @system in vibe.d 0.7.x and in the compatibility layer
		Dependency dep;
		if( verspec.type == Json.Type.object ){
			if( auto pp = "path" in verspec ) {
				dep = Dependency(NativePath(verspec["path"].get!string));
			} else if (auto repository = "repository" in verspec) {
				enforce("version" in verspec, "No version field specified!");
				enforce(repository.length > 0, "No repository field specified!");

				dep = Dependency(Repository(
                                     repository.get!string, verspec["version"].get!string));
			} else {
				enforce("version" in verspec, "No version field specified!");
				auto ver = verspec["version"].get!string;
				// Using the string to be able to specify a range of versions.
				dep = Dependency(ver);
			}

			if (auto po = "optional" in verspec) dep.optional = po.get!bool;
			if (auto po = "default" in verspec) dep.default_ = po.get!bool;
		} else {
			// canonical "package-id": "version"
			dep = Dependency(verspec.get!string);
		}
		return dep;
	}

	@trusted unittest {
		assert(fromJson(parseJsonString("\">=1.0.0 <2.0.0\"")) == Dependency(">=1.0.0 <2.0.0"));
		Dependency parsed = fromJson(parseJsonString(`
		{
			"version": "2.0.0",
			"optional": true,
			"default": true,
			"path": "path/to/package"
		}
			`));
		Dependency d = NativePath("path/to/package"); // supposed to ignore the version spec
		d.optional = true;
		d.default_ = true;
		assert(d == parsed);
	}

	/** Compares dependency specifications.

		These methods are suitable for equality comparisons, as well as for
		using `Dependency` as a key in hash or tree maps.
	*/
	bool opEquals(in Dependency o) const scope @safe {
		if (o.m_optional != this.m_optional) return false;
		if (o.m_default  != this.m_default)  return false;
		return this.m_value == o.m_value;
	}

	/// ditto
	int opCmp(in Dependency o) const @safe {
		alias ResultMatch = match!(
			(VersionRange r1, VersionRange r2) => r1.opCmp(r2),
			(_1, _2) => 0,
		);
		if (auto result = ResultMatch(this.m_value, o.m_value))
			return result;
		if (m_optional != o.m_optional) return m_optional ? -1 : 1;
		return 0;
	}

	/** Determines if this dependency specification is valid.

		A specification is valid if it can match at least one version.
	*/
	bool valid() const @safe {
		return this.m_value.match!(
			(NativePath v) => true,
			(Repository v) => true,
			(VersionRange v) => v.isValid(),
		);
	}

	/** Determines if this dependency specification matches arbitrary versions.

		This is true in particular for the `any` constant.
	*/
	deprecated("Use `VersionRange.matchesAny` directly")
	bool matchesAny() const scope @safe {
		return this.m_value.match!(
			(NativePath v) => true,
			(Repository v) => true,
			(VersionRange v) => v.matchesAny(),
		);
	}

	/** Tests if the specification matches a specific version.
	*/
	bool matches(string vers, VersionMatchMode mode = VersionMatchMode.standard) const @safe
	{
		return matches(Version(vers), mode);
	}
	/// ditto
	bool matches(in  Version v, VersionMatchMode mode = VersionMatchMode.standard) const @safe {
		return this.m_value.match!(
			(NativePath i) => true,
			(Repository i) => true,
			(VersionRange i) => i.matchesAny() || i.matches(v, mode),
		);
	}

	/** Merges two dependency specifications.

		The result is a specification that matches the intersection of the set
		of versions matched by the individual specifications. Note that this
		result can be invalid (i.e. not match any version).
	*/
	Dependency merge(ref const(Dependency) o) const @trusted {
		alias Merger = match!(
			(const NativePath a, const NativePath b) => a == b ? this : Invalid,
			(const NativePath a,       any         ) => o,
			(      any         , const NativePath b) => this,

			(const Repository a, const Repository b) => a.m_ref == b.m_ref ? this : Invalid,
			(const Repository a,       any         ) => this,
			(      any         , const Repository b) => o,

			(const VersionRange a, const VersionRange b) {
				if (a.matchesAny()) return o;
				if (b.matchesAny()) return this;

				VersionRange copy = a;
				copy.merge(b);
				if (!copy.isValid()) return Invalid;
				return Dependency(copy);
			}
		);

		Dependency ret = Merger(this.m_value, o.m_value);
		ret.m_optional = m_optional && o.m_optional;
		return ret;
	}
}

/// Allow direct access to the underlying dependency
public auto visit (Handlers...) (const auto ref Dependency dep)
{
    return dep.m_value.match!(Handlers);
}

//// Ditto
public auto visit (Handlers...) (auto ref Dependency dep)
{
    return dep.m_value.match!(Handlers);
}


unittest {
	Dependency a = Dependency(">=1.1.0"), b = Dependency(">=1.3.0");
	assert (a.merge(b).valid() && a.merge(b).toString() == ">=1.3.0", a.merge(b).toString());

	assertThrown(Dependency("<=2.0.0 >=1.0.0"));
	assertThrown(Dependency(">=2.0.0 <=1.0.0"));

	a = Dependency(">=1.0.0 <=5.0.0"); b = Dependency(">=2.0.0");
	assert (a.merge(b).valid() && a.merge(b).toString() == ">=2.0.0 <=5.0.0", a.merge(b).toString());

	assertThrown(a = Dependency(">1.0.0 ==5.0.0"), "Construction is invalid");

	a = Dependency(">1.0.0"); b = Dependency("<2.0.0");
	assert (a.merge(b).valid(), a.merge(b).toString());
	assert (a.merge(b).toString() == ">1.0.0 <2.0.0", a.merge(b).toString());

	a = Dependency(">2.0.0"); b = Dependency("<1.0.0");
	assert (!(a.merge(b)).valid(), a.merge(b).toString());

	a = Dependency(">=2.0.0"); b = Dependency("<=1.0.0");
	assert (!(a.merge(b)).valid(), a.merge(b).toString());

	a = Dependency("==2.0.0"); b = Dependency("==1.0.0");
	assert (!(a.merge(b)).valid(), a.merge(b).toString());

	a = Dependency("1.0.0"); b = Dependency("==1.0.0");
	assert (a == b);

	a = Dependency("<=2.0.0"); b = Dependency("==1.0.0");
	Dependency m = a.merge(b);
	assert (m.valid(), m.toString());
	assert (m.matches(Version("1.0.0")));
	assert (!m.matches(Version("1.1.0")));
	assert (!m.matches(Version("0.0.1")));


	// branches / head revisions
	a = Dependency(Version.masterBranch);
	assert(a.valid());
	assert(a.matches(Version.masterBranch));
	b = Dependency(Version.masterBranch);
	m = a.merge(b);
	assert(m.matches(Version.masterBranch));

	//assertThrown(a = Dependency(Version.MASTER_STRING ~ " <=1.0.0"), "Construction invalid");
	assertThrown(a = Dependency(">=1.0.0 " ~ Version.masterBranch.toString()), "Construction invalid");

	immutable string branch1 = Version.branchPrefix ~ "Branch1";
	immutable string branch2 = Version.branchPrefix ~ "Branch2";

	//assertThrown(a = Dependency(branch1 ~ " " ~ branch2), "Error: '" ~ branch1 ~ " " ~ branch2 ~ "' succeeded");
	//assertThrown(a = Dependency(Version.MASTER_STRING ~ " " ~ branch1), "Error: '" ~ Version.MASTER_STRING ~ " " ~ branch1 ~ "' succeeded");

	a = Dependency(branch1);
	b = Dependency(branch2);
	assert(!a.merge(b).valid, "Shouldn't be able to merge to different branches");
	b = a.merge(a);
	assert(b.valid, "Should be able to merge the same branches. (?)");
	assert(a == b);

	a = Dependency(branch1);
	assert(a.matches(branch1), "Dependency(branch1) does not match 'branch1'");
	assert(a.matches(Version(branch1)), "Dependency(branch1) does not match Version('branch1')");
	assert(!a.matches(Version.masterBranch), "Dependency(branch1) matches Version.masterBranch");
	assert(!a.matches(branch2), "Dependency(branch1) matches 'branch2'");
	assert(!a.matches(Version("1.0.0")), "Dependency(branch1) matches '1.0.0'");
	a = Dependency(">=1.0.0");
	assert(!a.matches(Version(branch1)), "Dependency(1.0.0) matches 'branch1'");

	// Testing optional dependencies.
	a = Dependency(">=1.0.0");
	assert(!a.optional, "Default is not optional.");
	b = a;
	assert(!a.merge(b).optional, "Merging two not optional dependencies wrong.");
	a.optional = true;
	assert(!a.merge(b).optional, "Merging optional with not optional wrong.");
	b.optional = true;
	assert(a.merge(b).optional, "Merging two optional dependencies wrong.");

	// SemVer's sub identifiers.
	a = Dependency(">=1.0.0-beta");
	assert(!a.matches(Version("1.0.0-alpha")), "Failed: match 1.0.0-alpha with >=1.0.0-beta");
	assert(a.matches(Version("1.0.0-beta")), "Failed: match 1.0.0-beta with >=1.0.0-beta");
	assert(a.matches(Version("1.0.0")), "Failed: match 1.0.0 with >=1.0.0-beta");
	assert(a.matches(Version("1.0.0-rc")), "Failed: match 1.0.0-rc with >=1.0.0-beta");

	// Approximate versions.
	a = Dependency("~>3.0");
	b = Dependency(">=3.0.0 <4.0.0-0");
	assert(a == b, "Testing failed: " ~ a.toString());
	assert(a.matches(Version("3.1.146")), "Failed: Match 3.1.146 with ~>0.1.2");
	assert(!a.matches(Version("0.2.0")), "Failed: Match 0.2.0 with ~>0.1.2");
	assert(!a.matches(Version("4.0.0-beta.1")));
	a = Dependency("~>3.0.0");
	assert(a == Dependency(">=3.0.0 <3.1.0-0"), "Testing failed: " ~ a.toString());
	a = Dependency("~>3.5");
	assert(a == Dependency(">=3.5.0 <4.0.0-0"), "Testing failed: " ~ a.toString());
	a = Dependency("~>3.5.0");
	assert(a == Dependency(">=3.5.0 <3.6.0-0"), "Testing failed: " ~ a.toString());
	assert(!Dependency("~>3.0.0").matches(Version("3.1.0-beta")));

	a = Dependency("^0.1.2");
	assert(a == Dependency(">=0.1.2 <0.1.3-0"));
	a = Dependency("^1.2.3");
	assert(a == Dependency(">=1.2.3 <2.0.0-0"), "Testing failed: " ~ a.toString());
	a = Dependency("^1.2");
	assert(a == Dependency(">=1.2.0 <2.0.0-0"), "Testing failed: " ~ a.toString());

	a = Dependency("~>0.1.1");
	b = Dependency("==0.1.0");
	assert(!a.merge(b).valid);
	b = Dependency("==0.1.9999");
	assert(a.merge(b).valid);
	b = Dependency("==0.2.0");
	assert(!a.merge(b).valid);
	b = Dependency("==0.2.0-beta.1");
	assert(!a.merge(b).valid);

	a = Dependency("~>1.0.1-beta");
	b = Dependency(">=1.0.1-beta <1.1.0-0");
	assert(a == b, "Testing failed: " ~ a.toString());
	assert(a.matches(Version("1.0.1-beta")));
	assert(a.matches(Version("1.0.1-beta.6")));

	a = Dependency("~d2test");
	assert(!a.optional);
	assert(a.valid);
	assert(a.version_ == Version("~d2test"));

	a = Dependency("==~d2test");
	assert(!a.optional);
	assert(a.valid);
	assert(a.version_ == Version("~d2test"));

	a = Dependency.Any;
	assert(!a.optional);
	assert(a.valid);
	assertThrown(a.version_);
	assert(a.matches(Version.masterBranch));
	assert(a.matches(Version("1.0.0")));
	assert(a.matches(Version("0.0.1-pre")));
	b = Dependency(">=1.0.1");
	assert(b == a.merge(b));
	assert(b == b.merge(a));
	b = Dependency(Version.masterBranch);
	assert(a.merge(b) == b);
	assert(b.merge(a) == b);

	a.optional = true;
	assert(a.matches(Version.masterBranch));
	assert(a.matches(Version("1.0.0")));
	assert(a.matches(Version("0.0.1-pre")));
	b = Dependency(">=1.0.1");
	assert(b == a.merge(b));
	assert(b == b.merge(a));
	b = Dependency(Version.masterBranch);
	assert(a.merge(b) == b);
	assert(b.merge(a) == b);

	assert(Dependency("1.0.0").matches(Version("1.0.0+foo")));
	assert(Dependency("1.0.0").matches(Version("1.0.0+foo"), VersionMatchMode.standard));
	assert(!Dependency("1.0.0").matches(Version("1.0.0+foo"), VersionMatchMode.strict));
	assert(Dependency("1.0.0+foo").matches(Version("1.0.0+foo"), VersionMatchMode.strict));
	assert(Dependency("~>1.0.0+foo").matches(Version("1.0.0+foo"), VersionMatchMode.strict));
	assert(Dependency("~>1.0.0").matches(Version("1.0.0+foo"), VersionMatchMode.strict));
}

unittest {
	assert(VersionRange.fromString("~>1.0.4").toString() == "~>1.0.4");
	assert(VersionRange.fromString("~>1.4").toString() == "~>1.4");
	assert(VersionRange.fromString("~>2").toString() == "~>2");
	assert(VersionRange.fromString("~>1.0.4+1.2.3").toString() == "~>1.0.4");
	assert(VersionRange.fromString("^0.1.2").toString() == "^0.1.2");
	assert(VersionRange.fromString("^1.2.3").toString() == "^1.2.3");
	assert(VersionRange.fromString("^1.2").toString() == "~>1.2"); // equivalent; prefer ~>
}

/**
	Represents an SCM repository.
*/
struct Repository
{
	private string m_remote;
	private string m_ref;

	private Kind m_kind;

	enum Kind
	{
		git,
	}

	/**
		Params:
			remote = Repository remote.
			ref_   = Reference to use (SHA1, tag, branch name...)
	 */
	this(string remote, string ref_)
	{
		enforce(remote.startsWith("git+"), "Unsupported repository type (supports: git+URL)");

		m_remote = remote["git+".length .. $];
		m_kind = Kind.git;
		m_ref = ref_;
		assert(m_remote.length);
		assert(m_ref.length);
	}

	/// Ditto
	deprecated("Use the constructor accepting a second parameter named `ref_`")
	this(string remote)
	{
		enforce(remote.startsWith("git+"), "Unsupported repository type (supports: git+URL)");

		m_remote = remote["git+".length .. $];
		m_kind = Kind.git;
		assert(m_remote.length);
	}

	string toString() const nothrow pure @safe
	{
		if (empty) return null;
		string kindRepresentation;

		final switch (kind)
		{
			case Kind.git:
				kindRepresentation = "git";
		}
		return kindRepresentation~"+"~remote;
	}

	/**
		Returns:
			Repository URL or path.
	*/
	@property string remote() const @nogc nothrow pure @safe
	in { assert(m_remote !is null); }
	do
	{
		return m_remote;
	}

	/**
		Returns:
			The reference (commit hash, branch name, tag) we are targeting
	*/
	@property string ref_() const @nogc nothrow pure @safe
	in { assert(m_remote !is null); }
	in { assert(m_ref !is null); }
	do
	{
		return m_ref;
	}

	/**
		Returns:
			Repository type.
	*/
	@property Kind kind() const @nogc nothrow pure @safe
	{
		return m_kind;
	}

	/**
		Returns:
			Whether the repository was initialized with an URL or path.
	*/
	@property bool empty() const @nogc nothrow pure @safe
	{
		return m_remote.empty;
	}
}


/**
	Represents a version in semantic version format, or a branch identifier.

	This can either have the form "~master", where "master" is a branch name,
	or the form "major.update.bugfix-prerelease+buildmetadata" (see the
	Semantic Versioning Specification v2.0.0 at http://semver.org/).
*/
struct Version {
	private {
		static immutable MAX_VERS = "99999.0.0";
		static immutable masterString = "~master";
		enum branchPrefix = '~';
		string m_version;
	}

	static immutable Version minRelease = Version("0.0.0");
	static immutable Version maxRelease = Version(MAX_VERS);
	static immutable Version masterBranch = Version(masterString);

	/** Constructs a new `Version` from its string representation.
	*/
	this(string vers) @safe pure
	{
		enforce(vers.length > 1, "Version strings must not be empty.");
		if (vers[0] != branchPrefix)
			enforce(vers.isValidVersion(), "Invalid SemVer format: " ~ vers);
		m_version = vers;
	}

	/** Constructs a new `Version` from its string representation.

		This method is equivalent to calling the constructor and is used as an
		endpoint for the serialization framework.
	*/
	static Version fromString(string vers) @safe pure { return Version(vers); }

	bool opEquals(in Version oth) const scope @safe pure
	{
		return opCmp(oth) == 0;
	}

	/// Tests if this represents a branch instead of a version.
	@property bool isBranch() const scope @safe pure nothrow @nogc
	{
		return m_version.length > 0 && m_version[0] == branchPrefix;
	}

	/// Tests if this represents the master branch "~master".
	@property bool isMaster() const scope @safe pure nothrow @nogc
	{
		return m_version == masterString;
	}

	/** Tests if this represents a pre-release version.

		Note that branches are always considered pre-release versions.
	*/
	@property bool isPreRelease() const scope @safe pure nothrow @nogc
	{
		if (isBranch) return true;
		return isPreReleaseVersion(m_version);
	}

	/** Tests two versions for equality, according to the selected match mode.
	*/
	bool matches(in Version other, VersionMatchMode mode = VersionMatchMode.standard)
	const scope @safe pure
	{
		if (mode == VersionMatchMode.strict)
			return this.toString() == other.toString();
		return this == other;
	}

	/** Compares two versions/branches for precedence.

		Versions generally have precedence over branches and the master branch
		has precedence over other branches. Apart from that, versions are
		compared using SemVer semantics, while branches are compared
		lexicographically.
	*/
	int opCmp(in Version other) const scope @safe pure
	{
		if (isBranch || other.isBranch) {
			if(m_version == other.m_version) return 0;
			if (!isBranch) return 1;
			else if (!other.isBranch) return -1;
			if (isMaster) return 1;
			else if (other.isMaster) return -1;
			return this.m_version < other.m_version ? -1 : 1;
		}

		return compareVersions(m_version, other.m_version);
	}

	/// Returns the string representation of the version/branch.
	string toString() const return scope @safe pure nothrow @nogc
	{
		return m_version;
	}
}

/**
 * A range of versions that are acceptable
 *
 * While not directly described in SemVer v2.0.0, a common set
 * of range operators have appeared among package managers.
 * We mostly NPM's: https://semver.npmjs.com/
 *
 * Hence the acceptable forms for this string are as follows:
 *
 * $(UL
 *  $(LI `"1.0.0"` - a single version in SemVer format)
 *  $(LI `"==1.0.0"` - alternative single version notation)
 *  $(LI `">1.0.0"` - version range with a single bound)
 *  $(LI `">1.0.0 <2.0.0"` - version range with two bounds)
 *  $(LI `"~>1.0.0"` - a fuzzy version range)
 *  $(LI `"~>1.0"` - a fuzzy version range with partial version)
 *  $(LI `"^1.0.0"` - semver compatible version range (same version if 0.x.y, ==major >=minor.patch if x.y.z))
 *  $(LI `"^1.0"` - same as ^1.0.0)
 *  $(LI `"~master"` - a branch name)
 *  $(LI `"*"` - match any version (see also `VersionRange.Any`))
 * )
 *
 * Apart from "$(LT)" and "$(GT)", "$(GT)=" and "$(LT)=" are also valid
 * comparators.
 */
public struct VersionRange
{
	private Version m_versA;
	private Version m_versB;
	private bool m_inclusiveA = true; // A comparison > (true) or >= (false)
	private bool m_inclusiveB = true; // B comparison < (true) or <= (false)

	/// Matches any version
	public static immutable Any = VersionRange(Version.minRelease, Version.maxRelease);
	/// Doesn't match any version
	public static immutable Invalid = VersionRange(Version.maxRelease, Version.minRelease);

	///
	public int opCmp (in VersionRange o) const scope @safe
	{
		if (m_inclusiveA != o.m_inclusiveA) return m_inclusiveA < o.m_inclusiveA ? -1 : 1;
		if (m_inclusiveB != o.m_inclusiveB) return m_inclusiveB < o.m_inclusiveB ? -1 : 1;
		if (m_versA != o.m_versA) return m_versA < o.m_versA ? -1 : 1;
		if (m_versB != o.m_versB) return m_versB < o.m_versB ? -1 : 1;
		return 0;
	}

	public bool matches (in Version v, VersionMatchMode mode = VersionMatchMode.standard)
		const scope @safe
	{
		if (m_versA.isBranch) {
			enforce(this.isExactVersion());
			return m_versA == v;
		}

		if (v.isBranch)
			return m_versA == v;

		if (m_versA == m_versB)
			return this.m_versA.matches(v, mode);

		return doCmp(m_inclusiveA, m_versA, v) &&
			doCmp(m_inclusiveB, v, m_versB);
	}

	/// Modify in place
	public void merge (const VersionRange o) @safe
	{
		int acmp = m_versA.opCmp(o.m_versA);
		int bcmp = m_versB.opCmp(o.m_versB);

		this.m_inclusiveA = !m_inclusiveA && acmp >= 0 ? false : o.m_inclusiveA;
		this.m_versA = acmp > 0 ? m_versA : o.m_versA;
		this.m_inclusiveB = !m_inclusiveB && bcmp <= 0 ? false : o.m_inclusiveB;
		this.m_versB = bcmp < 0 ? m_versB : o.m_versB;
	}

	/// Returns true $(I iff) the version range only matches a specific version.
	@property bool isExactVersion() const scope @safe
	{
		return this.m_versA == this.m_versB;
	}

	/// Determines if this dependency specification matches arbitrary versions.
	/// This is true in particular for the `any` constant.
	public bool matchesAny() const scope @safe
	{
		return this.m_inclusiveA && this.m_inclusiveB
			&& this.m_versA == Version.minRelease
			&& this.m_versB == Version.maxRelease;
	}

	unittest {
		assert(VersionRange.fromString("*").matchesAny);
		assert(!VersionRange.fromString(">0.0.0").matchesAny);
		assert(!VersionRange.fromString(">=1.0.0").matchesAny);
		assert(!VersionRange.fromString("<1.0.0").matchesAny);
	}

	public static VersionRange fromString (string ves) @safe
	{
		static import std.string;

		enforce(ves.length > 0);

		if (ves == Dependency.ANY_IDENT) {
			// Any version is good.
			ves = ">=0.0.0";
		}

		if (ves.startsWith("~>")) {
			// Shortcut: "~>x.y.z" variant. Last non-zero number will indicate
			// the base for this so something like this: ">=x.y.z <x.(y+1).z"
			ves = ves[2..$];
			return VersionRange(
				Version(expandVersion(ves)), Version(bumpVersion(ves) ~ "-0"),
				true, false);
		}

		if (ves.startsWith("^")) {
			// Shortcut: "^x.y.z" variant. "Semver compatible" - no breaking changes.
			// if 0.x.y, ==0.x.y
			// if x.y.z, >=x.y.z <(x+1).0.0-0
			// ^x.y is equivalent to ^x.y.0.
			ves = ves[1..$].expandVersion;
			return VersionRange(
				Version(ves), Version(bumpIncompatibleVersion(ves) ~ "-0"),
				true, false);
		}

		if (ves[0] == Version.branchPrefix) {
			auto ver = Version(ves);
			return VersionRange(ver, ver, true, true);
		}

		if (std.string.indexOf("><=", ves[0]) == -1) {
			auto ver = Version(ves);
			return VersionRange(ver, ver, true, true);
		}

		auto cmpa = skipComp(ves);
		size_t idx2 = std.string.indexOf(ves, " ");
		if (idx2 == -1) {
			if (cmpa == "<=" || cmpa == "<")
				return VersionRange(Version.minRelease, Version(ves), true, (cmpa == "<="));

			if (cmpa == ">=" || cmpa == ">")
				return VersionRange(Version(ves), Version.maxRelease, (cmpa == ">="), true);

			// Converts "==" to ">=a&&<=a", which makes merging easier
			return VersionRange(Version(ves), Version(ves), true, true);
		}

		enforce(cmpa == ">" || cmpa == ">=",
				"First comparison operator expected to be either > or >=, not " ~ cmpa);
		assert(ves[idx2] == ' ');
		VersionRange ret;
		ret.m_versA = Version(ves[0..idx2]);
		ret.m_inclusiveA = cmpa == ">=";
		string v2 = ves[idx2+1..$];
		auto cmpb = skipComp(v2);
		enforce(cmpb == "<" || cmpb == "<=",
				"Second comparison operator expected to be either < or <=, not " ~ cmpb);
		ret.m_versB = Version(v2);
		ret.m_inclusiveB = cmpb == "<=";

		enforce(!ret.m_versA.isBranch && !ret.m_versB.isBranch,
				format("Cannot compare branches: %s", ves));
		enforce(ret.m_versA <= ret.m_versB,
				"First version must not be greater than the second one.");

		return ret;
	}

	/// Returns a string representation of this range
	string toString() const @safe {
		static import std.string;

		string r;

		if (this == Invalid) return "no";
		if (this.isExactVersion() && m_inclusiveA && m_inclusiveB) {
			// Special "==" case
			if (m_versA == Version.masterBranch) return "~master";
			else return m_versA.toString();
		}

		// "~>", "^" case
		if (m_inclusiveA && !m_inclusiveB && !m_versA.isBranch) {
			auto vs = m_versA.toString();
			auto i1 = std.string.indexOf(vs, '-'), i2 = std.string.indexOf(vs, '+');
			auto i12 = i1 >= 0 ? i2 >= 0 ? i1 < i2 ? i1 : i2 : i1 : i2;
			auto va = i12 >= 0 ? vs[0 .. i12] : vs;
			auto parts = va.splitter('.').array;
			assert(parts.length == 3, "Version string with a digit group count != 3: "~va);

			foreach (i; 0 .. 3) {
				auto vp = parts[0 .. i+1].join(".");
				auto ve = Version(expandVersion(vp));
				auto veb = Version(bumpVersion(vp) ~ "-0");
				if (ve == m_versA && veb == m_versB) return "~>" ~ vp;

				auto veb2 = Version(bumpIncompatibleVersion(expandVersion(vp)) ~ "-0");
				if (ve == m_versA && veb2 == m_versB) return "^" ~ vp;
			}
		}

		if (m_versA != Version.minRelease) r = (m_inclusiveA ? ">=" : ">") ~ m_versA.toString();
		if (m_versB != Version.maxRelease) r ~= (r.length==0 ? "" : " ") ~ (m_inclusiveB ? "<=" : "<") ~ m_versB.toString();
		if (this.matchesAny()) r = ">=0.0.0";
		return r;
	}

	public bool isValid() const @safe {
		return m_versA <= m_versB && doCmp(m_inclusiveA && m_inclusiveB, m_versA, m_versB);
	}

	private static bool doCmp(bool inclusive, in Version a, in Version b)
		@safe
	{
		return inclusive ? a <= b : a < b;
	}

	private static bool isDigit(char ch) @safe { return ch >= '0' && ch <= '9'; }
	private static string skipComp(ref string c) @safe {
		size_t idx = 0;
		while (idx < c.length && !isDigit(c[idx]) && c[idx] != Version.branchPrefix) idx++;
		enforce(idx < c.length, "Expected version number in version spec: "~c);
		string cmp = idx==c.length-1||idx==0? ">=" : c[0..idx];
		c = c[idx..$];
		switch(cmp) {
			default: enforce(false, "No/Unknown comparison specified: '"~cmp~"'"); return ">=";
			case ">=": goto case; case ">": goto case;
			case "<=": goto case; case "<": goto case;
			case "==": return cmp;
		}
	}
}

enum VersionMatchMode {
	standard,  /// Match according to SemVer rules
	strict     /// Also include build metadata suffix in the comparison
}

unittest {
	Version a, b;

	assertNotThrown(a = Version("1.0.0"), "Constructing Version('1.0.0') failed");
	assert(!a.isBranch, "Error: '1.0.0' treated as branch");
	assert(a == a, "a == a failed");

	assertNotThrown(a = Version(Version.masterString), "Constructing Version("~Version.masterString~"') failed");
	assert(a.isBranch, "Error: '"~Version.masterString~"' treated as branch");
	assert(a.isMaster);
	assert(a == Version.masterBranch, "Constructed master version != default master version.");

	assertNotThrown(a = Version("~BRANCH"), "Construction of branch Version failed.");
	assert(a.isBranch, "Error: '~BRANCH' not treated as branch'");
	assert(!a.isMaster);
	assert(a == a, "a == a with branch failed");

	// opCmp
	a = Version("1.0.0");
	b = Version("1.0.0");
	assert(a == b, "a == b with a:'1.0.0', b:'1.0.0' failed");
	b = Version("2.0.0");
	assert(a != b, "a != b with a:'1.0.0', b:'2.0.0' failed");

	a = Version.masterBranch;
	b = Version("~BRANCH");
	assert(a != b, "a != b with a:MASTER, b:'~branch' failed");
	assert(a > b);
	assert(a < Version("0.0.0"));
	assert(b < Version("0.0.0"));
	assert(a > Version("~Z"));
	assert(b < Version("~Z"));

	// SemVer 2.0.0-rc.2
	a = Version("2.0.0-rc.2");
	b = Version("2.0.0-rc.3");
	assert(a < b, "Failed: 2.0.0-rc.2 < 2.0.0-rc.3");

	a = Version("2.0.0-rc.2+build-metadata");
	b = Version("2.0.0+build-metadata");
	assert(a < b, "Failed: "~a.toString()~"<"~b.toString());

	// 1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0
	Version[] versions;
	versions ~= Version("1.0.0-alpha");
	versions ~= Version("1.0.0-alpha.1");
	versions ~= Version("1.0.0-beta.2");
	versions ~= Version("1.0.0-beta.11");
	versions ~= Version("1.0.0-rc.1");
	versions ~= Version("1.0.0");
	for(int i=1; i<versions.length; ++i)
		for(int j=i-1; j>=0; --j)
			assert(versions[j] < versions[i], "Failed: " ~ versions[j].toString() ~ "<" ~ versions[i].toString());

	assert(Version("1.0.0+a") == Version("1.0.0+b"));

	assert(Version("1.0.0").matches(Version("1.0.0+foo")));
	assert(Version("1.0.0").matches(Version("1.0.0+foo"), VersionMatchMode.standard));
	assert(!Version("1.0.0").matches(Version("1.0.0+foo"), VersionMatchMode.strict));
	assert(Version("1.0.0+foo").matches(Version("1.0.0+foo"), VersionMatchMode.strict));
}

/// Determines whether the given string is a Git hash.
bool isGitHash(string hash) @nogc nothrow pure @safe
{
	import std.ascii : isHexDigit;
	import std.utf : byCodeUnit;

	return hash.length >= 7 && hash.length <= 40 && hash.byCodeUnit.all!isHexDigit;
}

@nogc nothrow pure @safe unittest {
	assert(isGitHash("73535568b79a0b124bc1653002637a830ce0fcb8"));
	assert(!isGitHash("735"));
	assert(!isGitHash("73535568b79a0b124bc1-53002637a830ce0fcb8"));
	assert(!isGitHash("73535568b79a0b124bg1"));
}
