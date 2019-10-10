/**
	Implementes version validation and comparison according to the semantic
	versioning specification.

	The general format of a semantiv version is: a.b.c[-x.y...][+x.y...]
	a/b/c must be integer numbers with no leading zeros, and x/y/... must be
	either numbers or identifiers containing only ASCII alphabetic characters
	or hyphens. Identifiers may not start with a digit.

	See_Also: http://semver.org/

	Copyright: © 2013-2016 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.semver;

import std.algorithm : map, max;
import std.conv;
import std.range;
import std.regex;
import std.string;

@safe:

struct SemVer {
	int major;
	int minor;
	int patch;
	string prerelease;
	string buildmetadata;

	enum semVerRegex = `^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)` ~
		`(?:-(?P<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))` ~
		`?(?:\+(?P<buildmetadata>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$`;

	this(string version_) {
		import std.exception : enforce;

		if (__ctfe) {
			// regex does not work at compiletime
			if (version_ == "0.0.0") return;
			if (version_ == "99999.0.0") {
				this.major = 99999;
				return;
			}
			assert(false, version_);
		}
		enforce(isValidVersion(version_), "corrupt version '%s'".format(version_));

		auto match = matchFirst(version_, ctRegex!semVerRegex);

		enforce(!match.empty, "corrupt version '%s'".format(version_));

		this(
			match["major"].to!int,
			match["minor"].to!int,
			match["patch"].to!int,
			match["prerelease"],
			match["buildmetadata"]
		);
	}

	this(int major, int minor, int patch = 0, string prerelease = null, string buildmetadata = null) {
		this.major = major;
		this.minor = minor;
		this.patch = patch;
		this.prerelease = prerelease;
		this.buildmetadata = buildmetadata;
	}

	string toString() const {
		return "%s.%s.%s".format(this.major, this.minor, this.patch) ~
			(this.prerelease.empty ? "" : format!"-%s"(this.prerelease)) ~
			(this.buildmetadata.empty ? "" : format!"+%s"(this.buildmetadata));
	}
}

/**
	Validates a version string according to the SemVer specification.
*/
bool isValidVersion(string ver) {
	// NOTE: this is not by spec, but to ensure sane input
	if (ver.length > 256) return false;

	if (__ctfe) {
		// regex does not work at compiletime
		if (ver == "0.0.0") return true;
		if (ver == "99999.0.0") return true;
		assert(false, ver);
	}

	return !matchFirst(ver, ctRegex!(SemVer.semVerRegex)).empty;
}

///
unittest {
	assert(isValidVersion("1.9.0"));
	assert(isValidVersion("0.10.0"));
	assert(!isValidVersion("01.9.0"));
	assert(!isValidVersion("1.09.0"));
	assert(!isValidVersion("1.9.00"));
	assert(isValidVersion("1.0.0-alpha"));
	assert(isValidVersion("1.0.0-alpha.1"));
	assert(isValidVersion("1.0.0-0.3.7"));
	assert(isValidVersion("1.0.0-x.7.z.92"));
	assert(isValidVersion("1.0.0-x.7-z.92"));
	assert(!isValidVersion("1.0.0-00.3.7"));
	assert(!isValidVersion("1.0.0-0.03.7"));
	assert(isValidVersion("1.0.0-alpha+001"));
	assert(isValidVersion("1.0.0+20130313144700"));
	assert(isValidVersion("1.0.0-beta+exp.sha.5114f85"));
	assert(!isValidVersion(" 1.0.0"));
	assert(!isValidVersion("1. 0.0"));
	assert(!isValidVersion("1.0 .0"));
	assert(!isValidVersion("1.0.0 "));
	assert(!isValidVersion("1.0.0-a_b"));
	assert(!isValidVersion("1.0.0+"));
	assert(!isValidVersion("1.0.0-"));
	assert(!isValidVersion("1.0.0-+a"));
	assert(!isValidVersion("1.0.0-a+"));
	assert(!isValidVersion("1.0"));
	assert(!isValidVersion("1.0-1.0"));
}

/**
	Compares the precedence of two SemVer versions.

	Note that the build meta data suffix (if any) is
	being ignored when comparing version numbers.

	Returns:
		Returns a negative number if `a` is a lower version than `b`, `0` if they are
		equal, and a positive number otherwise.
*/
int compareVersions(SemVer a, SemVer b)
pure @nogc {
	// compare a.b.c numerically
	int cmp(T)(T a, T b) { return (a < b) ? -1 : ((a > b) ? 1 : 0); }
	if (auto ret = cmp(a.major, b.major)) return ret;
	if (auto ret = cmp(a.minor, b.minor)) return ret;
	if (auto ret = cmp(a.patch, b.patch)) return ret;

	// give precedence to non-prerelease versions
	if (auto ret = cmp(a.prerelease.empty, b.prerelease.empty)) return ret;

	if (a.prerelease.empty) return 0;

	// compare the prerelease tail lexicographically
	auto apre = a.prerelease, bpre = b.prerelease;
	do {
		if (auto ret = compareIdentifier(apre, bpre)) return ret;
		apre = apre.drop(1);
		bpre = bpre.drop(1);
	} while (!apre.empty && !bpre.empty);

	// give longer prerelease tails precedence
	if (auto ret = cmp(apre.length, bpre.length)) return ret;

	return 0;
}

///
unittest {
	assert(compareVersions(SemVer("1.0.0"), SemVer("1.0.0")) == 0);
	assert(compareVersions(SemVer("1.0.0+b1"), SemVer("1.0.0+b2")) == 0);
	assert(compareVersions(SemVer("1.0.0"), SemVer("2.0.0")) < 0);
	assert(compareVersions(SemVer("1.0.0-beta"), SemVer("1.0.0")) < 0);
	assert(compareVersions(SemVer("1.0.1"), SemVer("1.0.0")) > 0);
}

unittest {
	void assertLess(string a, string b) {
		auto versionA = SemVer(a);
		auto versionB = SemVer(b);

		assert(compareVersions(versionA, versionB) < 0, "Failed for "~a~" < "~b);
		assert(compareVersions(versionB, versionA) > 0);
		assert(compareVersions(versionA, versionA) == 0);
		assert(compareVersions(versionB, versionB) == 0);
	}
	assertLess("1.0.0", "2.0.0");
	assertLess("2.0.0", "2.1.0");
	assertLess("2.1.0", "2.1.1");
	assertLess("1.0.0-alpha", "1.0.0");
	assertLess("1.0.0-alpha", "1.0.0-alpha.1");
	assertLess("1.0.0-alpha.1", "1.0.0-alpha.beta");
	assertLess("1.0.0-alpha.beta", "1.0.0-beta");
	assertLess("1.0.0-beta", "1.0.0-beta.2");
	assertLess("1.0.0-beta.2", "1.0.0-beta.11");
	assertLess("1.0.0-beta.11", "1.0.0-rc.1");
	assertLess("1.0.0-rc.1", "1.0.0");
	assert(compareVersions(SemVer("1.0.0"), SemVer("1.0.0+1.2.3")) == 0);
	assert(compareVersions(SemVer("1.0.0"), SemVer("1.0.0+1.2.3-2")) == 0);
	assert(compareVersions(SemVer("1.0.0+asdasd"), SemVer("1.0.0+1.2.3")) == 0);
	assertLess("2.0.0", "10.0.0");
	assertLess("1.0.0-2", "1.0.0-10");
	assertLess("1.0.0-99", "1.0.0-1a");
	assertLess("1.0.0-99", "1.0.0-a");
	assertLess("1.0.0-alpha", "1.0.0-alphb");
	assertLess("1.0.0-alphz", "1.0.0-alphz0");
	assertLess("1.0.0-alphZ", "1.0.0-alpha");
}

/**
	Increments a given (partial) version number to the next higher version.

	Prerelease and build metadata information is ignored. The given version
	can skip the minor and patch digits. If no digits are skipped, the next
	minor version will be selected. If the patch or minor versions are skipped,
	the next major version will be selected.

	This function corresponds to the semantivs of the "~>" comparison operator's
	upper bound.

	The semantics of this are the same as for the "approximate" version
	specifier from rubygems.
	(https://github.com/rubygems/rubygems/tree/81d806d818baeb5dcb6398ca631d772a003d078e/lib/rubygems/version.rb)

	See_Also: `expandVersion`
*/
string bumpVersion(string ver)
pure {
	// Cut off metadata and prerelease information.
	auto mi = ver.indexOfAny("+-");
	if (mi > 0) ver = ver[0..mi];
	// Increment next to last version from a[.b[.c]].
	auto splitted = () @trusted { return split(ver, "."); } (); // DMD 2.065.0
	assert(splitted.length > 0 && splitted.length <= 3, "Version corrupt: " ~ ver);
	auto to_inc = splitted.length == 3? 1 : 0;
	splitted = splitted[0 .. to_inc+1];
	splitted[to_inc] = to!string(to!int(splitted[to_inc]) + 1);
	// Fill up to three compontents to make valid SemVer version.
	while (splitted.length < 3) splitted ~= "0";
	return splitted.join(".");
}
///
unittest {
	assert("1.0.0" == bumpVersion("0"));
	assert("1.0.0" == bumpVersion("0.0"));
	assert("0.1.0" == bumpVersion("0.0.0"));
	assert("1.3.0" == bumpVersion("1.2.3"));
	assert("1.3.0" == bumpVersion("1.2.3+metadata"));
	assert("1.3.0" == bumpVersion("1.2.3-pre.release"));
	assert("1.3.0" == bumpVersion("1.2.3-pre.release+metadata"));
}

/**
	Takes a partial version and expands it to a valid SemVer version.

	This function corresponds to the semantivs of the "~>" comparison operator's
	lower bound.

	See_Also: `bumpVersion`
*/
string expandVersion(string ver)
pure {
	auto mi = ver.indexOfAny("+-");
	auto sub = "";
	if (mi > 0) {
		sub = ver[mi..$];
		ver = ver[0..mi];
	}
	auto splitted = () @trusted { return split(ver, "."); } (); // DMD 2.065.0
	assert(splitted.length > 0 && splitted.length <= 3, "Version corrupt: " ~ ver);
	while (splitted.length < 3) splitted ~= "0";
	return splitted.join(".") ~ sub;
}
///
unittest {
	assert("1.0.0" == expandVersion("1"));
	assert("1.0.0" == expandVersion("1.0"));
	assert("1.0.0" == expandVersion("1.0.0"));
	// These are rather excotic variants...
	assert("1.0.0-pre.release" == expandVersion("1-pre.release"));
	assert("1.0.0+meta" == expandVersion("1+meta"));
	assert("1.0.0-pre.release+meta" == expandVersion("1-pre.release+meta"));
}

private int compareIdentifier(ref string a, ref string b)
pure @nogc {
	bool anumber = true;
	bool bnumber = true;
	bool aempty = true, bempty = true;
	int res = 0;
	while (true) {
		if (a[0] != b[0] && res == 0) res = a[0] - b[0];
		if (anumber && (a[0] < '0' || a[0] > '9')) anumber = false;
		if (bnumber && (b[0] < '0' || b[0] > '9')) bnumber = false;
		a = a[1 .. $]; b = b[1 .. $];
		aempty = !a.length || a[0] == '.' || a[0] == '+';
		bempty = !b.length || b[0] == '.' || b[0] == '+';
		if (aempty || bempty) break;
	}

	if (anumber && bnumber) {
		// the !empty value might be an indentifier instead of a number, but identifiers always have precedence
		if (aempty != bempty) return bempty - aempty;
		return res;
	} else {
		if (anumber && aempty) return -1;
		if (bnumber && bempty) return 1;
		// this assumption is necessary to correctly classify 111A > 11111 (ident always > number)!
		static assert('0' < 'a' && '0' < 'A');
		if (res != 0) return res;
		return bempty - aempty;
	}
}

private ptrdiff_t indexOfAny(string str, in char[] chars)
pure @nogc {
	ptrdiff_t ret = -1;
	foreach (ch; chars) {
		auto idx = str.indexOf(ch);
		if (idx >= 0 && (ret < 0 || idx < ret))
			ret = idx;
	}
	return ret;
}
