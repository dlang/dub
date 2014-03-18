/**
	Stuff with dependencies.

	Copyright: © 2012-2013 Matthias Dondorff
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
import std.conv;
import std.exception;
import std.regex;
import std.string;
import std.typecons;
static import std.compiler;

/**
	A version in the format "major.update.bugfix-prerelease+buildmetadata"
	according to Semantic Versioning Specification v2.0.0.

	(deprecated):
	This also supports a format like "~master", to identify trunk, or
	"~branch_name" to identify a branch. Both Version types starting with "~"
	refer to the head revision of the corresponding branch.
	This is subject to be removed soon.
*/
struct Version {
	private { 
		enum MAX_VERS = "99999.0.0";
		enum UNKNOWN_VERS = "unknown";
		string m_version;
	}

	static @property RELEASE() { return Version("0.0.0"); }
	static @property HEAD() { return Version(MAX_VERS); }
	static @property MASTER() { return Version(MASTER_STRING); }
	static @property UNKNOWN() { return Version(UNKNOWN_VERS); }
	static @property MASTER_STRING() { return "~master"; }
	static @property BRANCH_IDENT() { return '~'; }
	
	this(string vers)
	{
		enforce(vers.length > 1, "Version strings must not be empty.");
		if (vers[0] != BRANCH_IDENT && vers != UNKNOWN_VERS)
			enforce(vers.isValidVersion(), "Invalid SemVer format: " ~ vers);
		m_version = vers;
	}

	bool opEquals(const Version oth) const {
		if (isUnknown || oth.isUnknown) {
			throw new Exception("Can't compare unknown versions! (this: %s, other: %s)".format(this, oth));
		}
		return m_version == oth.m_version; 
	}
	
	/// Returns true, if this version indicates a branch, which is not the trunk.
	@property bool isBranch() const { return !m_version.empty && m_version[0] == BRANCH_IDENT; }
	@property bool isMaster() const { return m_version == MASTER_STRING; }
	@property bool isPreRelease() const {
		if (isBranch) return true;
		return isPreReleaseVersion(m_version);
	}
	@property bool isUnknown() const { return m_version == UNKNOWN_VERS; }

	/** 
		Comparing Versions is generally possible, but comparing Versions 
		identifying branches other than master will fail. Only equality
		can be tested for these.
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

		return compareVersions(isMaster ? MAX_VERS : m_version, other.isMaster ? MAX_VERS : other.m_version);
	}
	int opCmp(in Version other) const { return opCmp(other); }
	
	string toString() const { return m_version; }
}

unittest {
	Version a, b;

	assertNotThrown(a = Version("1.0.0"), "Constructing Version('1.0.0') failed");
	assert(!a.isBranch, "Error: '1.0.0' treated as branch");
	assert(a == a, "a == a failed");

	assertNotThrown(a = Version(Version.MASTER_STRING), "Constructing Version("~Version.MASTER_STRING~"') failed");
	assert(a.isBranch, "Error: '"~Version.MASTER_STRING~"' treated as branch");
	assert(a.isMaster);
	assert(a == Version.MASTER, "Constructed master version != default master version.");

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
	a = Version(Version.MASTER_STRING);
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
	assert(a < b, "Failed: "~to!string(a)~"<"~to!string(b));
	
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
			assert(versions[j] < versions[i], "Failed: " ~ to!string(versions[j]) ~ "<" ~ to!string(versions[i]));

	a = Version.UNKNOWN;
	b = Version.RELEASE;
	assertThrown(a == b, "Failed: compared " ~ to!string(a) ~ " with " ~ to!string(b) ~ "");

	a = Version.UNKNOWN;
	b = Version.UNKNOWN;
	assertThrown(a == b, "Failed: UNKNOWN == UNKNOWN");
}

/**
	Representing a dependency, which is basically a version string and a 
	compare methode, e.g. '>=1.0.0 <2.0.0' (i.e. a space separates the two
	version numbers)
*/
struct Dependency {
	private {
		// Shortcut to create >=0.0.0
		enum ANY_IDENT = "*";
		string m_cmpA;
		Version m_versA;
		string m_cmpB;
		Version m_versB;
		Path m_path;
		bool m_optional = false;
	}

	// A Dependency, which matches every valid version.
	static @property ANY() { return Dependency(ANY_IDENT); }
	static @property INVALID() { Dependency ret; ret.m_versA = Version.HEAD; ret.m_versB = Version.RELEASE; return ret; }

	this(string ves)
	{
		enforce(ves.length > 0);
		string orig = ves;

		if (ves == ANY_IDENT) {
			// Any version is good.
			ves = ">=0.0.0";
		}

		if (ves[0] == Version.BRANCH_IDENT && ves[1] == '>') {
			// Shortcut: "~>x.y.z" variant. Last non-zero number will indicate
			// the base for this so something like this: ">=x.y.z <x.(y+1).z"
			m_cmpA = ">=";
			m_cmpB = "<";
			ves = ves[2..$];
			m_versA = Version(expandVersion(ves));
			m_versB = Version(bumpVersion(ves));
		} else if (ves[0] == Version.BRANCH_IDENT) {
			m_cmpA = ">=";
			m_cmpB = "<=";
			m_versA = m_versB = Version(ves);
		} else if (std.string.indexOf("><=", ves[0]) == -1) {
			m_cmpA = ">=";
			m_cmpB = "<=";
			m_versA = m_versB = Version(ves);
		} else {
			m_cmpA = skipComp(ves);
			size_t idx2 = std.string.indexOf(ves, " ");
			if (idx2 == -1) {
				if (m_cmpA == "<=" || m_cmpA == "<") {
					m_versA = Version.RELEASE;
					m_cmpB = m_cmpA;
					m_cmpA = ">=";
					m_versB = Version(ves);
				} else if (m_cmpA == ">=" || m_cmpA == ">") {
					m_versA = Version(ves);
					m_versB = Version.HEAD;
					m_cmpB = "<=";
				} else {
					// Converts "==" to ">=a&&<=a", which makes merging easier
					m_versA = m_versB = Version(ves);
					m_cmpA = ">=";
					m_cmpB = "<=";
				}
			} else {
				assert(ves[idx2] == ' ');
				m_versA = Version(ves[0..idx2]);
				string v2 = ves[idx2+1..$];
				m_cmpB = skipComp(v2);
				m_versB = Version(v2);

				enforce(!m_versA.isBranch, "Partly a branch (A): %s", ves);
				enforce(!m_versB.isBranch, "Partly a branch (B): %s", ves);

				if (m_versB < m_versA) {
					swap(m_versA, m_versB);
					swap(m_cmpA, m_cmpB);
				}
				enforce( m_cmpA != "==" && m_cmpB != "==", "For equality, please specify a single version.");
			}
		}
	}

	this(in Version ver)
	{
		m_cmpA = ">=";
		m_cmpB = "<=";
		m_versA = ver;
		m_versB = ver;
	}

	@property void path(Path value) { m_path = value; }
	@property Path path() const { return m_path; }
	@property bool optional() const { return m_optional; }
	@property void optional(bool optional) { m_optional = optional; }

	@property Version version_() const {
		enforce(m_versA == m_versB, "Dependency "~toString()~" is no exact version."); 
		return m_versA; 
	}
	
	string toString()
	const {
		return versionString();
		// TODO(mdondorff): add information to path and optionality.
		//   This is not directly possible, as this toString method is used for
		//   writing to the dub.json files.
		// if (m_path) r ~= "(path: " ~ m_path.toString() ~ ")";
		// if (m_optional) r ~= ", optional";
	}

	private string versionString() const {
		string r;
	
		if( m_versA == m_versB && m_cmpA == ">=" && m_cmpB == "<=" ){
			// Special "==" case
			if (m_versA == Version.MASTER ) r = "~master";
			else r = to!string(m_versA);
		} else {
			if( m_versA != Version.RELEASE ) r = m_cmpA ~ to!string(m_versA);
			if( m_versB != Version.HEAD ) r ~= (r.length==0?"" : " ") ~ m_cmpB ~ to!string(m_versB);
			if( m_versA == Version.RELEASE && m_versB == Version.HEAD ) r = ">=0.0.0";
		}
		return r;
	}

	Json toJson() const {
		Json json;
		if( path.empty && !optional ){
			json = Json(versionString());
		} else {
			json = Json.emptyObject;
			json["version"] = versionString();
			if (!path.empty) json["path"] = path.toString();
			if (optional) json["optional"] = true;
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

	static Dependency fromJson(Json verspec) {
		Dependency dep;
		if( verspec.type == Json.Type.object ){
			enforce("version" in verspec, "No version field specified!");
			auto ver = verspec["version"].get!string;
			if( auto pp = "path" in verspec ) {
				// This enforces the "version" specifier to be a simple version, 
				// without additional range specifiers.
				dep = Dependency(Version(ver));
				dep.path = Path(verspec.path.get!string());
			} else {
				// Using the string to be able to specifiy a range of versions.
				dep = Dependency(ver);
			}
			if( auto po = "optional" in verspec ) {
				dep.optional = verspec.optional.get!bool();
			}
		} else {
			// canonical "package-id": "version"
			dep = Dependency(verspec.get!string());
		}
		return dep;
	}

	unittest {
		assert(fromJson(parseJsonString("\">=1.0.0 <2.0.0\"")) == Dependency(">=1.0.0 <2.0.0"));
		Dependency parsed = fromJson(parseJsonString(`
		{
			"version": "2.0.0",
			"optional": true,
			"path": "path/to/package"
		}
			`));
		Dependency d = Dependency(Version("2.0.0"));
		d.optional = true;
		d.path = Path("path/to/package");
		assert(d == parsed);
		// optional and path not checked by opEquals.
		assert(d.optional == parsed.optional);
		assert(d.path == parsed.path);
	}

	bool opEquals(in Dependency o)
	const {
		// TODO(mdondorff): Check if not comparing the path is correct for all clients.
		return o.m_cmpA == m_cmpA && o.m_cmpB == m_cmpB 
			&& o.m_versA == m_versA && o.m_versB == m_versB 
			&& o.m_optional == m_optional;
	}
	
	bool valid() const {
		return m_versA == m_versB // compare not important
			|| (m_versA < m_versB && doCmp(m_cmpA, m_versB, m_versA) && doCmp(m_cmpB, m_versA, m_versB));
	}
	
	bool matches(string vers) const { return matches(Version(vers)); }
	bool matches(const(Version) v) const { return matches(v); }
	bool matches(ref const(Version) v) const {
		//logDebug(" try match: %s with: %s", v, this);
		// Master only matches master
		if(m_versA.isBranch) {
			enforce(m_versA == m_versB);
			return m_versA == v;
		}
		if(v.isBranch || m_versA.isBranch)
			return m_versA == v;
		if( !doCmp(m_cmpA, v, m_versA) )
			return false;
		if( !doCmp(m_cmpB, v, m_versB) )
			return false;
		return true;
	}
	
	/// Merges to versions
	Dependency merge(ref const(Dependency) o)
	const {
		if (!this.valid || !o.valid) return INVALID;
		if (m_versA.isBranch != o.m_versA.isBranch) return INVALID;
		if (m_versB.isBranch != o.m_versB.isBranch) return INVALID;
		if (m_versA.isBranch) return m_versA == o.m_versA ? this : INVALID;

		Version a = m_versA > o.m_versA ? m_versA : o.m_versA;
		Version b = m_versB < o.m_versB ? m_versB : o.m_versB;
	
		Dependency d = this;
		d.m_cmpA = !doCmp(m_cmpA, a,a)? m_cmpA : o.m_cmpA;
		d.m_versA = a;
		d.m_cmpB = !doCmp(m_cmpB, b,b)? m_cmpB : o.m_cmpB;
		d.m_versB = b;
		d.m_optional = m_optional && o.m_optional;
		
		return d;
	}
	
	private static bool isDigit(char ch) { return ch >= '0' && ch <= '9'; }
	private static string skipComp(ref string c) {
		size_t idx = 0;
		while (idx < c.length && !isDigit(c[idx]) && c[idx] != Version.BRANCH_IDENT) idx++;
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
	
	private static bool doCmp(string mthd, ref const Version a, ref const Version b) {
		//logDebug("Calling %s%s%s", a, mthd, b);
		switch(mthd) {
			default: throw new Exception("Unknown comparison operator: "~mthd);
			case ">": return a>b;
			case ">=": return a>=b;
			case "==": return a==b;
			case "<=": return a<=b;
			case "<": return a<b;
		}
	}
}

unittest {
	Dependency a = Dependency(">=1.1.0"), b = Dependency(">=1.3.0");
	assert( a.merge(b).valid() && to!string(a.merge(b)) == ">=1.3.0", to!string(a.merge(b)) );
	
	a = Dependency("<=1.0.0 >=2.0.0");
	assert( !a.valid(), to!string(a) );
	
	a = Dependency(">=1.0.0 <=5.0.0"), b = Dependency(">=2.0.0");
	assert( a.merge(b).valid() && to!string(a.merge(b)) == ">=2.0.0 <=5.0.0", to!string(a.merge(b)) );
	
	assertThrown(a = Dependency(">1.0.0 ==5.0.0"), "Construction is invalid");
	
	a = Dependency(">1.0.0"), b = Dependency("<2.0.0");
	assert( a.merge(b).valid(), to!string(a.merge(b)));
	assert( to!string(a.merge(b)) == ">1.0.0 <2.0.0", to!string(a.merge(b)) );
	
	a = Dependency(">2.0.0"), b = Dependency("<1.0.0");
	assert( !(a.merge(b)).valid(), to!string(a.merge(b)));
	
	a = Dependency(">=2.0.0"), b = Dependency("<=1.0.0");
	assert( !(a.merge(b)).valid(), to!string(a.merge(b)));
	
	a = Dependency("==2.0.0"), b = Dependency("==1.0.0");
	assert( !(a.merge(b)).valid(), to!string(a.merge(b)));

	a = Dependency("1.0.0"), b = Dependency("==1.0.0");
	assert(a == b);
	
	a = Dependency("<=2.0.0"), b = Dependency("==1.0.0");
	Dependency m = a.merge(b);
	assert( m.valid(), to!string(m));
	assert( m.matches( Version("1.0.0") ) );
	assert( !m.matches( Version("1.1.0") ) );
	assert( !m.matches( Version("0.0.1") ) );


	// branches / head revisions
	a = Dependency(Version.MASTER_STRING);
	assert(a.valid());
	assert(a.matches(Version.MASTER));
	b = Dependency(Version.MASTER_STRING);
	m = a.merge(b);
	assert(m.matches(Version.MASTER));

	//assertThrown(a = Dependency(Version.MASTER_STRING ~ " <=1.0.0"), "Construction invalid");
	assertThrown(a = Dependency(">=1.0.0 " ~ Version.MASTER_STRING), "Construction invalid");

	immutable string branch1 = Version.BRANCH_IDENT ~ "Branch1";
	immutable string branch2 = Version.BRANCH_IDENT ~ "Branch2";

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
	assert(!a.matches(Version.MASTER), "Dependency(branch1) matches Version.MASTER");
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
	assert(a == b, "Testing failed: " ~ a.to!string());
	assert(a.matches(Version("3.1.146")), "Failed: Match 3.1.146 with ~>0.1.2");
	assert(!a.matches(Version("0.2.0")), "Failed: Match 0.2.0 with ~>0.1.2");
	a = Dependency("~>3.0.0");
	assert(a == Dependency(">=3.0.0 <3.1.0"), "Testing failed: " ~ a.to!string());
	a = Dependency("~>3.5");
	assert(a == Dependency(">=3.5.0 <4.0.0"), "Testing failed: " ~ a.to!string());
	a = Dependency("~>3.5.0");
	assert(a == Dependency(">=3.5.0 <3.6.0"), "Testing failed: " ~ a.to!string());

	a = Dependency("~>1.0.1-beta");
	b = Dependency(">=1.0.1-beta <1.1.0");
	assert(a == b, "Testing failed: " ~ a.to!string());
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

	a = Dependency.ANY;
	assert(!a.optional);
	assert(a.valid);
	assertThrown(a.version_);
	b = Dependency(">=1.0.1");
	assert(b == a.merge(b));
	assert(b == b.merge(a));

	logDebug("Dependency Unittest sucess.");
}


class DependencyResolver(CONFIGS, CONFIG) {
	static struct TreeNodes {
		string pack;
		CONFIGS configs;
	}

	static struct TreeNode {
		string pack;
		CONFIG config;
	}

	static struct ChildIterationState {
		TreeNode[] configs;
		size_t configIndex;
	}

	static struct GraphIterationState {
		CONFIG[string] visited;
		TreeNode[] stack;
		TreeNode node;
		ChildIterationState[] children;
	}

	CONFIG[string] resolve(TreeNode root)
	{
		static string rootPackage(string p) {
			auto idx = std.string.indexOf(p, ":");
			if (idx < 0) return p;
			return p[0 .. idx];
		}

		size_t[string] package_indices;
		CONFIG[][] all_configs;
		void findConfigsRec(TreeNode parent)
		{
			foreach (ch; getChildren(parent)) {
				auto basepack = rootPackage(ch.pack);
				if (basepack in package_indices) continue;

				auto pidx = all_configs.length;
				auto configs = getAllConfigs(basepack);
				enforce(configs.length > 0, format("Found no configurations for package %s.", basepack));
				all_configs ~= configs;
				package_indices[basepack] = pidx;

				foreach (v; all_configs[pidx])
					findConfigsRec(TreeNode(ch.pack, v));
			}
		}
		findConfigsRec(root);

		auto config_indices = new size_t[all_configs.length];
		config_indices[] = 0;

		bool[TreeNode] visited;
		bool validateConfigs(TreeNode parent)
		{
			if (parent in visited) return true;
			visited[parent] = true;
			foreach (ch; getChildren(parent)) {
				auto basepack = rootPackage(ch.pack);
				assert(basepack in package_indices, format("%s not in packages %s", basepack, package_indices));
				auto pidx = package_indices[basepack];
				auto config = all_configs[pidx][config_indices[pidx]];
				auto chnode = TreeNode(ch.pack, config);
				if (!matches(ch.configs, config) || !validateConfigs(chnode))
					return false;
			}
			return true;
		}

		while (true) {
			// check if the current combination of configurations works out
			visited = null;
			if (validateConfigs(root)) {
				CONFIG[string] ret;
				foreach (p, i; package_indices)
					ret[p] = all_configs[i][config_indices[i]];
				return ret;
			}

			// find the next combination of configurations
			foreach_reverse (pi, ref i; config_indices) {
				if (++i >= all_configs[pi].length) i = 0;
				else break;
			}
			enforce(config_indices.any!"a!=0", "Could not find a valid dependency tree configuration.");
		}
	}

	protected abstract CONFIG[] getAllConfigs(string pack);
	protected abstract TreeNodes[] getChildren(TreeNode node);
	protected abstract bool matches(CONFIGS configs, CONFIG config);
}

unittest {
	static class TestResolver : DependencyResolver!(uint[], uint) {
		private TreeNodes[][string] m_children;
		this(TreeNodes[][string] children) { m_children = children; }
		protected override uint[] getAllConfigs(string pack) {
			auto ret = appender!(uint[]);
			foreach (p; m_children.byKey) {
				if (p.length <= pack.length+1) continue;
				if (p[0 .. pack.length] != pack || p[pack.length] != ':') continue;
				auto didx = p.lastIndexOf(':');
				ret ~= p[didx+1 .. $].to!uint;
			}
			ret.data.sort!"a>b"();
			return ret.data;
		}
		protected override TreeNodes[] getChildren(TreeNode node) { return m_children.get(node.pack ~ ":" ~ node.config.to!string(), null); }
		protected override bool matches(uint[] configs, uint config) { return configs.canFind(config); }
	}

	// properly back up if conflicts are detected along the way (d:2 vs d:1)
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes("b", [2, 1]), TreeNodes("d", [1]), TreeNodes("e", [2, 1])],
			"b:1": [TreeNodes("c", [2, 1]), TreeNodes("d", [1])],
			"b:2": [TreeNodes("c", [3, 2]), TreeNodes("d", [2, 1])],
			"c:1": [], "c:2": [], "c:3": [],
			"d:1": [], "d:2": [],
			"e:1": [], "e:2": [],
		]);
		assert(res.resolve(TreeNode("a", 0)) == ["b":2u, "c":3u, "d":1u, "e":2u]);
	}

	// handle cyclic dependencies gracefully
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes("b", [1])],
			"b:1": [TreeNodes("b", [1])]
		]);
		assert(res.resolve(TreeNode("a", 0)) == ["b":1u]);
	}
}
