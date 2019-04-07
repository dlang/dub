module dub.packagesuppliers.registry;

import dub.packagesuppliers.packagesupplier;

package enum PackagesPath = "packages";

/**
	Online registry based package supplier.

	This package supplier connects to an online registry (e.g.
	$(LINK https://code.dlang.org/)) to search for available packages.
*/
class RegistryPackageSupplier : PackageSupplier {
	import dub.internal.utils : download, retryDownload, HTTPStatusException;
	import dub.internal.vibecompat.core.log;
	import dub.internal.vibecompat.data.json : parseJson, parseJsonString, serializeToJson;
	import dub.internal.vibecompat.inet.url : URL;

	import std.datetime : Clock, Duration, hours, SysTime, UTC;
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
		import std.algorithm.sorting : sort;
		auto md = getMetadata(package_id);
		if (md.type == Json.Type.null_)
			return null;
		Version[] ret;
		foreach (json; md["versions"]) {
			auto cur = Version(cast(string)json["version"]);
			ret ~= cur;
		}
		ret.sort();
		return ret;
	}

	void fetchPackage(NativePath path, string packageId, Dependency dep, bool pre_release)
	{
		import std.array : replace;
		import std.format : format;
		auto md = getMetadata(packageId);
		Json best = getBestPackage(md, packageId, dep, pre_release);
		if (best.type == Json.Type.null_)
			return;
		auto vers = best["version"].get!string;
		auto url = m_registryUrl ~ NativePath(PackagesPath~"/"~packageId~"/"~vers~".zip");
		try {
			retryDownload(url, path);
			return;
		}
		catch(HTTPStatusException e) {
			if (e.status == 404) throw e;
			else logDebug("Failed to download package %s from %s", packageId, url);
		}
		catch(Exception e) {
			logDebug("Failed to download package %s from %s", packageId, url);
		}
		throw new Exception("Failed to download package %s from %s".format(packageId, url));
	}

	Json fetchPackageRecipe(string packageId, Dependency dep, bool pre_release)
	{
		auto md = getMetadata(packageId);
		return getBestPackage(md, packageId, dep, pre_release);
	}

	private Json getMetadata(string packageId)
	{
		auto now = Clock.currTime(UTC());
		if (auto pentry = packageId in m_metadataCache) {
			if (pentry.cacheTime + m_maxCacheTime > now)
				return pentry.data;
			m_metadataCache.remove(packageId);
		}

		auto url = m_registryUrl ~ NativePath("api/packages/" ~ packageId ~ "/info?minimize=true");

		logDebug("Downloading metadata for %s", packageId);
		string jsonData;

		try
			jsonData = cast(string)retryDownload(url);
		catch(HTTPStatusException e) {
			if (e.status == 404) {
				logDebug("Package %s not found at %s (404): %s", packageId, description, e.msg);
				return Json(null);
			}
			else throw e;
		}

		Json json = parseJsonString(jsonData, url.toString());
		m_metadataCache[packageId] = CacheEntry(json, now);
		return json;
	}

	SearchResult[] searchPackages(string query) {
		import std.array : array;
		import std.algorithm.iteration : map;
		import std.uri : encodeComponent;
		auto url = m_registryUrl;
		url.localURI = "/api/packages/search?q="~encodeComponent(query);
		string data;
		data = cast(string)retryDownload(url);
		return data.parseJson.opt!(Json[])
			.map!(j => SearchResult(j["name"].opt!string, j["description"].opt!string, j["version"].opt!string))
			.array;
	}
}

