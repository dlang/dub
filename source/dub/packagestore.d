/**
	A package store, storing and retrieving installed packages.

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.packagestore;

import std.conv;

import vibe.core.log;
import vibe.inet.path;

import dub.dependency;
import dub.package_;

class PackageStore {

	this() {
	}

	/// The PackageStore will use this directory to lookup packages.
	void includePath(Path path) { m_includePaths ~= path; }
	
	/// Retrieves an installed package.
	Package package_(string packageId, const Dependency dep) {
		logDebug("PackageStore.package_('%s', '%s')", packageId, to!string(dep));
		if(packageId == "vibe.d") {
			return new Package(Path("E:\\dev\\vibe.d"));
		}
		return null;
	}
		
	private {
		Path[] m_includePaths;
	}
}
