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

	/// perform cache operation
	void cacheOp(Path cacheDir, CacheOp op);

	/// search for packages
	Json searchForPackages(string[] names);
}

/// operations on package supplier cache
enum CacheOp {
	load,
	store,
	clean,
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
		return jsonFromZip(filename, "dub.json");
	}

	void cacheOp(Path cacheDir, CacheOp op) {
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

	Json searchForPackages(string[] names){
		assert(0, "Can't search for packages with FileSystemRegistry yet");
	}
}


/// Client PackageSupplier using the registry available via registerVpmRegistry
class RegistryPackageSupplier : PackageSupplier {
	private {
		URL m_registryUrl;
		struct CacheEntry { Json data; SysTime cacheTime; }
		CacheEntry[string] m_metadataCache;
		Duration m_maxCacheTime;
		bool m_metadataCacheDirty;
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
		auto vers = best["version"].get!string;
		auto url = m_registryUrl ~ Path(PackagesPath~"/"~packageId~"/"~vers~".zip");
		logDiagnostic("Found download URL: '%s'", url);
		download(url, path);
	}

	Json getPackageDescription(string packageId, Dependency dep, bool pre_release)
	{
		return getBestPackage(packageId, dep, pre_release);
	}

	void cacheOp(Path cacheDir, CacheOp op)
	{
		auto path = cacheDir ~ cacheFileName;
		final switch (op)
		{
		case CacheOp.store:
			if (!m_metadataCacheDirty) return;
			if (!cacheDir.existsFile())
				mkdirRecurse(cacheDir.toNativeString());
			// TODO: method is slow due to Json escaping
			writeJsonFile(path, m_metadataCache.serializeToJson());
			break;

		case CacheOp.load:
			if (!path.existsFile()) return;
			try deserializeJson(m_metadataCache, jsonFromFile(path));
			catch (Exception e) {
				import std.encoding;
				logWarn("Error loading package cache file %s: %s", path.toNativeString(), e.msg);
				logDebug("Full error: %s", e.toString().sanitize());
			}
			break;

		case CacheOp.clean:
			if (path.existsFile()) removeFile(path);
			m_metadataCache.destroy();
			break;
		}
		m_metadataCacheDirty = false;
	}

	Json searchForPackages(string[] names)
	{
		import std.array : join;
		import std.uri : encodeComponent;
		auto url = m_registryUrl ~ Path("api/search?q=" ~ names.join(",").encodeComponent);
		return (cast(string)download(url)).parseJsonString;
	}

	private @property string cacheFileName()
	{
		import std.digest.md;
		auto hash = m_registryUrl.toString.md5Of();
		return m_registryUrl.host ~ hash[0 .. $/2].toHexString().idup ~ ".json";
	}

	private Json getMetadata(string packageId)
	{
		auto now = Clock.currTime(UTC());
		if (auto pentry = packageId in m_metadataCache) {
			if (pentry.cacheTime + m_maxCacheTime > now)
				return pentry.data;
			m_metadataCache.remove(packageId);
			m_metadataCacheDirty = true;
		}

		auto url = m_registryUrl ~ Path(PackagesPath ~ "/" ~ packageId ~ ".json");

		logDebug("Downloading metadata for %s", packageId);
		logDebug("Getting from %s", url);

		auto jsonData = cast(string)download(url);
		Json json = parseJsonString(jsonData, url.toString());
		// strip readme data (to save size and time)
		foreach (ref v; json["versions"])
			v.remove("readme");
		m_metadataCache[packageId] = CacheEntry(json, now);
		m_metadataCacheDirty = true;
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
