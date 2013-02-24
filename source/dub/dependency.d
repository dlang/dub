/**
	Stuff with dependencies.

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff, Sönke Ludwig
*/
module dub.dependency;

import dub.utils;
import dub.package_;

import vibecompat.core.log;
import vibecompat.core.file;
import vibecompat.data.json;
import vibecompat.inet.url;

import std.array;
import std.string;
import std.exception;
import std.algorithm;
import std.typecons;
import std.conv;
static import std.compiler;


/**
	A version in the format "major.update.bugfix" or "~master", to identify trunk,
	or "~branch_name" to identify a branch. Both Version types starting with "~"
	refer to the head revision of the corresponding branch.
*/
struct Version {
	static const Version RELEASE = Version("0.0.0");
	static const Version HEAD = Version(to!string(MAX_VERS)~"."~to!string(MAX_VERS)~"."~to!string(MAX_VERS));
	static const Version INVALID = Version();
	static const Version MASTER = Version(MASTER_STRING);
	static const string MASTER_STRING = "~master";
	static immutable char BRANCH_IDENT = '~';
	
	private { 
		static const size_t MAX_VERS = 9999;
		static const size_t MASTER_VERS = cast(size_t)(-1);
		string sVersion;
	}
	
	this(string vers)
	{
		enforce(vers.length > 1);
		enforce(vers[0] == BRANCH_IDENT || count(vers, ".") == 2);
		sVersion = vers;
		/*
		if(vers == MASTER_STRING) {
			v = [MASTER_VERS, MASTER_VERS, MASTER_VERS];
		} else {
			auto toks = split(vers, ".");
			v.length = toks.length;
			foreach( i, t; toks ) v[i] = t.to!size_t();
		}
		*/
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
		identifying branches other than master will fail.
	*/
	int opCmp(ref const Version other)
	const {
		if(isBranch || other.isBranch) 
			throw new Exception("Can't compare branch versions! (this: %s, other: %s)".format(this, other));

		size_t v[] = toArray();
		size_t ov[] = other.toArray();

		foreach( i; 0 .. min(v.length, ov.length) )
			if( v[i] != ov[i] )
				return cast(int)v[i] - cast(int)ov[i];
		return cast(int)v.length - cast(int)ov.length;
	}
	int opCmp(in Version other) const { return opCmp(other); }
	
	string toString() const { return sVersion; }

	private size_t[] toArray() const { 
		enforce(!isBranch, "Cannot convert a branch an array representation (%s)", sVersion);

		size_t v[];
		if(sVersion == MASTER_STRING) {
			v = [MASTER_VERS, MASTER_VERS, MASTER_VERS];
		} else {
			auto toks = split(sVersion, ".");
			v.length = toks.length;
			foreach( i, t; toks ) v[i] = t.to!size_t();
		}
		return v;
	}
}

unittest {
	Version a, b;

	try a = Version("1.0.0");
	catch assert(false, "Constructing Version('1.0.0') failed");
	assert(!a.isBranch, "Error: '1.0.0' treated as branch");
	size_t[] arrRepr = [ 1, 0, 0 ];
	assert(a.toArray == arrRepr, "Array representation of '1.0.0' is wrong.");
	assert(a == a, "a == a failed");

	try a = Version(Version.MASTER_STRING);
	catch assert(false, "Constructing Version("~Version.MASTER_STRING~"') failed");
	assert(!a.isBranch, "Error: '"~Version.MASTER_STRING~"' treated as branch");
	arrRepr = [ Version.MASTER_VERS, Version.MASTER_VERS, Version.MASTER_VERS ];
	assert(a.toArray == arrRepr, "Array representation of '"~Version.MASTER_STRING~"' is wrong.");
	assert(a == Version.MASTER, "Constructed master version != default master version.");

	try a = Version("~BRANCH");
	catch assert(false, "Construction of branch Version failed.");
	assert(a.isBranch, "Error: '~BRANCH' not treated as branch'");
	try {
		a.toArray();
		assert(false, "Error: Converting branch version to array succeded.");
	}
	catch { /* exception expected */ }
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

	this(string cmp, string ver)
	{
		m_cmpA = cmp;
		m_versB = m_versA = Version(ver);
		m_cmpB = "==";
	}
	
	this(const Dependency o) {
		m_cmpA = o.m_cmpA; m_versA = Version(o.m_versA);
		m_cmpB = o.m_cmpB; m_versB = Version(o.m_versB);
		enforce( m_cmpA != "==" || m_cmpB == "==");
		enforce(m_versA <= m_versB);
	}
	
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
		return r;
	}

	override bool opEquals(Object b)
	{
		if (this is b) return true; if (b is null) return false; if (typeid(this) != typeid(b)) return false;
		Dependency o = cast(Dependency) b;
		return o.m_cmpA == m_cmpA && o.m_cmpB == m_cmpB && o.m_versA == m_versA && o.m_versB == m_versB;
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
		
/// TODO: continue porting Version / Dependency to use branches and string

		Version a = m_versA > o.m_versA? m_versA : o.m_versA;
		Version b = m_versB < o.m_versB? m_versB : o.m_versB;
		
		//logTrace(" this : %s", this);
		//logTrace(" other: %s", o);
	
		Dependency d = new Dependency(this);
		d.m_cmpA = !doCmp(m_cmpA, a,a)? m_cmpA : o.m_cmpA;
		d.m_versA = a;
		d.m_cmpB = !doCmp(m_cmpB, b,b)? m_cmpB : o.m_cmpB;
		d.m_versB = b;
		
		//logTrace(" merged: %s", d);
		
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
	
	try {
		a = new Dependency(">1.0.0 ==5.0.0");
		assert( false, "Construction is invalid");
	} catch( Exception ) {}
	
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

	try {
		a = new Dependency(Version.MASTER_STRING ~ " <=1.0.0");
		assert(false, "Construction invalid");
	} catch { /*expected*/ }

	try {
		a = new Dependency(">=1.0.0 " ~ Version.MASTER_STRING);
		assert(false, "Construction invalid");
	} catch { /*expected*/ }

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

	try { 
		a = new Dependency(branch1 ~ " " ~ branch2);
		assert(false, "Error: '" ~ branch1 ~ " " ~ branch2 ~ "' succeeded");
	} catch { /*expected*/ }
	try { 
		a = new Dependency(Version.MASTER_STRING ~ " " ~ branch1);
		assert(false, "Error: '" ~ Version.MASTER_STRING ~ " " ~ branch1 ~ "' succeeded");
	} catch { /*expected*/ }

	a = new Dependency(branch1);
	b = new Dependency(branch2);
	try {
		a.merge(b);
		assert(false, "Shouldn't be able to merge to different branches");
	} catch { /*expected*/ }
	try {
		b = a.merge(a);
		assert(a == b);
	}
	catch assert(false, "Should be able to merge the same branches. (?)");


	a = new Dependency(branch1);
	assert(a.matches(branch1), "Dependency(branch1) does not match 'branch1'");
	assert(a.matches(Version(branch1)), "Dependency(branch1) does not match Version('branch1')");
	assert(!a.matches(Version.MASTER), "Dependency(branch1) matches Version.MASTER");
	assert(!a.matches(branch2), "Dependency(branch1) matches 'branch2'");
	assert(!a.matches(Version("1.0.0")), "Dependency(branch1) matches '1.0.0'");
	a = new Dependency(">=1.0.0");
	assert(!a.matches(Version(branch1)), "Dependency(1.0.0) matches 'branch1'");

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
			if(!avail || !d.matches(avail.vers))
				addDependency(deps, pkgId, d, issuer);
		});
		return deps;
	}
	
	RequestedDependency[string] needed() const {
		RequestedDependency[string] deps;
		forAllDependencies( (const PkgType* avail, string pkgId, const Dependency d, const Package issuer) {
			addDependency(deps, pkgId, d, issuer);
		});
		return deps;
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
