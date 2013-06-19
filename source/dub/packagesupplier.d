/**
	A package supplier, able to get some packages to the local FS.

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.packagesupplier;

import dub.dependency;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.url;
import dub.utils;

import std.file;
import std.exception;
import std.zip;
import std.conv;

/// Supplies packages, this is done by supplying the latest possible version
/// which is available.
interface PackageSupplier {
	/// path: absolute path to store the package (usually in a zip format)
	void retrievePackage(const Path path, const string packageId, const Dependency dep);
	
	/// returns the metadata for the package
	Json getPackageDescription(const string packageId, const Dependency dep);
}

class FSPackageSupplier : PackageSupplier {
	private { Path m_path; }
	this(Path root) { m_path = root; }
	
	void retrievePackage(const Path path, const string packageId, const Dependency dep) {
		enforce(path.absolute);
		logInfo("Storing package '"~packageId~"', version requirements: %s", dep);
		auto filename = bestPackageFile(packageId, dep);
		enforce(existsFile(filename));
		copyFile(filename, path);
	}
	
	Json getPackageDescription(const string packageId, const Dependency dep) {
		auto filename = bestPackageFile(packageId, dep);
		return jsonFromZip(filename, "package.json");
	}
	
	private Path bestPackageFile( const string packageId, const Dependency dep) const {
		Version bestVersion = Version(Version.RELEASE);
		foreach(DirEntry d; dirEntries(m_path.toNativeString(), packageId~"*", SpanMode.shallow)) {
			Path p = Path(d.name);
			logDebug("Entry: %s", p);
			enforce(to!string(p.head)[$-4..$] == ".zip");
			string vers = to!string(p.head)[packageId.length+1..$-4];
			logDebug("Version string: "~vers);
			Version v = Version(vers);
			if(v > bestVersion && dep.matches(v) ) {
				bestVersion = v;
			}
		}
		
		auto fileName = m_path ~ (packageId ~ "_" ~ to!string(bestVersion) ~ ".zip");
		
		if(bestVersion == Version.RELEASE || !existsFile(fileName))
			throw new Exception("No matching package found");
		
		logDiagnostic("Found best matching package: '%s'", fileName);
		return fileName;
	}
}