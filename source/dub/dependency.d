/**
	Dependency specification functionality.

	Copyright: © 2012-2013 Matthias Dondorff, © 2012-2016 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff, Sönke Ludwig
*/
module dub.dependency;

import dub.internal.utils;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.path;
import dub.package_;
import dub.semver;

import std.algorithm;
import std.array;
import std.exception;
import std.string;


/** Encapsulates the name of a package along with its dependency specification.
*/
struct PackageDependency {
	/// Name of the referenced package.
	string name;

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
@safe:

	private {
		// Shortcut to create >=0.0.0
		enum ANY_IDENT = "*";
		bool m_inclusiveA = true; // A comparison > (true) or >= (false)
		Version m_versA;
		bool m_inclusiveB = true; // B comparison < (true) or <= (false)
		Version m_versB;
		NativePath m_path;
		bool m_optional = false;
		bool m_default = false;
		Repository m_repository;
	}

	/// A Dependency, which matches every valid version.
	static @property Dependency any() { return Dependency(ANY_IDENT); }

	/// An invalid dependency (with no possible version matches).
	static @property Dependency invalid() { Dependency ret; ret.m_versA = Version.maxRelease; ret.m_versB = Version.minRelease; return ret; }

	/** Constructs a new dependency specification from a string

		See the `versionSpec` property for a description of the accepted
		contents of that string.
	*/
	this(string spec)
	{
		this.versionSpec = spec;
	}

	/** Constructs a new dependency specification that matches a specific
		version.
	*/
	this(const Version ver)
	{
		m_inclusiveA = m_inclusiveB = true;
		m_versA = ver;
		m_versB = ver;
	}

	/** Constructs a new dependency specification that matches a specific
		path.
	*/
	this(NativePath path)
	{
		this(ANY_IDENT);
		m_path = path;
	}

	/** Constructs a new dependency specification that matches a specific
		Git reference.
	*/
	this(Repository repository, string spec) {
		this.versionSpec = spec;
		this.repository = repository;
	}

	/// If set, overrides any version based dependency selection.
	@property void path(NativePath value) { m_path = value; }
	/// ditto
	@property NativePath path() const { return m_path; }

	/// If set, overrides any version based dependency selection.
	@property void repository(Repository value)
	{
		m_repository = value;
	}

	/// ditto
	@property Repository repository() const
	{
		return m_repository;
	}

	/// Determines if the dependency is required or optional.
	@property bool optional() const { return m_optional; }
	/// ditto
	@property void optional(bool optional) { m_optional = optional; }

	/// Determines if an optional dependency should be chosen by default.
	@property bool default_() const { return m_default; }
	/// ditto
	@property void default_(bool value) { m_default = value; }

	/// Returns true $(I iff) the version range only matches a specific version.
	@property bool isExactVersion() const { return m_versA == m_versB; }

	/// Determines whether it is a Git dependency.
	@property bool isSCM() const { return !repository.empty; }

	/// Returns the exact version matched by the version range.
	@property Version version_() const {
		enforce(m_versA == m_versB, "Dependency "~this.versionSpec~" is no exact version.");
		return m_versA;
	}

	/** Sets/gets the matching version range as a specification string.

		The acceptable forms for this string are as follows:

		$(UL
			$(LI `"1.0.0"` - a single version in SemVer format)
			$(LI `"==1.0.0"` - alternative single version notation)
			$(LI `">1.0.0"` - version range with a single bound)
			$(LI `">1.0.0 <2.0.0"` - version range with two bounds)
			$(LI `"~>1.0.0"` - a fuzzy version range)
			$(LI `"~>1.0"` - a fuzzy version range with partial version)
			$(LI `"^1.0.0"` - semver compatible version range (same version if 0.x.y, ==major >=minor.patch if x.y.z))
			$(LI `"^1.0"` - same as ^1.0.0)
			$(LI `"~master"` - a branch name)
			$(LI `"*" - match any version (see also `any`))
		)

		Apart from "$(LT)" and "$(GT)", "$(GT)=" and "$(LT)=" are also valid
		comparators.

	*/
	@property void versionSpec(string ves)
	{
		static import std.string;

		enforce(ves.length > 0);

		if (ves == ANY_IDENT) {
			// Any version is good.
			ves = ">=0.0.0";
		}

		if (ves.startsWith("~>")) {
			// Shortcut: "~>x.y.z" variant. Last non-zero number will indicate
			// the base for this so something like this: ">=x.y.z <x.(y+1).z"
			m_inclusiveA = true;
			m_inclusiveB = false;
			ves = ves[2..$];
			m_versA = Version(expandVersion(ves));
			m_versB = Version(bumpVersion(ves) ~ "-0");
		} else if (ves.startsWith("^")) {
			// Shortcut: "^x.y.z" variant. "Semver compatible" - no breaking changes.
			// if 0.x.y, ==0.x.y
			// if x.y.z, >=x.y.z <(x+1).0.0-0
			// ^x.y is equivalent to ^x.y.0.
			m_inclusiveA = true;
			m_inclusiveB = false;
			ves = ves[1..$].expandVersion;
			m_versA = Version(ves);
			m_versB = Version(bumpIncompatibleVersion(ves) ~ "-0");
		} else if (ves[0] == Version.branchPrefix || ves.isGitHash) {
			m_inclusiveA = true;
			m_inclusiveB = true;
			m_versA = m_versB = Version(ves);
		} else if (std.string.indexOf("><=", ves[0]) == -1) {
			m_inclusiveA = true;
			m_inclusiveB = true;
			m_versA = m_versB = Version(ves);
		} else {
			auto cmpa = skipComp(ves);
			size_t idx2 = std.string.indexOf(ves, " ");
			if (idx2 == -1) {
				if (cmpa == "<=" || cmpa == "<") {
					m_versA = Version.minRelease;
					m_inclusiveA = true;
					m_versB = Version(ves);
					m_inclusiveB = cmpa == "<=";
				} else if (cmpa == ">=" || cmpa == ">") {
					m_versA = Version(ves);
					m_inclusiveA = cmpa == ">=";
					m_versB = Version.maxRelease;
					m_inclusiveB = true;
				} else {
					// Converts "==" to ">=a&&<=a", which makes merging easier
					m_versA = m_versB = Version(ves);
					m_inclusiveA = m_inclusiveB = true;
				}
			} else {
				enforce(cmpa == ">" || cmpa == ">=", "First comparison operator expected to be either > or >=, not "~cmpa);
				assert(ves[idx2] == ' ');
				m_versA = Version(ves[0..idx2]);
				m_inclusiveA = cmpa == ">=";
				string v2 = ves[idx2+1..$];
				auto cmpb = skipComp(v2);
				enforce(cmpb == "<" || cmpb == "<=", "Second comparison operator expected to be either < or <=, not "~cmpb);
				m_versB = Version(v2);
				m_inclusiveB = cmpb == "<=";

				enforce(!m_versA.isBranch && !m_versB.isBranch, format("Cannot compare branches: %s", ves));
				enforce(m_versA <= m_versB, "First version must not be greater than the second one.");
			}
		}
	}
	/// ditto
	@property string versionSpec()
	const {
		static import std.string;

		string r;

		if (this == invalid) return "invalid";
		if (m_versA == m_versB && m_inclusiveA && m_inclusiveB) {
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
		if (m_versA == Version.minRelease && m_versB == Version.maxRelease) r = ">=0.0.0";
		return r;
	}

	/** Returns a modified dependency that gets mapped to a given path.

		This function will return an unmodified `Dependency` if it is not path
		based. Otherwise, the given `path` will be prefixed to the existing
		path.
	*/
	Dependency mapToPath(NativePath path)
	const @trusted { // NOTE Path is @system in vibe.d 0.7.x and in the compatibility layer
		if (m_path.empty || m_path.absolute) return this;
		else {
			Dependency ret = this;
			ret.path = path ~ ret.path;
			return ret;
		}
	}

	/** Returns a human-readable string representation of the dependency
		specification.
	*/
	string toString()()
	const {
		string ret;

		if (!repository.empty) {
			ret ~= repository.toString~"#";
		}
		ret ~= versionSpec;
		if (optional) {
			if (default_) ret ~= " (optional, default)";
			else ret ~= " (optional)";
		}

		// NOTE Path is @system in vibe.d 0.7.x and in the compatibility layer
		() @trusted {
			if (!path.empty) ret ~= " @"~path.toNativeString();
		} ();

		return ret;
	}

	/** Returns a JSON representation of the dependency specification.

		Simple specifications will be represented as a single specification
		string (`versionSpec`), while more complex specifications will be
		represented as a JSON object with optional "version", "path", "optional"
		and "default" fields.
	*/
	Json toJson()
	const @trusted { // NOTE Path and Json is @system in vibe.d 0.7.x and in the compatibility layer
		Json json;
		if( path.empty && repository.empty && !optional ){
			json = Json(this.versionSpec);
		} else {
			json = Json.emptyObject;
			json["version"] = this.versionSpec;
			if (!path.empty) json["path"] = path.toString();
			if (!repository.empty) json["repository"] = repository.toString;
			if (optional) json["optional"] = true;
			if (default_) json["default"] = true;
		}
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
		Dependency dependency = Dependency(Repository("git+http://localhost"), "1.0.0");
		Json expected = Json([
			"repository": Json("git+http://localhost"),
			"version": Json("1.0.0")
		]);
		assert(dependency.toJson() == expected, "Failed: " ~ dependency.toJson().toPrettyString());
	}

	/** Constructs a new `Dependency` from its JSON representation.

		See `toJson` for a description of the JSON format.
	*/
	static Dependency fromJson(Json verspec)
	@trusted { // NOTE Path and Json is @system in vibe.d 0.7.x and in the compatibility layer
		Dependency dep;
		if( verspec.type == Json.Type.object ){
			if( auto pp = "path" in verspec ) {
				if (auto pv = "version" in verspec)
					logDiagnostic("Ignoring version specification (%s) for path based dependency %s", pv.get!string, pp.get!string);

				dep = Dependency.any;
				dep.path = NativePath(verspec["path"].get!string);
			} else if (auto repository = "repository" in verspec) {
				enforce("version" in verspec, "No version field specified!");
				enforce(repository.length > 0, "No repository field specified!");

				dep = Dependency(Repository(repository.get!string),
						verspec["version"].get!string);
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
		Dependency d = Dependency.any; // supposed to ignore the version spec
		d.optional = true;
		d.default_ = true;
		d.path = NativePath("path/to/package");
		assert(d == parsed);
		// optional and path not checked by opEquals.
		assert(d.optional == parsed.optional);
		assert(d.default_ == parsed.default_);
		assert(d.path == parsed.path);
	}

	/** Compares dependency specifications.

		These methods are suitable for equality comparisons, as well as for
		using `Dependency` as a key in hash or tree maps.
	*/
	bool opEquals(const Dependency o)
	const {
		// TODO(mdondorff): Check if not comparing the path is correct for all clients.
		return o.m_inclusiveA == m_inclusiveA && o.m_inclusiveB == m_inclusiveB
			&& o.m_versA == m_versA && o.m_versB == m_versB
			&& o.m_optional == m_optional && o.m_default == m_default;
	}

	/// ditto
	int opCmp(const Dependency o)
	const {
		if (m_inclusiveA != o.m_inclusiveA) return m_inclusiveA < o.m_inclusiveA ? -1 : 1;
		if (m_inclusiveB != o.m_inclusiveB) return m_inclusiveB < o.m_inclusiveB ? -1 : 1;
		if (m_versA != o.m_versA) return m_versA < o.m_versA ? -1 : 1;
		if (m_versB != o.m_versB) return m_versB < o.m_versB ? -1 : 1;
		if (m_optional != o.m_optional) return m_optional ? -1 : 1;
		return 0;
	}

	/// ditto
	size_t toHash()
	const nothrow @trusted  {
		try {
			size_t hash = 0;
			hash = m_inclusiveA.hashOf(hash);
			hash = m_versA.toString().hashOf(hash);
			hash = m_inclusiveB.hashOf(hash);
			hash = m_versB.toString().hashOf(hash);
			hash = m_optional.hashOf(hash);
			hash = m_default.hashOf(hash);
			return hash;
		} catch (Exception) assert(false);
	}

	/** Determines if this dependency specification is valid.

		A specification is valid if it can match at least one version.
	*/
	bool valid() const {
		if (this.isSCM) return true;
		return m_versA <= m_versB && doCmp(m_inclusiveA && m_inclusiveB, m_versA, m_versB);
	}

	/** Determines if this dependency specification matches arbitrary versions.

		This is true in particular for the `any` constant.
	*/
	bool matchesAny()
	const {
		return m_inclusiveA && m_inclusiveB
			&& m_versA.toString() == "0.0.0"
			&& m_versB == Version.maxRelease;
	}

	unittest {
		assert(Dependency("*").matchesAny);
		assert(!Dependency(">0.0.0").matchesAny);
		assert(!Dependency(">=1.0.0").matchesAny);
		assert(!Dependency("<1.0.0").matchesAny);
	}

	/** Tests if the specification matches a specific version.
	*/
	bool matches(string vers) const { return matches(Version(vers)); }
	/// ditto
	bool matches(const(Version) v) const { return matches(v); }
	/// ditto
	bool matches(ref const(Version) v) const {
		if (this.matchesAny) return true;
		if (this.isSCM) return true;
		//logDebug(" try match: %s with: %s", v, this);
		// Master only matches master
		if(m_versA.isBranch) {
			enforce(m_versA == m_versB);
			return m_versA == v;
		}
		if(v.isBranch || m_versA.isBranch)
			return m_versA == v;
		if( !doCmp(m_inclusiveA, m_versA, v) )
			return false;
		if( !doCmp(m_inclusiveB, v, m_versB) )
			return false;
		return true;
	}

	/** Merges two dependency specifications.

		The result is a specification that matches the intersection of the set
		of versions matched by the individual specifications. Note that this
		result can be invalid (i.e. not match any version).
	*/
	Dependency merge(ref const(Dependency) o)
	const {
		if (this.isSCM) {
			if (!o.isSCM) return this;
			if (this.m_versA == o.m_versA) return this;
			return invalid;
		}
		if (o.isSCM) return o;

		if (this.matchesAny) return o;
		if (o.matchesAny) return this;
		if (m_versA.isBranch != o.m_versA.isBranch) return invalid;
		if (m_versB.isBranch != o.m_versB.isBranch) return invalid;
		if (m_versA.isBranch) return m_versA == o.m_versA ? this : invalid;
		// NOTE Path is @system in vibe.d 0.7.x and in the compatibility layer
		if (() @trusted { return this.path != o.path; } ()) return invalid;

		int acmp = m_versA.opCmp(o.m_versA);
		int bcmp = m_versB.opCmp(o.m_versB);

		Dependency d = this;
		d.m_inclusiveA = !m_inclusiveA && acmp >= 0 ? false : o.m_inclusiveA;
		d.m_versA = acmp > 0 ? m_versA : o.m_versA;
		d.m_inclusiveB = !m_inclusiveB && bcmp <= 0 ? false : o.m_inclusiveB;
		d.m_versB = bcmp < 0 ? m_versB : o.m_versB;
		d.m_optional = m_optional && o.m_optional;
		if (!d.valid) return invalid;

		return d;
	}

	private static bool isDigit(char ch) { return ch >= '0' && ch <= '9'; }
	private static string skipComp(ref string c) {
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

	private static bool doCmp(bool inclusive, ref const Version a, ref const Version b) {
		return inclusive ? a <= b : a < b;
	}
}

unittest {
	Dependency a = Dependency(">=1.1.0"), b = Dependency(">=1.3.0");
	assert (a.merge(b).valid() && a.merge(b).versionSpec == ">=1.3.0", a.merge(b).toString());

	assertThrown(Dependency("<=2.0.0 >=1.0.0"));
	assertThrown(Dependency(">=2.0.0 <=1.0.0"));

	a = Dependency(">=1.0.0 <=5.0.0"); b = Dependency(">=2.0.0");
	assert (a.merge(b).valid() && a.merge(b).versionSpec == ">=2.0.0 <=5.0.0", a.merge(b).toString());

	assertThrown(a = Dependency(">1.0.0 ==5.0.0"), "Construction is invalid");

	a = Dependency(">1.0.0"); b = Dependency("<2.0.0");
	assert (a.merge(b).valid(), a.merge(b).toString());
	assert (a.merge(b).versionSpec == ">1.0.0 <2.0.0", a.merge(b).toString());

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

	a = Dependency.any;
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

	logDebug("Dependency unittest success.");
}

unittest {
	assert(Dependency("~>1.0.4").versionSpec == "~>1.0.4");
	assert(Dependency("~>1.4").versionSpec == "~>1.4");
	assert(Dependency("~>2").versionSpec == "~>2");
	assert(Dependency("~>1.0.4+1.2.3").versionSpec == "~>1.0.4");
	assert(Dependency("^0.1.2").versionSpec == "^0.1.2");
	assert(Dependency("^1.2.3").versionSpec == "^1.2.3");
	assert(Dependency("^1.2").versionSpec == "~>1.2"); // equivalent; prefer ~>
}

/**
	Represents an SCM repository.
*/
struct Repository
{
	private string m_remote;

	private Kind m_kind;

	enum Kind
	{
		git,
	}

	/**
		Params:
			remote = Repository remote.
	 */
	this(string remote)
	{
		if (remote.startsWith("git+"))
		{
			m_remote = remote["git+".length .. $];
			m_kind = Kind.git;
		}
		else
		{
			throw new Exception("Unsupported repository type");
		}
	}

	string toString() nothrow pure @safe
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
	@property string remote() @nogc nothrow pure @safe
	in { assert(m_remote !is null); }
	do
	{
		return m_remote;
	}

	/**
		Returns:
			Repository type.
	*/
	@property Kind kind() @nogc nothrow pure @safe
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
@safe:
	private {
		static immutable MAX_VERS = "99999.0.0";
		static immutable UNKNOWN_VERS = "unknown";
		static immutable masterString = "~master";
		enum branchPrefix = '~';
		string m_version;
	}

	static immutable Version minRelease = Version("0.0.0");
	static immutable Version maxRelease = Version(MAX_VERS);
	static immutable Version masterBranch = Version(masterString);
	static immutable Version unknown = Version(UNKNOWN_VERS);

	/** Constructs a new `Version` from its string representation.
	*/
	this(string vers)
	{
		enforce(vers.length > 1, "Version strings must not be empty.");
		if (vers[0] != branchPrefix && !vers.isGitHash && vers.ptr !is UNKNOWN_VERS.ptr)
			enforce(vers.isValidVersion(true), "Invalid SemVer format: " ~ vers);
		m_version = vers;
	}

	/** Constructs a new `Version` from its string representation.

		This method is equivalent to calling the constructor and is used as an
		endpoint for the serialization framework.
	*/
	static Version fromString(string vers) { return Version(vers); }

	bool opEquals(const Version oth) const { return opCmp(oth) == 0; }

	/// Tests if this represents a hash instead of a version.
	@property bool isSCM() const { return m_version.isGitHash; }

	/// Tests if this represents a branch instead of a version.
	@property bool isBranch() const { return m_version.length > 0 && m_version[0] == branchPrefix; }

	/// Tests if this represents the master branch "~master".
	@property bool isMaster() const { return m_version == masterString; }

	/** Tests if this represents a pre-release version.

		Note that branches are always considered pre-release versions.
	*/
	@property bool isPreRelease() const {
		if (isBranch || isSCM) return true;
		return isPreReleaseVersion(m_version);
	}

	/// Tests if this represents the special unknown version constant.
	@property bool isUnknown() const { return m_version == UNKNOWN_VERS; }

	/** Compares two versions/branches for precedence.

		Versions generally have precedence over branches and the master branch
		has precedence over other branches. Apart from that, versions are
		compared using SemVer semantics, while branches are compared
		lexicographically.
	*/
	int opCmp(ref const Version other)
	const {
		if (isUnknown || other.isUnknown) {
			throw new Exception("Can't compare unknown versions! (this: %s, other: %s)".format(this, other));
		}

		if (isSCM || other.isSCM) {
			if (!isSCM) return -1;
			if (!other.isSCM) return 1;
			return m_version == other.m_version ? 0 : 1;
		}

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
	/// ditto
	int opCmp(const Version other) const { return opCmp(other); }

	/// Returns the string representation of the version/branch.
	string toString() const { return m_version; }
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

	a = Version.unknown;
	b = Version.minRelease;
	assertThrown(a == b, "Failed: compared " ~ a.toString() ~ " with " ~ b.toString() ~ "");

	a = Version.unknown;
	b = Version.unknown;
	assertThrown(a == b, "Failed: UNKNOWN == UNKNOWN");

	assert(Version("1.0.0+a") == Version("1.0.0+b"));

	assert(Version("73535568b79a0b124bc1653002637a830ce0fcb8").isSCM);
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
