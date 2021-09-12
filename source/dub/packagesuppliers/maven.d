module dub.packagesuppliers.maven;

import dub.packagesuppliers.packagesupplier;

/**
	Maven repository based package supplier.

	This package supplier connects to a maven repository
	to search for available packages.
*/
class MavenRegistryPackageSupplier : PackageSupplier {
	import dub.internal.utils : retryDownload, HTTPStatusException;
	import dub.internal.vibecompat.data.json : serializeToJson;
	import dub.internal.vibecompat.core.log;
	import dub.internal.vibecompat.inet.url : URL;

	import std.datetime : Clock, Duration, hours, SysTime, UTC;

	private {
		enum httpTimeout = 16;
		URL m_mavenUrl;
		struct CacheEntry { Json data; SysTime cacheTime; }
		CacheEntry[string] m_metadataCache;
		Duration m_maxCacheTime;
	}

	this(URL mavenUrl)
	{
		m_mavenUrl = mavenUrl;
		m_maxCacheTime = 24.hours();
	}

	override @property string description() { return "maven repository at "~m_mavenUrl.toString(); }

	Version[] getVersions(PackageName package_name)
	{
		import std.algorithm.sorting : sort;
		auto md = getMetadata(package_name);
		if (md.type == Json.Type.null_)
			return null;
		Version[] ret;
		foreach (json; md["versions"]) {
			auto cur = Version(json["version"].get!string);
			ret ~= cur;
		}
		ret.sort();
		return ret;
	}

	void fetchPackage(NativePath path, PackageName package_name, Dependency dep, bool pre_release)
	{
		import std.format : format;
		auto md = getMetadata(package_name);
		Json best = getBestPackage(md, package_name, dep, pre_release);
		if (best.type == Json.Type.null_)
			return;
		auto vers = best["version"].get!string;
		auto url = m_mavenUrl~NativePath("%s/%s/%s-%s.zip".format(package_name, vers, package_name, vers));

		try {
			retryDownload(url, path, 3, httpTimeout);
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
		import dub.internal.undead.xml;

		auto now = Clock.currTime(UTC());
		if (auto pentry = package_name in m_metadataCache) {
			if (pentry.cacheTime + m_maxCacheTime > now)
				return pentry.data;
			m_metadataCache.remove(package_name);
		}

		auto url = m_mavenUrl~NativePath(package_name~"/maven-metadata.xml");

		logDebug("Downloading maven metadata for %s", package_name);
		string xmlData;

		try
			xmlData = cast(string)retryDownload(url, 3, httpTimeout);
		catch(HTTPStatusException e) {
			if (e.status == 404) {
				logDebug("Maven metadata %s not found at %s (404): %s", package_name, description, e.msg);
				return Json(null);
			}
			else throw e;
		}

		auto json = Json(["name": Json(package_name), "versions": Json.emptyArray]);
		auto xml = new DocumentParser(xmlData);

		xml.onStartTag["versions"] = (ElementParser xml) {
			 xml.onEndTag["version"] = (in Element e) {
				json["versions"] ~= serializeToJson(["name": package_name, "version": e.text]);
			 };
			 xml.parse();
		};
		xml.parse();

		m_metadataCache[package_name] = CacheEntry(json, now);
		return json;
	}

	SearchResult[] searchPackages(string query)
	{
		// Only exact search is supported
		// This enables retrival of dub packages on dub run
		auto md = getMetadata(PackageName(query));
		if (md.type == Json.Type.null_)
			return [];
		auto json = getBestPackage(md, PackageName(query), Dependency(">=0.0.0"), true);
		return [SearchResult(PackageName(json["name"].opt!string),
							 "",
							 json["version"].opt!string)];
	}
}
