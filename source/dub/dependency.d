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

// todo: cleanup imports
import std.array;
import std.exception;
import std.algorithm;
import std.zip;
import std.typecons;
import std.conv;
static import std.compiler;


/**
	A version in the format "major.update.bugfix".
*/
struct Version {
	static const Version RELEASE = Version("0.0.0");
	static const Version HEAD = Version(to!string(MAX_VERS)~"."~to!string(MAX_VERS)~"."~to!string(MAX_VERS));
	static const Version INVALID = Version();
	static const Version MASTER = Version(MASTER_STRING);
	static const string MASTER_STRING = "~master";
	
	private { 
		static const size_t MAX_VERS = 9999;
		static const size_t MASTER_VERS = cast(size_t)(-1);
		size_t[] v; 
	}
	
	this(string vers)
	{
		enforce(vers == MASTER_STRING || count(vers, ".") == 2);
		if(vers == MASTER_STRING) {
			v = [MASTER_VERS, MASTER_VERS, MASTER_VERS];
		} else {
			auto toks = split(vers, ".");
			v.length = toks.length;
			foreach( i, t; toks ) v[i] = t.to!size_t();
		}
	}
	
	this(const Version o)
	{
		foreach(size_t vers; o.v)
			v ~= vers;
	}
	
	bool opEquals(ref const Version oth) const { return v == oth.v; }
	bool opEquals(const Version oth) const { return v == oth.v; }
	
	int opCmp(ref const Version other)
	const {
		foreach( i; 0 .. min(v.length, other.v.length) )
			if( v[i] != other.v[i] )
				return cast(int)v[i] - cast(int)other.v[i];
		return cast(int)v.length - cast(int)other.v.length;
	}
	int opCmp(in Version other) const { return opCmp(other); }
	
	string toString()
	const {
		enforce( v.length == 3 && (v[0] != MASTER_VERS || v[1] == v[2] && v[1] == MASTER_VERS) );
		if(v[0] == MASTER_VERS) 
			return MASTER_STRING;
		string r;
		for(size_t i=0; i<v.length; ++i) {
			if(i!=0) r ~= ".";
			r ~= to!string(v[i]);
		}
		return r;
	}
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
		if(ves == Version.MASTER_STRING) {
			m_cmpA = ">=";
			m_cmpB = "<=";
			m_versA = m_versB = Version(Version.MASTER);
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
		
		Version a = m_versA > o.m_versA? Version(m_versA) : Version(o.m_versA);
		Version b = m_versB < o.m_versB? Version(m_versB) : Version(o.m_versB);
		
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