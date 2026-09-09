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
	import dub.internal.vibecompat.inet.path : InetPath;
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
		auto md = getMetadata(name.base);
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
		auto md = getMetadata(name.base);
		Json best = getBestPackage(md, name.base, dep, pre_release);
		if (best.type == Json.Type.null_)
			return null;
		auto vers = best["version"].get!string;
		auto url = m_mavenUrl ~ InetPath(
			"%s/%s/%s-%s.zip".format(name.base, vers, name.base, vers));

		try {
			return retryDownload(url, 3, httpTimeout);
		}
		catch(HTTPStatusException e) {
			if (e.status == 404) throw e;
			else logDebug("Failed to download package %s from %s", name.base, url);
		}
		catch(Exception e) {
			logDebug("Failed to download package %s from %s", name.base, url);
		}
		throw new Exception("Failed to download package %s from %s".format(name.base, url));
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
		if (auto pentry = name.base in m_metadataCache) {
			if (pentry.cacheTime + m_maxCacheTime > now)
				return pentry.data;
			m_metadataCache.remove(name.base);
		}

		auto url = m_mavenUrl ~ InetPath(name.base.toString() ~ "/maven-metadata.xml");

		logDebug("Downloading maven metadata for %s", name.base);
		string xmlData;

		try
			xmlData = cast(string)retryDownload(url, 3, httpTimeout);
		catch(HTTPStatusException e) {
			if (e.status == 404) {
				logDebug("Maven metadata %s not found at %s (404): %s", name.base, description, e.msg);
				return Json(null);
			}
			else throw e;
		}

		auto json = Json([
			"name": Json(name.base.toString()),
			"versions": Json.emptyArray
		]);
		auto xml = new DocumentParser(xmlData);

		xml.onStartTag["versions"] = (ElementParser xml) {
			 xml.onEndTag["version"] = (in Element e) {
				json["versions"] ~= serializeToJson([
					"name": name.base.toString(),
					"version": e.text,
				]);
			 };
			 xml.parse();
		};
		xml.parse();

		m_metadataCache[name.base] = CacheEntry(json, now);
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
