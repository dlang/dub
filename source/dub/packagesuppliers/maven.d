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
	import dub.recipe.packagerecipe : PackageRecipe;

	import std.datetime : Clock, Duration, hours, SysTime, UTC;
	import std.typecons : Nullable;

	private {
		enum httpTimeout = 16;
		URL m_mavenUrl;
		struct CacheEntry { Metadata data; SysTime cacheTime; }
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
		if (md.isNull)
			return [];
		Version[] ret;
		foreach (recipe; md.get.versions) {
			auto cur = Version(recipe.version_);
			ret ~= cur;
		}
		ret.sort();
		return ret;
	}

	void fetchPackage(NativePath path, string packageId, Dependency dep, bool pre_release)
	{
		import std.format : format;
		auto md = getMetadata(packageId);
		auto best = getBestPackage(md, packageId, dep, pre_release);
		if (best.isNull)
			return;
		auto vers = best.get.version_;
		auto url = m_mavenUrl~NativePath("%s/%s/%s-%s.zip".format(packageId, vers, packageId, vers));

		try {
			retryDownload(url, path, 3, httpTimeout);
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

	Nullable!PackageRecipe fetchPackageRecipe(string packageId, Dependency dep, bool pre_release)
	{
		auto md = getMetadata(packageId);
		return getBestPackage(md, packageId, dep, pre_release);
	}

	private Nullable!Metadata getMetadata(string packageId)
	{
		import dub.internal.undead.xml;

		auto now = Clock.currTime(UTC());
		if (auto pentry = packageId in m_metadataCache) {
			if (pentry.cacheTime + m_maxCacheTime > now)
				return typeof(return)(pentry.data);
			m_metadataCache.remove(packageId);
		}

		auto url = m_mavenUrl~NativePath(packageId~"/maven-metadata.xml");

		logDebug("Downloading maven metadata for %s", packageId);
		string xmlData;

		try
			xmlData = cast(string)retryDownload(url, 3, httpTimeout);
		catch(HTTPStatusException e) {
			if (e.status == 404) {
				logDebug("Maven metadata %s not found at %s (404): %s", packageId, description, e.msg);
				return typeof(return).init;
			}
			else throw e;
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

		auto entry = CacheEntry(Metadata.fromJson(json), now);
		m_metadataCache[packageId] = entry;
		return typeof(return)(entry.data);
	}

	SearchResult[] searchPackages(string query)
	{
		// Only exact search is supported
		// This enables retrival of dub packages on dub run
		auto md = getMetadata(query);
		auto recipe = getBestPackage(md, query, Dependency.any, true);
		if (recipe.isNull)
			return null;
		return [SearchResult(recipe.get.name, "", recipe.get.version_)];
	}
}
