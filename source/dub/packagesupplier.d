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
	void retrievePackage(Path path, string packageId, Dependency dep);
	
	/// returns the metadata for the package
	Json getPackageDescription(string packageId, Dependency dep);

	/// Returns a hunman readable representation of the supplier
	string toString();
}

class FileSystemPackageSupplier : PackageSupplier {
	private {
		Path m_path;
	}

	this(Path root) { m_path = root; }

	override string toString() { return "file repository at "~m_path.toNativeString(); }
	
	void retrievePackage(Path path, string packageId, Dependency dep)
	{
		enforce(path.absolute);
		logInfo("Storing package '"~packageId~"', version requirements: %s", dep);
		auto filename = bestPackageFile(packageId, dep);
		enforce(existsFile(filename));
		copyFile(filename, path);
	}
	
	Json getPackageDescription(string packageId, Dependency dep)
	{
		auto filename = bestPackageFile(packageId, dep);
		return jsonFromZip(filename, "package.json");
	}
	
	private Path bestPackageFile(string packageId, Dependency dep)
	const {
		Version bestVersion = Version.RELEASE;
		foreach (DirEntry d; dirEntries(m_path.toNativeString(), packageId~"*", SpanMode.shallow)) {
			Path p = Path(d.name);
			logDebug("Entry: %s", p);
			enforce(to!string(p.head)[$-4..$] == ".zip");
			string vers = to!string(p.head)[packageId.length+1..$-4];
			logDebug("Version string: "~vers);
			Version v = Version(vers);
			if (v > bestVersion && dep.matches(v)) {
				bestVersion = v;
			}
		}
		
		auto fileName = m_path ~ (packageId ~ "_" ~ to!string(bestVersion) ~ ".zip");
		
		if (bestVersion == Version.RELEASE || !existsFile(fileName))
			throw new Exception("No matching package found");
		
		logDiagnostic("Found best matching package: '%s'", fileName);
		return fileName;
	}
}


/// Client PackageSupplier using the registry available via registerVpmRegistry
class RegistryPackageSupplier : PackageSupplier {
	private {
		Url m_registryUrl;
		Json[string] m_allMetadata;
	}
	
	this(Url registry)
	{
		m_registryUrl = registry;
	}

	override string toString() { return "registry at "~m_registryUrl.toString(); }
	
	void retrievePackage(Path path, string packageId, Dependency dep)
	{
		Json best = getBestPackage(packageId, dep);
		auto url = m_registryUrl ~ Path(PackagesPath~"/"~packageId~"/"~best["version"].get!string~".zip");
		logDiagnostic("Found download URL: '%s'", url);
		download(url, path);
	}
	
	Json getPackageDescription(string packageId, Dependency dep)
	{
		return getBestPackage(packageId, dep);
	}
	
	private Json getMetadata(string packageId)
	{
		if (auto json = packageId in m_allMetadata)
			return *json;

		auto url = m_registryUrl ~ Path(PackagesPath ~ "/" ~ packageId ~ ".json");
		
		logDebug("Downloading metadata for %s", packageId);
		logDebug("Getting from %s", url);

		auto jsonData = cast(string)download(url);
		Json json = parseJson(jsonData);
		m_allMetadata[packageId] = json;
		return json;
	}
	
	private Json getBestPackage(string packageId, Dependency dep)
	{
		Json md = getMetadata(packageId);
		Json best = null;
		foreach (json; md["versions"]) {
			auto cur = Version(cast(string)json["version"]);
			if (dep.matches(cur) && (best == null || Version(cast(string)best["version"]) < cur))
				best = json;
		}
		enforce(best != null, "No package candidate found for "~packageId~" "~dep.toString());
		return best;
	}
}

private enum PackagesPath = "packages";
