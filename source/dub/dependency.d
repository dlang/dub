/**
	Stuff with dependencies.

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff, Sönke Ludwig
*/
module dub.dependency;

import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.url;
import dub.package_;
import dub.utils;

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
	private enum NoCheck = 0;
	private this(string vers, int noCheck){ sVersion = vers; }
	static const Version RELEASE = Version("0.0.0", NoCheck);
	static const Version HEAD = Version(to!string(MAX_VERS)~"."~to!string(MAX_VERS)~"."~to!string(MAX_VERS), NoCheck);
	static const Version INVALID = Version("", NoCheck);
	static const Version MASTER = Version(MASTER_STRING, NoCheck);
	static const string MASTER_STRING = "~master";
	static immutable char BRANCH_IDENT = '~';
	
	private { 
		static const size_t MAX_VERS = 9999;
		static const size_t MASTER_VERS = cast(size_t)(-1);
		string sVersion;
	}
	
	this(string vers)
	in {
		enforce(vers.length > 1, "Version strings must not be empty.");
		if(vers[0] == BRANCH_IDENT) {
			// branch style, ok
		}
		else {
			// Check valid SemVer style
			// 1.2.3-pre.release-version+build-meta.data.3
			//enum semVerRegEx = ctRegex!(`yadda_malloc cannot be interpreted at compile time`);
			//assert(match(vers, 
			//  `^[0-9]+\.[0-9]+\.[0-9]+\-{0,1}(?:[0-9A-Za-z-]+\.{0,1})*\+{0,1}(?:[0-9A-Za-z-]+\.{0,1})*$`));
			bool isNumericChar(char x) { return x >= '0' && x <= '9'; }
			bool isIdentChar(char x) { return isNumericChar(x) || (x >= 'a' && x <= 'z') || (x >= 'A' && x <= 'Z') || x == '-'; }
			// 1-3 (version), 4 (prebuild), 5 (build), negative: substate
			int state = 1; 
			foreach(c; vers) {
				switch(state) {
				default: enforce(false, "Messed up"); break;
				case 1: case 2: case 3: case 4: case 5:
					enforce(0
						|| (state <= 3 && isNumericChar(c))
						|| (state >= 4 && isIdentChar(c)), "State #"~to!string(state)~", Char "~c~", Version: "~vers);
					state = -state;
					break;
				case -1: case -2: case -3: case -4: case -5:
					enforce(0
						|| (state >= -2 && (c == '.' || isNumericChar(c)))
						|| (state == -3 && (c == '-' || c == '+' || isNumericChar(c)))
						|| (state == -4 && (c == '+' || c == '.' || isIdentChar(c)))
						|| (state == -5 && isIdentChar(c)), "State #"~to!string(state)~", Char "~c~", Version: "~vers);
					if(0
						|| state >= -2 && c == '.'
						|| state == -3 && c == '-'
						|| state == -4 && c == '+')
						state = -state + 1;
					if(state == -3 && c == '+')
						state = 5;
					break;
				}
			}
			enforce(state <= -3, "The version string is invalid: '" ~ vers ~ "'");
		}
	}
	body {
		sVersion = vers;
	}

	this(const Version o)
	{
		sVersion = o.sVersion;
	}
	
	bool opEquals(ref const Version oth) const { return sVersion == oth.sVersion; }
	bool opEquals(const Version oth) const { return sVersion == oth.sVersion; }
	
	/// Returns true, if this version indicates a branch, which is not the trunk.
	@property bool isBranch() const { return sVersion[0] == BRANCH_IDENT && sVersion != MASTER_STRING; }

	/** 
		Comparing Versions is generally possible, but comparing Versions 
		identifying branches other than master will fail. Only equality
		can be tested for these.
	*/
	int opCmp(ref const Version other)
	const {
		if(isBranch || other.isBranch) {
			if(sVersion == other.sVersion) return 0;
			else throw new Exception("Can't compare branch versions! (this: %s, other: %s)".format(this, other));
		}

		// Compare two SemVer versions
		string v[] = this.toComparableArray();
		string ov[] = other.toComparableArray();

		foreach( i; 0 .. min(v.length, ov.length) ) {
			if( v[i] != ov[i] ) {
				if(isNumeric(v[i]) && isNumeric(ov[i]))
					return to!int(v[i]) < to!int(ov[i])? -1 : 1;
				else 
					return v[i] < ov[i]? -1 : 1;
			}
		}
		if(v.length == 3)
			return ov.length == 3? 0 : 1;
		else if(ov.length == 3)
			return -1;
		else
			return cast(int)v.length - cast(int)ov.length;
	}
	int opCmp(in Version other) const { return opCmp(other); }
	
	string toString() const { return sVersion; }

	private string[] toComparableArray() const 
	out(result) {
		assert(result.length >= 3);
	}
	body { 
		enforce(!isBranch, "Cannot convert a branch an array representation (%s)", sVersion);

		// Master has to compare to the other regular versions, therefore a special
		// representation is returned for this case.
		if(sVersion == MASTER_STRING)
			return [ to!string(Version.MASTER_VERS), to!string(Version.MASTER_VERS), to!string(Version.MASTER_VERS) ];
		
		// Split and discard possible build metadata, this is not compared.
		string vers = split(sVersion, "+")[0];
		
		// Split prerelease data (may be empty)
		auto dashIdx = std.string.indexOf(vers, "-");
		string prerelease;
		if(dashIdx != -1) {
			prerelease = vers[dashIdx+1..$];
			vers = vers[0..dashIdx];
		}
		auto toksV = split(vers, ".");
		auto toksP = split(prerelease, ".");
		
		string v[];
		v.length = toksV.length + toksP.length;
		int i=-1;
		foreach( token; toksV ) v[++i] = token;
		foreach( token; toksP ) v[++i] = token;
		
		return v;
	}
}

unittest {
	Version a, b;

	assertNotThrown(a = Version("1.0.0"), "Constructing Version('1.0.0') failed");
	assert(!a.isBranch, "Error: '1.0.0' treated as branch");
	string[] arrRepr = [ "1", "0", "0" ];
	assert(a.toComparableArray() == arrRepr, "Array representation of '1.0.0' is wrong.");
	assert(a == a, "a == a failed");

	assertNotThrown(a = Version(Version.MASTER_STRING), "Constructing Version("~Version.MASTER_STRING~"') failed");
	assert(!a.isBranch, "Error: '"~Version.MASTER_STRING~"' treated as branch");
	arrRepr = [ to!string(Version.MASTER_VERS), to!string(Version.MASTER_VERS), to!string(Version.MASTER_VERS) ];
	assert(a.toComparableArray() == arrRepr, "'"~Version.MASTER_STRING~"' has a array representation.");
	assert(a == Version.MASTER, "Constructed master version != default master version.");

	assertNotThrown(a = Version("~BRANCH"), "Construction of branch Version failed.");
	assert(a.isBranch, "Error: '~BRANCH' not treated as branch'");
	assertThrown(a.toComparableArray(), "Error: Converting branch version to array succeded.");
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
	arrRepr = [ "2","0","0","rc","2" ];
	assert(a.toComparableArray() == arrRepr, "Array representation of 2.0.0-rc.2 is wrong.");
	assert(a < b, "Failed: 2.0.0-rc.2 < 2.0.0-rc.3");
	
	a = Version("2.0.0-rc.2+build-metadata");
	arrRepr = [ "2","0","0","rc","2" ];
	assert(a.toComparableArray() == arrRepr, "Array representation of 2.0.0-rc.2 is wrong.");
	b = Version("2.0.0+build-metadata");
	arrRepr = [ "2","0","0" ];
	assert(b.toComparableArray() == arrRepr, "Array representation of 2.0.0+build-metadata is wrong.");  
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
class Dependency {
	private {
		string m_cmpA;
		Version m_versA;
		string m_cmpB;
		Version m_versB;
		Path m_path;
		string m_configuration = "library";
		bool m_optional = false;
	}

	this( string ves ) {
		enforce( ves.length > 0);
		string orig = ves;
		if(ves[0] == Version.BRANCH_IDENT) {
			m_cmpA = ">=";
			m_cmpB = "<=";
			m_versA = m_versB = Version(ves);
		}
		else {
			m_cmpA = skipComp(ves);
			size_t idx2 = std.string.indexOf(ves, " ");
			if( idx2 == -1 ) {
				if( m_cmpA == "<=" || m_cmpA == "<" ) {
					m_versA = Version(Version.RELEASE);
					m_cmpB = m_cmpA;
					m_cmpA = ">=";
					m_versB = Version(ves);
				}
				else if( m_cmpA == ">=" || m_cmpA == ">" ) {
					m_versA = Version(ves);
					m_versB = Version(Version.HEAD);
					m_cmpB = "<=";
				}
				else {
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

				if( m_versB < m_versA ) {
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

	this(const Dependency o) {
		m_cmpA = o.m_cmpA; m_versA = Version(o.m_versA);
		m_cmpB = o.m_cmpB; m_versB = Version(o.m_versB);
		m_path = o.m_path;
		m_configuration = o.m_configuration;
		m_optional = o.m_optional;
	}

	@property void path(Path value) { m_path = value; }
	@property Path path() const { return m_path; }
	@property bool optional() const { return m_optional; }
	@property void optional(bool optional) { m_optional = optional; }

	@property Version version_() const { assert(m_versA == m_versB); return m_versA; }
	
	override string toString() const {
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

	override bool opEquals(Object b)
	{
		if (this is b) return true; if (b is null) return false; if (typeid(this) != typeid(b)) return false;
		Dependency o = cast(Dependency) b;
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
		//logTrace(" try match: %s with: %s", v, this);
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
		if(!valid())
			return new Dependency(this);
		if(!o.valid())
			return new Dependency(o);
		if( m_configuration != o.m_configuration )
			return new Dependency(">=1.0.0 <=0.0.0");
		
		Version a = m_versA > o.m_versA? m_versA : o.m_versA;
		Version b = m_versB < o.m_versB? m_versB : o.m_versB;
	
		Dependency d = new Dependency(this);
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
		//logTrace("Calling %s%s%s", a, mthd, b);
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
	Dependency a = new Dependency(">=1.1.0"), b = new Dependency(">=1.3.0");
	assert( a.merge(b).valid() && to!string(a.merge(b)) == ">=1.3.0", to!string(a.merge(b)) );
	
	a = new Dependency("<=1.0.0 >=2.0.0");
	assert( !a.valid(), to!string(a) );
	
	a = new Dependency(">=1.0.0 <=5.0.0"), b = new Dependency(">=2.0.0");
	assert( a.merge(b).valid() && to!string(a.merge(b)) == ">=2.0.0 <=5.0.0", to!string(a.merge(b)) );
	
	assertThrown(a = new Dependency(">1.0.0 ==5.0.0"), "Construction is invalid");
	
	a = new Dependency(">1.0.0"), b = new Dependency("<2.0.0");
	assert( a.merge(b).valid(), to!string(a.merge(b)));
	assert( to!string(a.merge(b)) == ">1.0.0 <2.0.0", to!string(a.merge(b)) );
	
	a = new Dependency(">2.0.0"), b = new Dependency("<1.0.0");
	assert( !(a.merge(b)).valid(), to!string(a.merge(b)));
	
	a = new Dependency(">=2.0.0"), b = new Dependency("<=1.0.0");
	assert( !(a.merge(b)).valid(), to!string(a.merge(b)));
	
	a = new Dependency("==2.0.0"), b = new Dependency("==1.0.0");
	assert( !(a.merge(b)).valid(), to!string(a.merge(b)));
	
	a = new Dependency("<=2.0.0"), b = new Dependency("==1.0.0");
	Dependency m = a.merge(b);
	assert( m.valid(), to!string(m));
	assert( m.matches( Version("1.0.0") ) );
	assert( !m.matches( Version("1.1.0") ) );
	assert( !m.matches( Version("0.0.1") ) );


	// branches / head revisions
	a = new Dependency(Version.MASTER_STRING);
	assert(a.valid());
	assert(a.matches(Version.MASTER));
	b = new Dependency(Version.MASTER_STRING);
	m = a.merge(b);
	assert(m.matches(Version.MASTER));

	//assertThrown(a = new Dependency(Version.MASTER_STRING ~ " <=1.0.0"), "Construction invalid");
	assertThrown(a = new Dependency(">=1.0.0 " ~ Version.MASTER_STRING), "Construction invalid");

	a = new Dependency(">=1.0.0");
	b = new Dependency(Version.MASTER_STRING);

	//// support crazy stuff like this?
	//m = a.merge(b);
	//assert(m.valid());
	//assert(m.matches(Version.MASTER));

	//b = new Dependency("~not_the_master");
	//m = a.merge(b);
//	assert(!m.valid());

	immutable string branch1 = Version.BRANCH_IDENT ~ "Branch1";
	immutable string branch2 = Version.BRANCH_IDENT ~ "Branch2";

	//assertThrown(a = new Dependency(branch1 ~ " " ~ branch2), "Error: '" ~ branch1 ~ " " ~ branch2 ~ "' succeeded");
	//assertThrown(a = new Dependency(Version.MASTER_STRING ~ " " ~ branch1), "Error: '" ~ Version.MASTER_STRING ~ " " ~ branch1 ~ "' succeeded");

	a = new Dependency(branch1);
	b = new Dependency(branch2);
	assertThrown(a.merge(b), "Shouldn't be able to merge to different branches");
	assertNotThrown(b = a.merge(a), "Should be able to merge the same branches. (?)");
	assert(a == b);

	a = new Dependency(branch1);
	assert(a.matches(branch1), "Dependency(branch1) does not match 'branch1'");
	assert(a.matches(Version(branch1)), "Dependency(branch1) does not match Version('branch1')");
	assert(!a.matches(Version.MASTER), "Dependency(branch1) matches Version.MASTER");
	assert(!a.matches(branch2), "Dependency(branch1) matches 'branch2'");
	assert(!a.matches(Version("1.0.0")), "Dependency(branch1) matches '1.0.0'");
	a = new Dependency(">=1.0.0");
	assert(!a.matches(Version(branch1)), "Dependency(1.0.0) matches 'branch1'");

	// Testing optional dependencies.
	a = new Dependency(">=1.0.0");
	assert(!a.optional, "Default is not optional.");
	b = new Dependency(a);
	assert(!a.merge(b).optional, "Merging two not optional dependencies wrong.");
	a.optional = true;
	assert(!a.merge(b).optional, "Merging optional with not optional wrong.");
	b.optional = true;
	assert(a.merge(b).optional, "Merging two optional dependencies wrong.");

	logTrace("Dependency Unittest sucess.");
}

struct RequestedDependency {
	this( string pkg, const Dependency de) {
		dependency = new Dependency(de);
		packages[pkg] = new Dependency(de);
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
		enforce(p.name != m_root.name);
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
		forAllDependencies( (const PkgType* avail, string s, const Dependency d, const Package issuer) {
			if(avail && d.matches(avail.vers))
				unused.remove(avail.name);
		});
		foreach(string unusedPkg, d; unused) {
			logTrace("Removed unused package: "~unusedPkg);
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
		forAllDependencies( (const PkgType* avail, string pkgId, const Dependency d, const Package issuer) {
			if(!d.optional && (!avail || !d.matches(avail.vers)))
				addDependency(deps, pkgId, d, issuer);
		});
		return deps;
	}
	
	RequestedDependency[string] needed() const {
		RequestedDependency[string] deps;
		forAllDependencies( (const PkgType* avail, string pkgId, const Dependency d, const Package issuer) {
			if(!d.optional)
				addDependency(deps, pkgId, d, issuer);
		});
		return deps;
	}

	RequestedDependency[string] optional() const {
		RequestedDependency[string] allDeps;
		forAllDependencies( (const PkgType* avail, string pkgId, const Dependency d, const Package issuer) {
			addDependency(allDeps, pkgId, d, issuer);
		});
		RequestedDependency[string] optionalDeps;
		foreach(id, req; allDeps)
			if(req.dependency.optional) optionalDeps[id] = req;
		return optionalDeps;
	}
	
	private void forAllDependencies(void delegate (const PkgType* avail, string pkgId, const Dependency d, const Package issuer) dg) const {
		foreach(string issuerPackag, issuer; m_packages) {
			foreach(string depPkg, dependency; issuer.dependencies) {
				auto availPkg = depPkg in m_packages;
				dg(availPkg, depPkg, dependency, issuer);
			}
		}
	}
	
	private static void addDependency(ref RequestedDependency[string] deps, string packageId, const Dependency d, const Package issuer) {
		logTrace("addDependency "~packageId~", '%s'", d);
		auto d2 = packageId in deps;
		if(!d2) {
			deps[packageId] = RequestedDependency(issuer.name, d);
		}
		else {
			d2.dependency = d2.dependency.merge(d);
			d2.packages[issuer.name] = new Dependency(d);
		}
	}
	
	private {
		const Package m_root;
		PkgType[string] m_packages;
	}
}

unittest {
	/*
		
	*/

}
