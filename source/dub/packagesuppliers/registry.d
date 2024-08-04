module dub.packagesuppliers.registry;

import dub.dependency;
import dub.packagesuppliers.packagesupplier;

package enum PackagesPath = "packages";

/**
	Online registry based package supplier.

	This package supplier connects to an online registry (e.g.
	$(LINK https://code.dlang.org/)) to search for available packages.
*/
class RegistryPackageSupplier : PackageSupplier {
	import dub.internal.utils : retryDownload, HTTPStatusException;
	import dub.internal.vibecompat.data.json : parseJson, parseJsonString, serializeToJson;
	import dub.internal.vibecompat.inet.url : URL;
	import dub.internal.logging;

	import std.uri : encodeComponent;
	import std.datetime : Clock, Duration, hours, SysTime, UTC;
	private {
		URL m_registryUrl;
		struct CacheEntry { Json data; SysTime cacheTime; }
		CacheEntry[PackageName] m_metadataCache;
		Duration m_maxCacheTime;
	}

 	this(URL registry)
	{
		m_registryUrl = registry;
		m_maxCacheTime = 24.hours();
	}

	override @property string description() { return "registry at "~m_registryUrl.toString(); }

	override Version[] getVersions(in PackageName name)
	{
		import std.algorithm.sorting : sort;
		auto md = getMetadata(name);
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

	auto genPackageDownloadUrl(in PackageName name, in VersionRange dep, bool pre_release)
	{
		import std.array : replace;
		import std.format : format;
		import std.typecons : Nullable;
		auto md = getMetadata(name);
		Json best = getBestPackage(md, name, dep, pre_release);
		Nullable!URL ret;
		if (best.type != Json.Type.null_)
		{
			auto vers = best["version"].get!string;
			ret = m_registryUrl ~ NativePath(
				"%s/%s/%s.zip".format(PackagesPath, name.main, vers));
		}
		return ret;
	}

	override ubyte[] fetchPackage(in PackageName name,
		in VersionRange dep, bool pre_release)
	{
		import std.format : format;

		auto url = genPackageDownloadUrl(name, dep, pre_release);
		if(url.isNull) return null;
		try {
			return retryDownload(url.get);
		}
		catch(HTTPStatusException e) {
			if (e.status == 404) throw e;
			else logDebug("Failed to download package %s from %s", name.main, url);
		}
		catch(Exception e) {
			logDebug("Failed to download package %s from %s", name.main, url);
		}
		throw new Exception("Failed to download package %s from %s".format(name.main, url));
	}

	override Json fetchPackageRecipe(in PackageName name, in VersionRange dep,
		bool pre_release)
	{
		auto md = getMetadata(name);
		return getBestPackage(md, name, dep, pre_release);
	}

	private Json getMetadata(in PackageName name)
	{
		auto now = Clock.currTime(UTC());
		if (auto pentry = name.main in m_metadataCache) {
			if (pentry.cacheTime + m_maxCacheTime > now)
				return pentry.data;
			m_metadataCache.remove(name.main);
		}

		auto url = m_registryUrl ~ NativePath("api/packages/infos");

		url.queryString = "packages=" ~
			encodeComponent(`["` ~ name.main.toString() ~ `"]`) ~
			"&include_dependencies=true&minimize=true";

		logDebug("Downloading metadata for %s", name.main);
		string jsonData;

		jsonData = cast(string)retryDownload(url);

		Json json = parseJsonString(jsonData, url.toString());
		foreach (pkg, info; json.get!(Json[string]))
		{
			logDebug("adding %s to metadata cache", pkg);
			m_metadataCache[PackageName(pkg)] = CacheEntry(info, now);
		}
		return json[name.main.toString()];
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
