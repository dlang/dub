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
import dub.internal.vibecompat.inet.url;
import dub.package_;
import dub.semver;

import std.algorithm;
import std.array;
import std.exception;
import std.regex;
import std.string;
import std.typecons;
static import std.compiler;


/**
	Represents a dependency specification.

	A dependency specification either represents a specific version or version
	range, or a path to a package. In addition to that it has `optional` and
	`default_` flags to control how non-mandatory dependencies are handled. The
	package name is notably not part of the dependency specification.
*/
struct Dependency {
	private {
		// Shortcut to create >=0.0.0
		enum ANY_IDENT = "*";
		bool m_inclusiveA = true; // A comparison > (true) or >= (false)
		Version m_versA;
		bool m_inclusiveB = true; // B comparison < (true) or <= (false)
		Version m_versB;
		Path m_path;
		bool m_optional = false;
		bool m_default = false;
	}

	/// A Dependency, which matches every valid version.
	static @property any() { return Dependency(ANY_IDENT); }

	/// An invalid dependency (with no possible version matches).
	static @property invalid() { Dependency ret; ret.m_versA = Version.maxRelease; ret.m_versB = Version.minRelease; return ret; }

	deprecated("Use .any instead")
	alias ANY = any;
	deprecated("Use .invalid instead")
	alias INVALID = invalid;

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
	this(in Version ver)
	{
		m_inclusiveA = m_inclusiveB = true;
		m_versA = ver;
		m_versB = ver;
	}

	/** Constructs a new dependency specification that matches a specific
		path.
	*/
	this(Path path)
	{
		this(ANY_IDENT);
		m_path = path;
	}

	/// If set, overrides any version based dependency selection.
	@property void path(Path value) { m_path = value; }
	/// ditto
	@property Path path() const { return m_path; }

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

	/// Returns the exact version matched by the version range.
	@property Version version_() const {
		enforce(m_versA == m_versB, "Dependency "~this.versionSpec~" is no exact version.");
		return m_versA;
	}

	/// Compatibility alias
	deprecated("Use versionSpec instead.")
	alias versionString = versionSpec;

	/** Sets/gets the matching version range as a specification string.

		The acceptable forms for this string are as follows:

		$(UL
			$(LI `"1.0.0"` - a single version in SemVer format)
			$(LI `"==1.0.0"` - alternative single version notation)
			$(LI `">1.0.0"` - version range with a single bound)
			$(LI `">1.0.0 <2.0.0"` - version range with two bounds)
			$(LI `"~>1.0.0"` - a fuzzy version range)
			$(LI `"~>1.0"` - a fuzzy version range with partial version)
			$(LI `"~master"` - a branch name)
			$(LI `"*" - match any version (see also `any`))
		)

		Apart from "$(LT)" and "$(GT)", "$(GT)=" and "$(LT)=" are also valid
		comparators.

	*/
	@property void versionSpec(string ves)
	{
		enforce(ves.length > 0);
		string orig = ves;

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
			m_versB = Version(bumpVersion(ves));
		} else if (ves[0] == Version.branchPrefix) {
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
		string r;

		if (this == invalid) return "invalid";

		if (m_versA == m_versB && m_inclusiveA && m_inclusiveB) {
			// Special "==" case
			if (m_versA == Version.masterBranch) return "~master";
			else return m_versA.toString();
		}

		// "~>" case
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
				auto veb = Version(expandVersion(bumpVersion(vp)));
				if (ve == m_versA && veb == m_versB) return "~>" ~ vp;
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
	Dependency mapToPath(Path path)
	const {
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
		auto ret = versionSpec;
		if (optional) ret ~= " (optional)";
		if (!path.empty) ret ~= " @"~path.toNativeString();
		return ret;
	}

	/** Returns a JSON representation of the dependency specification.

		Simple specifications will be represented as a single specification
		string (`versionSpec`), while more complex specifications will be
		represented as a JSON object with optional "version", "path", "optional"
		and "default" fields.
	*/
	Json toJson() const {
		Json json;
		if( path.empty && !optional ){
			json = Json(this.versionSpec);
		} else {
			json = Json.emptyObject;
			json["version"] = this.versionSpec;
			if (!path.empty) json["path"] = path.toString();
			if (optional) json["optional"] = true;
			if (default_) json["default"] = true;
		}
		return json;
	}

	unittest {
		Dependency d = Dependency("==1.0.0");
		assert(d.toJson() == Json("1.0.0"), "Failed: " ~ d.toJson().toPrettyString());
		d = fromJson((fromJson(d.toJson())).toJson());
		assert(d == Dependency("1.0.0"));
		assert(d.toJson() == Json("1.0.0"), "Failed: " ~ d.toJson().toPrettyString());
	}

	/** Constructs a new `Dependency` from its JSON representation.

		See `toJson` for a description of the JSON format.
	*/
	static Dependency fromJson(Json verspec) {
		Dependency dep;
		if( verspec.type == Json.Type.object ){
			if( auto pp = "path" in verspec ) {
				if (auto pv = "version" in verspec)
					logDiagnostic("Ignoring version specification (%s) for path based dependency %s", pv.get!string, pp.get!string);

				dep = Dependency.any;
				dep.path = Path(verspec.path.get!string);
			} else {
				enforce("version" in verspec, "No version field specified!");
				auto ver = verspec["version"].get!string;
				// Using the string to be able to specifiy a range of versions.
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

	unittest {
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
		d.path = Path("path/to/package");
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
	bool opEquals(in Dependency o)
	const {
		// TODO(mdondorff): Check if not comparing the path is correct for all clients.
		return o.m_inclusiveA == m_inclusiveA && o.m_inclusiveB == m_inclusiveB
			&& o.m_versA == m_versA && o.m_versB == m_versB
			&& o.m_optional == m_optional && o.m_default == m_default;
	}

	/// ditto
	int opCmp(in Dependency o)
	const {
		if (m_inclusiveA != o.m_inclusiveA) return m_inclusiveA < o.m_inclusiveA ? -1 : 1;
		if (m_inclusiveB != o.m_inclusiveB) return m_inclusiveB < o.m_inclusiveB ? -1 : 1;
		if (m_versA != o.m_versA) return m_versA < o.m_versA ? -1 : 1;
		if (m_versB != o.m_versB) return m_versB < o.m_versB ? -1 : 1;
		if (m_optional != o.m_optional) return m_optional ? -1 : 1;
		return 0;
	}

	/// ditto
	hash_t toHash() const nothrow @trusted  {
		try {
			auto strhash = &typeid(string).getHash;
			auto str = this.toString();
			return strhash(&str);
		} catch (Exception) assert(false);
	}

	/** Determines if this dependency specification is valid.

		A specification is valid if it can match at least one version.
	*/
	bool valid() const {
		return m_versA <= m_versB && doCmp(m_inclusiveA && m_inclusiveB, m_versA, m_versB);
	}

	/** Determines if this dependency specification matches arbitrary versions.

		This is true in particular for the `any` constant.
	*/
	bool matchesAny() const {
		auto cmp = Dependency("*");
		cmp.optional = m_optional;
		cmp.default_ = m_default;
		return cmp == this;
	}

	/** Tests if the specification matches a specific version.
	*/
	bool matches(string vers) const { return matches(Version(vers)); }
	/// ditto
	bool matches(const(Version) v) const { return matches(v); }
	/// ditto
	bool matches(ref const(Version) v) const {
		if (this.matchesAny) return true;
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
		if (this.matchesAny) return o;
		if (o.matchesAny) return this;
		if (!this.valid || !o.valid) return invalid;
		if (m_versA.isBranch != o.m_versA.isBranch) return invalid;
		if (m_versB.isBranch != o.m_versB.isBranch) return invalid;
		if (m_versA.isBranch) return m_versA == o.m_versA ? this : invalid;
		if (this.path != o.path) return invalid;

		Version a = m_versA > o.m_versA ? m_versA : o.m_versA;
		Version b = m_versB < o.m_versB ? m_versB : o.m_versB;

		Dependency d = this;
		d.m_inclusiveA = !m_inclusiveA && m_versA >= o.m_versA ? false : o.m_inclusiveA;
		d.m_versA = a;
		d.m_inclusiveB = !m_inclusiveB && m_versB <= o.m_versB ? false : o.m_inclusiveB;
		d.m_versB = b;
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
			default: enforce(false, "No/Unknown comparision specified: '"~cmp~"'"); return ">=";
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
	b = Dependency(">=3.0.0 <4.0.0");
	assert(a == b, "Testing failed: " ~ a.toString());
	assert(a.matches(Version("3.1.146")), "Failed: Match 3.1.146 with ~>0.1.2");
	assert(!a.matches(Version("0.2.0")), "Failed: Match 0.2.0 with ~>0.1.2");
	a = Dependency("~>3.0.0");
	assert(a == Dependency(">=3.0.0 <3.1.0"), "Testing failed: " ~ a.toString());
	a = Dependency("~>3.5");
	assert(a == Dependency(">=3.5.0 <4.0.0"), "Testing failed: " ~ a.toString());
	a = Dependency("~>3.5.0");
	assert(a == Dependency(">=3.5.0 <3.6.0"), "Testing failed: " ~ a.toString());

	a = Dependency("~>0.1.1");
	b = Dependency("==0.1.0");
	assert(!a.merge(b).valid);
	b = Dependency("==0.1.9999");
	assert(a.merge(b).valid);
	b = Dependency("==0.2.0");
	assert(!a.merge(b).valid);

	a = Dependency("~>1.0.1-beta");
	b = Dependency(">=1.0.1-beta <1.1.0");
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

	logDebug("Dependency unittest sucess.");
}

unittest {
	assert(Dependency("~>1.0.4").versionSpec == "~>1.0.4");
	assert(Dependency("~>1.4").versionSpec == "~>1.4");
	assert(Dependency("~>2").versionSpec == "~>2");
	assert(Dependency("~>1.0.4+1.2.3").versionSpec == "~>1.0.4");
}


/**
	Represents a version in semantic version format, or a branch identifier.

	This can either have the form "~master", where "master" is a branch name,
	or the form "major.update.bugfix-prerelease+buildmetadata" (see the
	Semantic Versioning Specification v2.0.0 at http://semver.org/).
*/
struct Version {
	private {
		enum MAX_VERS = "99999.0.0";
		enum UNKNOWN_VERS = "unknown";
		enum branchPrefix = '~';
		enum masterString = "~master";
		string m_version;
	}

	static @property minRelease() { return Version("0.0.0"); }
	static @property maxRelease() { return Version(MAX_VERS); }
	static @property masterBranch() { return Version(masterString); }
	static @property unknown() { return Version(UNKNOWN_VERS); }

	deprecated("Use minRelease instead")
	static @property RELEASE() { return Version("0.0.0"); }
	deprecated("Use maxRelease instead")
	static @property HEAD() { return Version(MAX_VERS); }
	deprecated("Use masterBranch instead")
	static @property MASTER() { return Version(MASTER_STRING); }
	deprecated("Use unknown instead")
	static @property UNKNOWN() { return Version(UNKNOWN_VERS); }
	deprecated("Use masterBranch.toString() instead")
	static @property MASTER_STRING() { return masterString; }
	deprecated
	static @property BRANCH_IDENT() { return branchPrefix; }

	/** Constructs a new `Version` from its string representation.
	*/
	this(string vers)
	{
		enforce(vers.length > 1, "Version strings must not be empty.");
		if (vers[0] != branchPrefix && vers != UNKNOWN_VERS)
			enforce(vers.isValidVersion(), "Invalid SemVer format: " ~ vers);
		m_version = vers;
	}

	deprecated("Use the constructor instead.")
	static Version fromString(string vers) { return Version(vers); }

	bool opEquals(const Version oth) const {
		if (isUnknown || oth.isUnknown) {
			throw new Exception("Can't compare unknown versions! (this: %s, other: %s)".format(this, oth));
		}
		return opCmp(oth) == 0;
	}

	/// Tests if this represents a branch instead of a version.
	@property bool isBranch() const { return !m_version.empty && m_version[0] == branchPrefix; }

	/// Tests if this represents the master branch "~master".
	@property bool isMaster() const { return m_version == masterString; }

	/** Tests if this represents a pre-release version.

		Note that branches are always considered pre-release versions.
	*/
	@property bool isPreRelease() const {
		if (isBranch) return true;
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
	int opCmp(in Version other) const { return opCmp(other); }

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
}
