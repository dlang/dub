/**
	A package supplier, able to get some packages to the local FS.

	Copyright: © 2012-2013 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.packagesupplier;

import dub.dependency;
import dub.internal.utils;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.url;

import std.file;
import std.exception;
import std.zip;
import std.conv;

/// Supplies packages, this is done by supplying the latest possible version
/// which is available.
interface PackageSupplier {
	/// Returns a hunman readable representation of the supplier
	@property string description();

	/// path: absolute path to store the package (usually in a zip format)
	void retrievePackage(Path path, string packageId, Dependency dep, bool pre_release);
	
	/// returns the metadata for the package
	Json getPackageDescription(string packageId, Dependency dep, bool pre_release);
}

class FileSystemPackageSupplier : PackageSupplier {
	private {
		Path m_path;
	}

	this(Path root) { m_path = root; }

	override @property string description() { return "file repository at "~m_path.toNativeString(); }
	
	void retrievePackage(Path path, string packageId, Dependency dep, bool pre_release)
	{
		enforce(path.absolute);
		logInfo("Storing package '"~packageId~"', version requirements: %s", dep);
		auto filename = bestPackageFile(packageId, dep, pre_release);
		enforce(existsFile(filename));
		copyFile(filename, path);
	}
	
	Json getPackageDescription(string packageId, Dependency dep, bool pre_release)
	{
		auto filename = bestPackageFile(packageId, dep, pre_release);
		return jsonFromZip(filename, "package.json");
	}
	
	private Path bestPackageFile(string packageId, Dependency dep, bool pre_release)
	const {
		Version bestver = Version.RELEASE;
		foreach (DirEntry d; dirEntries(m_path.toNativeString(), packageId~"*", SpanMode.shallow)) {
			Path p = Path(d.name);
			logDebug("Entry: %s", p);
			enforce(to!string(p.head)[$-4..$] == ".zip");
			string vers = to!string(p.head)[packageId.length+1..$-4];
			logDebug("Version string: "~vers);
			Version cur = Version(vers);
			if (!dep.matches(cur)) continue;
			if (bestver == Version.RELEASE) bestver = cur;
			else if (pre_release) {
				if (cur > bestver) bestver = cur;
			} else if (bestver.isPreRelease) {
				if (!cur.isPreRelease || cur > bestver) bestver = cur;
			} else if (!cur.isPreRelease && cur > bestver) bestver = cur;
		}
		
		auto fileName = m_path ~ (packageId ~ "_" ~ to!string(bestver) ~ ".zip");
		
		if (bestver == Version.RELEASE || !existsFile(fileName))
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

	override @property string description() { return "registry at "~m_registryUrl.toString(); }
	
	void retrievePackage(Path path, string packageId, Dependency dep, bool pre_release)
	{
		import std.array : replace;
		Json best = getBestPackage(packageId, dep, pre_release);
		auto vers = replace(best["version"].get!string, "+", "%2B");
		auto url = m_registryUrl ~ Path(PackagesPath~"/"~packageId~"/"~vers~".zip");
		logDiagnostic("Found download URL: '%s'", url);
		download(url, path);
	}
	
	Json getPackageDescription(string packageId, Dependency dep, bool pre_release)
	{
		return getBestPackage(packageId, dep, pre_release);
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
	
	private Json getBestPackage(string packageId, Dependency dep, bool pre_release)
	{
		Json md = getMetadata(packageId);
		Json best = null;
		Version bestver;
		foreach (json; md["versions"]) {
			auto cur = Version(cast(string)json["version"]);
			if (!dep.matches(cur)) continue;
			if (best == null) best = json;
			else if (pre_release) {
				if (cur > bestver) best = json;
			} else if (bestver.isPreRelease) {
				if (!cur.isPreRelease || cur > bestver) best = json;
			} else if (!cur.isPreRelease && cur > bestver) best = json;
			bestver = Version(cast(string)best["version"]);
		}
		enforce(best != null, "No package candidate found for "~packageId~" "~dep.toString());
		return best;
	}
}

private enum PackagesPath = "packages";
