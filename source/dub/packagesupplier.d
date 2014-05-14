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

import std.algorithm : filter, sort;
import std.array : array;
import std.conv;
import std.datetime;
import std.exception;
import std.file;
import std.string : format;
import std.zip;

// TODO: drop the "best package" behavior and let retrievePackage/getPackageDescription take a Version instead of Dependency

/// Supplies packages, this is done by supplying the latest possible version
/// which is available.
interface PackageSupplier {
	/// Returns a hunman readable representation of the supplier
	@property string description();

	Version[] getVersions(string package_id);

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
	
	Version[] getVersions(string package_id)
	{
		Version[] ret;
		foreach (DirEntry d; dirEntries(m_path.toNativeString(), package_id~"*", SpanMode.shallow)) {
			Path p = Path(d.name);
			logDebug("Entry: %s", p);
			enforce(to!string(p.head)[$-4..$] == ".zip");
			auto vers = p.head.toString()[package_id.length+1..$-4];
			logDebug("Version: %s", vers);
			ret ~= Version(vers);
		}
		ret.sort();
		return ret;
	}

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
	{
		Path toPath(Version ver) {
			return m_path ~ (packageId ~ "-" ~ ver.toString() ~ ".zip");
		}
		auto versions = getVersions(packageId).filter!(v => dep.matches(v)).array;
		enforce(versions.length > 0, format("No package %s found matching %s", packageId, dep));
		foreach_reverse (ver; versions) {
			if (pre_release || !ver.isPreRelease)
				return toPath(ver);
		}
		return toPath(versions[$-1]);
	}
}


/// Client PackageSupplier using the registry available via registerVpmRegistry
class RegistryPackageSupplier : PackageSupplier {
	private {
		URL m_registryUrl;
		struct CacheEntry { Json data; SysTime cacheTime; }
		CacheEntry[string] m_metadataCache;
		Duration m_maxCacheTime;
	}
	
	this(URL registry)
	{
		m_registryUrl = registry;
		m_maxCacheTime = 24.hours();
	}

	override @property string description() { return "registry at "~m_registryUrl.toString(); }

	Version[] getVersions(string package_id)
	{
		Version[] ret;
		Json md = getMetadata(package_id);
		foreach (json; md["versions"]) {
			auto cur = Version(cast(string)json["version"]);
			ret ~= cur;
		}
		ret.sort();
		return ret;
	}
	
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
		auto now = Clock.currTime(UTC());
		if (auto pentry = packageId in m_metadataCache) {
			if (pentry.cacheTime + m_maxCacheTime > now)
				return pentry.data;
		}

		auto url = m_registryUrl ~ Path(PackagesPath ~ "/" ~ packageId ~ ".json");
		
		logDebug("Downloading metadata for %s", packageId);
		logDebug("Getting from %s", url);

		auto jsonData = cast(string)download(url);
		Json json = parseJsonString(jsonData);
		m_metadataCache[packageId] = CacheEntry(json, now);
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
