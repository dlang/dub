module dub.packagesuppliers.maven;

import dub.packagesuppliers.packagesupplier;

/**
	Maven repository based package supplier.

	This package supplier connects to a maven repository
	to search for available packages.
*/
class MavenRegistryPackageSupplier : PackageSupplier {
	import dub.internal.utils : download, HTTPStatusException;
	import dub.internal.vibecompat.data.json : serializeToJson;
	import dub.internal.vibecompat.inet.url : URL;
  import dub.logging;

	import std.datetime : Clock, Duration, hours, SysTime, UTC;

	private {
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

	Version[] getVersions(string package_id)
	{
		import std.algorithm.sorting : sort;
		auto md = getMetadata(package_id);
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

	void fetchPackage(NativePath path, string packageId, Dependency dep, bool pre_release)
	{
		import std.format : format;
		auto md = getMetadata(packageId);
		Json best = getBestPackage(md, packageId, dep, pre_release);
		if (best.type == Json.Type.null_)
			return;
		auto vers = best["version"].get!string;
		auto url = m_mavenUrl~NativePath("%s/%s/%s-%s.zip".format(packageId, vers, packageId, vers));
		logDiagnostic("Downloading from '%s'", url);
		foreach(i; 0..3) {
			try{
				download(url, path);
				return;
			}
			catch(HTTPStatusException e) {
				if (e.status == 404) throw e;
				else {
					logDebug("Failed to download package %s from %s (Attempt %s of 3)", packageId, url, i + 1);
					continue;
				}
			}
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
		import std.xml;

		auto now = Clock.currTime(UTC());
		if (auto pentry = packageId in m_metadataCache) {
			if (pentry.cacheTime + m_maxCacheTime > now)
				return pentry.data;
			m_metadataCache.remove(packageId);
		}

		auto url = m_mavenUrl~NativePath(packageId~"/maven-metadata.xml");

		logDebug("Downloading maven metadata for %s", packageId);
		logDebug("Getting from %s", url);

		string xmlData;
		foreach(i; 0..3) {
			try {
				xmlData = cast(string)download(url);
				break;
			}
			catch (HTTPStatusException e)
			{
				if (e.status == 404) {
					logDebug("Maven metadata %s not found at %s (404): %s", packageId, description, e.msg);
					return Json(null);
				}
				else {
					logDebug("Error getting maven metadata for %s at %s (attempt %s of 3): %s", packageId, description, i + 1, e.msg);
					if (i == 2)
						throw e;
					continue;
				}
			}
		}

		auto json = Json(["name": Json(packageId), "versions": Json.emptyArray]);
		auto xml = new DocumentParser(xmlData);

		xml.onStartTag["versions"] = (ElementParser xml) {
			 xml.onEndTag["version"] = (in Element e) {
				json["versions"] ~= serializeToJson(["name": packageId, "version": e.text]);
			 };
			 xml.parse();
		};
		xml.parse();
		m_metadataCache[packageId] = CacheEntry(json, now);
		return json;
	}

	SearchResult[] searchPackages(string query)
	{
		return [];
	}
}
