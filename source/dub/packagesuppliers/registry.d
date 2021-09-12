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

	import std.uri : encodeComponent;
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

	Version[] getVersions(PackageName package_name)
	{
		import std.algorithm.sorting : sort;
		auto md = getMetadata(package_name);
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

	auto genPackageDownloadUrl(PackageName package_name, Dependency dep, bool pre_release)
	{
		import std.array : replace;
		import std.format : format;
		import std.typecons : Nullable;
		auto md = getMetadata(package_name);
		Json best = getBestPackage(md, package_name, dep, pre_release);
		Nullable!URL ret;
		if (best.type != Json.Type.null_)
		{
			auto vers = best["version"].get!string;
			ret = m_registryUrl ~ NativePath(PackagesPath~"/"~package_name~"/"~vers~".zip");
		}
		return ret;
	}

	void fetchPackage(NativePath path, PackageName package_name, Dependency dep, bool pre_release)
	{
		import std.format : format;
		auto url = genPackageDownloadUrl(package_name, dep, pre_release);
		if(url.isNull)
			return;
		try {
			retryDownload(url.get, path);
			return;
		}
		catch(HTTPStatusException e) {
			if (e.status == 404) throw e;
			else logDebug("Failed to download package %s from %s", package_name, url);
		}
		catch(Exception e) {
			logDebug("Failed to download package %s from %s", package_name, url);
		}
		throw new Exception("Failed to download package %s from %s".format(package_name, url));
	}

	Json fetchPackageRecipe(PackageName package_name, Dependency dep, bool pre_release)
	{
		auto md = getMetadata(package_name);
		return getBestPackage(md, package_name, dep, pre_release);
	}

	private Json getMetadata(PackageName package_name)
	{
		auto now = Clock.currTime(UTC());
		if (auto pentry = package_name in m_metadataCache) {
			if (pentry.cacheTime + m_maxCacheTime > now)
				return pentry.data;
			m_metadataCache.remove(package_name);
		}

		auto url = m_registryUrl ~ NativePath("api/packages/infos");

		url.queryString = "packages=" ~
				encodeComponent(`["` ~ package_name ~ `"]`) ~ "&include_dependencies=true&minimize=true";

		logDebug("Downloading metadata for %s", package_name);
		string jsonData;

		jsonData = cast(string)retryDownload(url);

		Json json = parseJsonString(jsonData, url.toString());
		foreach (pkg, info; json.get!(Json[string]))
		{
			logDebug("adding %s to metadata cache", pkg);
			m_metadataCache[pkg] = CacheEntry(info, now);
		}
		return json[package_name];
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
			.map!(j => SearchResult(PackageName(j["name"].opt!string),
									j["description"].opt!string,
									j["version"].opt!string))
			.array;
	}
}
