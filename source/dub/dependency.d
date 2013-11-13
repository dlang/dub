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
	A version in the format "major.update.bugfix-pre-release+build-metadata" or
	"~master", to identify trunk, or "~branch_name" to identify a branch. Both 
	Version types starting with "~"	refer to the head revision of the 
	corresponding branch.
	
	Except for the "~branch" Version format, this follows the Semantic Versioning
	Specification (SemVer) 2.0.0-rc.2.
*/
struct Version {
	private { 
		enum MASTER_VERS = cast(size_t)(-1);
		enum MAX_VERS = "99999.0.0";
		string m_version;
	}

	static @property RELEASE() { return Version("0.0.0"); }
	static @property HEAD() { return Version(MAX_VERS); }
	static @property INVALID() { return Version(""); }
	static @property MASTER() { return Version(MASTER_STRING); }
	static @property MASTER_STRING() { return "~master"; }
	static @property BRANCH_IDENT() { return '~'; }
	
	this(string vers)
	{
		enforce(vers.length > 1, "Version strings must not be empty.");
		enforce(vers[0] == BRANCH_IDENT || vers.isValidVersion(), "Invalid SemVer format: "~vers);
		m_version = vers;
	}

	bool opEquals(ref const Version oth) const { return m_version == oth.m_version; }
	bool opEquals(const Version oth) const { return m_version == oth.m_version; }
	
	/// Returns true, if this version indicates a branch, which is not the trunk.
	@property bool isBranch() const { return m_version[0] == BRANCH_IDENT && m_version != MASTER_STRING; }
	@property bool isMaster() const { return m_version == MASTER_STRING; }

	/** 
		Comparing Versions is generally possible, but comparing Versions 
		identifying branches other than master will fail. Only equality
		can be tested for these.
	*/
	int opCmp(ref const Version other)
	const {
		if(isBranch || other.isBranch) {
			if(m_version == other.m_version) return 0;
			else throw new Exception("Can't compare branch versions! (this: %s, other: %s)".format(this, other));
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
	assert(!a.isBranch, "Error: '"~Version.MASTER_STRING~"' treated as branch");
	assert(a == Version.MASTER, "Constructed master version != default master version.");

	assertNotThrown(a = Version("~BRANCH"), "Construction of branch Version failed.");
	assert(a.isBranch, "Error: '~BRANCH' not treated as branch'");
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
}

/// Representing a dependency, which is basically a version string and a 
/// compare methode, e.g. '>=1.0.0 <2.0.0' (i.e. a space separates the two
/// version numbers)
struct Dependency {
	private {
		string m_cmpA;
		Version m_versA;
		string m_cmpB;
		Version m_versB;
		Path m_path;
		string m_configuration = "library";
		bool m_optional = false;
	}

	this(string ves)
	{
		enforce(ves.length > 0);
		string orig = ves;
		if (ves[0] == Version.BRANCH_IDENT) {
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

	@property Version version_() const { assert(m_versA == m_versB); return m_versA; }
	
	string toString()
	const {
		string r;
		// Special "==" case
		if( m_versA == m_versB && m_cmpA == ">=" && m_cmpB == "<=" ){
			if( m_versA == Version.MASTER ) r = "~master";
			else r = "==" ~ to!string(m_versA);
		} else {
			if( m_versA != Version.RELEASE ) r = m_cmpA ~ to!string(m_versA);
			if( m_versB != Version.HEAD ) r ~= (r.length==0?"" : " ") ~ m_cmpB ~ to!string(m_versB);
			if( m_versA == Version.RELEASE && m_versB == Version.HEAD ) r = ">=0.0.0";
		}
		// TODO(mdondorff): add information to path and optionality.
		return r;
	}

	bool opEquals(in Dependency o)
	{
		// TODO(mdondorff): Check if not comparing the path is correct for all clients.
		return o.m_cmpA == m_cmpA && o.m_cmpB == m_cmpB 
			&& o.m_versA == m_versA && o.m_versB == m_versB 
			&& o.m_configuration == m_configuration
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
		if(m_versA == Version.MASTER || m_versA.isBranch) {
			enforce(m_versA == m_versB);
			return m_versA == v;
		}
		if(v.isBranch)
			return m_versA == v;
		if(m_versA == Version.MASTER || v == Version.MASTER)
			return m_versA == v;
		if( !doCmp(m_cmpA, v, m_versA) )
			return false;
		if( !doCmp(m_cmpB, v, m_versB) )
			return false;
		return true;
	}
	
	/// Merges to versions
	Dependency merge(ref const(Dependency) o) const {
		if (!valid()) return this;
		if (!o.valid()) return o;
		if (m_configuration != o.m_configuration)
			return Dependency(">=1.0.0 <=0.0.0");
		
		Version a = m_versA > o.m_versA? m_versA : o.m_versA;
		Version b = m_versB < o.m_versB? m_versB : o.m_versB;
	
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
		while( idx < c.length && !isDigit(c[idx]) ) idx++;
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

	a = Dependency(">=1.0.0");
	b = Dependency(Version.MASTER_STRING);

	//// support crazy stuff like this?
	//m = a.merge(b);
	//assert(m.valid());
	//assert(m.matches(Version.MASTER));

	//b = Dependency("~not_the_master");
	//m = a.merge(b);
//	assert(!m.valid());

	immutable string branch1 = Version.BRANCH_IDENT ~ "Branch1";
	immutable string branch2 = Version.BRANCH_IDENT ~ "Branch2";

	//assertThrown(a = Dependency(branch1 ~ " " ~ branch2), "Error: '" ~ branch1 ~ " " ~ branch2 ~ "' succeeded");
	//assertThrown(a = Dependency(Version.MASTER_STRING ~ " " ~ branch1), "Error: '" ~ Version.MASTER_STRING ~ " " ~ branch1 ~ "' succeeded");

	a = Dependency(branch1);
	b = Dependency(branch2);
	assertThrown(a.merge(b), "Shouldn't be able to merge to different branches");
	assertNotThrown(b = a.merge(a), "Should be able to merge the same branches. (?)");
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

	logDebug("Dependency Unittest sucess.");
}

struct RequestedDependency {
	this( string pkg, Dependency de) {
		dependency = de;
		packages[pkg] = de;
	}
	Dependency dependency;
	Dependency[string] packages;
}

class DependencyGraph {	
	this(const Package root) {
		m_root = root;
		m_packages[m_root.name] = root;
	}
	
	void insert(const Package p) {
		enforce(p.name != m_root.name, format("Dependency with the same name as the root package (%s) detected.", p.name));
		m_packages[p.name] = p;
	}
	
	void remove(const Package p) {
		enforce(p.name != m_root.name);
		Rebindable!(const Package)* pkg = p.name in m_packages;
		if( pkg ) m_packages.remove(p.name);
	}
	
	private
	{
		alias Rebindable!(const Package) PkgType;
	}
	
	void clearUnused() {
		Rebindable!(const Package)[string] unused = m_packages.dup;
		unused.remove(m_root.name);
		forAllDependencies( (const PkgType* avail, string s, Dependency d, const Package issuer) {
			if(avail && d.matches(avail.vers))
				unused.remove(avail.name);
		});
		foreach(string unusedPkg, d; unused) {
			logDebug("Removed unused package: "~unusedPkg);
			m_packages.remove(unusedPkg);
		}
	}
	
	RequestedDependency[string] conflicted() const {
		RequestedDependency[string] deps = needed();
		RequestedDependency[string] conflicts;
		foreach(string pkg, d; deps)
			if(!d.dependency.valid())
				conflicts[pkg] = d;
		return conflicts;
	}
	
	RequestedDependency[string] missing() const {
		RequestedDependency[string] deps;
		forAllDependencies( (const PkgType* avail, string pkgId, Dependency d, const Package issuer) {
			if(!d.optional && (!avail || !d.matches(avail.vers)))
				addDependency(deps, pkgId, d, issuer);
		});
		return deps;
	}
	
	RequestedDependency[string] needed() const {
		RequestedDependency[string] deps;
		forAllDependencies( (const PkgType* avail, string pkgId, Dependency d, const Package issuer) {
			if(!d.optional)
				addDependency(deps, pkgId, d, issuer);
		});
		return deps;
	}

	RequestedDependency[string] optional() const {
		RequestedDependency[string] allDeps;
		forAllDependencies( (const PkgType* avail, string pkgId, Dependency d, const Package issuer) {
			addDependency(allDeps, pkgId, d, issuer);
		});
		RequestedDependency[string] optionalDeps;
		foreach(id, req; allDeps)
			if(req.dependency.optional) optionalDeps[id] = req;
		return optionalDeps;
	}
	
	private void forAllDependencies(void delegate (const PkgType* avail, string pkgId, Dependency d, const Package issuer) dg) const {
		foreach(string issuerPackag, issuer; m_packages) {
			foreach(string depPkg, dependency; issuer.dependencies) {
				auto availPkg = depPkg in m_packages;
				dg(availPkg, depPkg, dependency, issuer);
			}
		}
	}
	
	private static void addDependency(ref RequestedDependency[string] deps, string packageId, Dependency d, const Package issuer) {
		auto d2 = packageId in deps;
		if(!d2) {
			deps[packageId] = RequestedDependency(issuer.name, d);
		}
		else {
			d2.dependency = d2.dependency.merge(d);
			d2.packages[issuer.name] = d;
		}
	}
	
	private {
		const Package m_root;
		PkgType[string] m_packages;
	}

	unittest {
		/*
			R (master) -> A (master)
		*/
		auto R_json = parseJsonString(`
		{
			"name": "R",
			"dependencies": {
				"A": "~master",
				"B": "1.0.0"
			},
			"version": "~master"
		}
			`);
		Package r_master = new Package(R_json);
		auto graph = new DependencyGraph(r_master);

		assert(graph.conflicted.length == 0, "There are conflicting packages");

		void expectA(RequestedDependency[string] requested, string name) {
			assert("A" in requested, "Package A is not the "~name~" package");
			assert(requested["A"].dependency == Dependency("~master"), "Package A is not "~name~" as ~master version.");
			assert("R" in requested["A"].packages, "Package R is not the issuer of "~name~" Package A(~master).");
			assert(requested["A"].packages["R"] == Dependency("~master"), "Package R is not the issuer of "~name~" Package A(~master).");
		}
		void expectB(RequestedDependency[string] requested, string name) {
			assert("B" in requested, "Package B is not the "~name~" package");
			assert(requested["B"].dependency == Dependency("1.0.0"), "Package B is not "~name~" as 1.0.0 version.");
			assert("R" in requested["B"].packages, "Package R is not the issuer of "~name~" Package B(1.0.0).");
			assert(requested["B"].packages["R"] == Dependency("1.0.0"), "Package R is not the issuer of "~name~" Package B(1.0.0).");
		}
		auto missing = graph.missing();
		assert(missing.length == 2, "Invalid count of missing items");
		expectA(missing, "missing");
		expectB(missing, "missing");

		auto needed = graph.needed();
		assert(needed.length == 2, "Invalid count of needed packages.");		
		expectA(needed, "needed");
		expectB(needed, "needed");

		assert(graph.optional.length == 0, "There are optional packages reported");

		auto A_json = parseJsonString(`
		{
			"name": "A",
			"dependencies": {
			},
			"version": "~master"
		}
			`);
		Package a_master = new Package(A_json);
		graph.insert(a_master);

		assert(graph.conflicted.length == 0, "There are conflicting packages");

		auto missing2 = graph.missing;
		assert(missing2.length == 1, "Missing list does not contain an package.");
		expectB(missing2, "missing2");

		needed = graph.needed;
		assert(needed.length == 2, "Invalid count of needed packages.");		
		expectA(needed, "needed");
		expectB(needed, "needed");

		assert(graph.optional.length == 0, "There are optional packages reported");
	}

	unittest {
		/*
			R -> R:sub
		*/
		auto R_json = parseJsonString(`
		{
			"name": "R",
			"dependencies": {
				"R:sub": "~master"
			},
			"version": "~master",
			"subPackages": [
				{
					"name": "sub"
				}
			]
		}
			`);

		Package r_master = new Package(R_json);
		auto graph = new DependencyGraph(r_master);
		assert(graph.missing().length == 1);
		foreach (sp; r_master.subPackages) graph.insert(sp);
		assert(graph.missing().length == 0);
	}
}