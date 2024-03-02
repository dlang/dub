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
	import dub.internal.vibecompat.inet.url : URL;
	import dub.internal.logging;

	import std.datetime : Clock, Duration, hours, SysTime, UTC;

	private {
		enum httpTimeout = 16;
		URL m_mavenUrl;
		struct CacheEntry { Json data; SysTime cacheTime; }
		CacheEntry[PackageName] m_metadataCache;
		Duration m_maxCacheTime;
	}

	this(URL mavenUrl)
	{
		m_mavenUrl = mavenUrl;
		m_maxCacheTime = 24.hours();
	}

	override @property string description() { return "maven repository at "~m_mavenUrl.toString(); }

	override Version[] getVersions(in PackageName name)
	{
		import std.algorithm.sorting : sort;
		auto md = getMetadata(name.main);
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

	override ubyte[] fetchPackage(in PackageName name,
		in VersionRange dep, bool pre_release)
	{
		import std.format : format;
		auto md = getMetadata(name.main);
		Json best = getBestPackage(md, name.main, dep, pre_release);
		if (best.type == Json.Type.null_)
			return null;
		auto vers = best["version"].get!string;
		auto url = m_mavenUrl ~ NativePath(
			"%s/%s/%s-%s.zip".format(name.main, vers, name.main, vers));

		try {
			return retryDownload(url, 3, httpTimeout);
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
		import dub.internal.undead.xml;

		auto now = Clock.currTime(UTC());
		if (auto pentry = name.main in m_metadataCache) {
			if (pentry.cacheTime + m_maxCacheTime > now)
				return pentry.data;
			m_metadataCache.remove(name.main);
		}

		auto url = m_mavenUrl ~ NativePath(name.main.toString() ~ "/maven-metadata.xml");

		logDebug("Downloading maven metadata for %s", name.main);
		string xmlData;

		try
			xmlData = cast(string)retryDownload(url, 3, httpTimeout);
		catch(HTTPStatusException e) {
			if (e.status == 404) {
				logDebug("Maven metadata %s not found at %s (404): %s", name.main, description, e.msg);
				return Json(null);
			}
			else throw e;
		}

		auto json = Json([
			"name": Json(name.main.toString()),
			"versions": Json.emptyArray
		]);
		auto xml = new DocumentParser(xmlData);

		xml.onStartTag["versions"] = (ElementParser xml) {
			 xml.onEndTag["version"] = (in Element e) {
				json["versions"] ~= serializeToJson([
					"name": name.main.toString(),
					"version": e.text,
				]);
			 };
			 xml.parse();
		};
		xml.parse();

		m_metadataCache[name.main] = CacheEntry(json, now);
		return json;
	}

	SearchResult[] searchPackages(string query)
	{
		// Only exact search is supported
		// This enables retrieval of dub packages on dub run
		auto md = getMetadata(PackageName(query));
		if (md.type == Json.Type.null_)
			return null;
		auto json = getBestPackage(md, PackageName(query), VersionRange.Any, true);
		return [SearchResult(json["name"].opt!string, "", json["version"].opt!string)];
	}
}
