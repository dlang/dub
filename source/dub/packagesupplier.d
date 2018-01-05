/**
	Contains (remote) package supplier interface and implementations.

	Copyright: © 2012-2013 Matthias Dondorff, 2012-2016 Sönke Ludwig
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
import std.typecons : AutoImplement;
import std.zip;

// TODO: Could drop the "best package" behavior and let retrievePackage/
//       getPackageDescription take a Version instead of Dependency. But note
//       this means that two requests to the registry are necessary to retrieve
//       a package recipe instead of one (first get version list, then the
//       package recipe)

/**
	Base interface for remote package suppliers.

	Provides functionality necessary to query package versions, recipes and
	contents.
*/
interface PackageSupplier {
	/// Represents a single package search result.
	static struct SearchResult { string name, description, version_; }

	/// Returns a human-readable representation of the package supplier.
	@property string description();

	/** Retrieves a list of all available versions(/branches) of a package.

		Throws: Throws an exception if the package name is not known, or if
			an error occurred while retrieving the version list.
	*/
	Version[] getVersions(string package_id);

	/** Downloads a package and stores it as a ZIP file.

		Params:
			path = Absolute path of the target ZIP file
			package_id = Name of the package to retrieve
			dep: Version constraint to match against
			pre_release: If true, matches the latest pre-release version.
				Otherwise prefers stable versions.
	*/
	void fetchPackage(NativePath path, string package_id, Dependency dep, bool pre_release);

	/** Retrieves only the recipe of a particular package.

		Params:
			package_id = Name of the package of which to retrieve the recipe
			dep: Version constraint to match against
			pre_release: If true, matches the latest pre-release version.
				Otherwise prefers stable versions.
	*/
	Json fetchPackageRecipe(string package_id, Dependency dep, bool pre_release);

	/** Searches for packages matching the given search query term.

		Search queries are currently a simple list of words separated by
		white space. Results will get ordered from best match to worst.
	*/
	SearchResult[] searchPackages(string query);
}


/**
	File system based package supplier.

	This package supplier searches a certain directory for files with names of
	the form "[package name]-[version].zip".
*/
class FileSystemPackageSupplier : PackageSupplier {
	private {
		NativePath m_path;
	}

	this(NativePath root) { m_path = root; }

	override @property string description() { return "file repository at "~m_path.toNativeString(); }

	Version[] getVersions(string package_id)
	{
		Version[] ret;
		foreach (DirEntry d; dirEntries(m_path.toNativeString(), package_id~"*", SpanMode.shallow)) {
			NativePath p = NativePath(d.name);
			logDebug("Entry: %s", p);
			enforce(to!string(p.head)[$-4..$] == ".zip");
			auto vers = p.head.toString()[package_id.length+1..$-4];
			logDebug("Version: %s", vers);
			ret ~= Version(vers);
		}
		ret.sort();
		return ret;
	}

	void fetchPackage(NativePath path, string packageId, Dependency dep, bool pre_release)
	{
		enforce(path.absolute);
		logInfo("Storing package '"~packageId~"', version requirements: %s", dep);
		auto filename = bestPackageFile(packageId, dep, pre_release);
		enforce(existsFile(filename));
		copyFile(filename, path);
	}

	Json fetchPackageRecipe(string packageId, Dependency dep, bool pre_release)
	{
		auto filename = bestPackageFile(packageId, dep, pre_release);
		return jsonFromZip(filename, "dub.json");
	}

	SearchResult[] searchPackages(string query)
	{
		// TODO!
		return null;
	}

	private NativePath bestPackageFile(string packageId, Dependency dep, bool pre_release)
	{
		NativePath toPath(Version ver) {
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


/**
	Online registry based package supplier.

	This package supplier connects to an online registry (e.g.
	$(LINK https://code.dlang.org/)) to search for available packages.
*/
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
		Json best = getBestPackage(packageId, dep, pre_release);
		if (best.type == Json.Type.null_)
			return;
		auto vers = best["version"].get!string;
		auto url = m_registryUrl ~ NativePath(PackagesPath~"/"~packageId~"/"~vers~".zip");
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
		return getBestPackage(packageId, dep, pre_release);
	}

	private Json getMetadata(string packageId)
	{
		auto now = Clock.currTime(UTC());
		if (auto pentry = packageId in m_metadataCache) {
			if (pentry.cacheTime + m_maxCacheTime > now)
				return pentry.data;
			m_metadataCache.remove(packageId);
		}

		auto url = m_registryUrl ~ NativePath(PackagesPath ~ "/" ~ packageId ~ ".json");

		logDebug("Downloading metadata for %s", packageId);
		logDebug("Getting from %s", url);

		string jsonData;
		foreach(i; 0..3) {
			try {
				jsonData = cast(string)download(url);
				break;
			}
			catch (HTTPStatusException e)
			{
				if (e.status == 404) {
					logDebug("Package %s not found at %s (404): %s", packageId, description, e.msg);
					return Json(null);
				}
				else {
					logDebug("Error getting metadata for package %s at %s (attempt %s of 3): %s", packageId, description, i + 1, e.msg);
					if (i == 2)
						throw e;
					continue;
				}
			}
		}
		Json json = parseJsonString(jsonData, url.toString());
		// strip readme data (to save size and time)
		foreach (ref v; json["versions"])
			v.remove("readme");
		m_metadataCache[packageId] = CacheEntry(json, now);
		return json;
	}

	SearchResult[] searchPackages(string query) {
		import std.uri : encodeComponent;
		auto url = m_registryUrl;
		url.localURI = "/api/packages/search?q="~encodeComponent(query);
		string data;
		data = cast(string)download(url);
		import std.algorithm : map;
		return data.parseJson.opt!(Json[])
			.map!(j => SearchResult(j["name"].opt!string, j["description"].opt!string, j["version"].opt!string))
			.array;
	}

	private Json getBestPackage(string packageId, Dependency dep, bool pre_release)
	{
		Json md = getMetadata(packageId);
		if (md.type == Json.Type.null_)
			return md;
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

package abstract class AbstractFallbackPackageSupplier : PackageSupplier
{
	protected PackageSupplier m_default;
	protected PackageSupplier[] m_fallbacks;

	this(PackageSupplier default_, PackageSupplier[] fallbacks)
	{
		m_default = default_;
		m_fallbacks = fallbacks;
	}

	override @property string description()
	{
		import std.algorithm : map;
		return format("%s (fallback %s)", m_default.description, m_fallbacks.map!(x => x.description));
	}

	// Workaround https://issues.dlang.org/show_bug.cgi?id=2525
	abstract override Version[] getVersions(string package_id);
	abstract override void fetchPackage(NativePath path, string package_id, Dependency dep, bool pre_release);
	abstract override Json fetchPackageRecipe(string package_id, Dependency dep, bool pre_release);
	abstract override SearchResult[] searchPackages(string query);
}

/**
	Combines two package suppliers and uses the second as fallback to handle failures.

	Assumes that both registries serve the same packages (--mirror).
*/
package alias FallbackPackageSupplier = AutoImplement!(AbstractFallbackPackageSupplier, fallback);

private template fallback(T, alias func)
{
	enum fallback = q{
		import std.range : back, dropBackOne;
		import dub.internal.vibecompat.core.log : logDebug;
		scope (failure)
		{
			foreach (m_fallback; m_fallbacks.dropBackOne)
			{
				try
					return m_fallback.%1$s(args);
				catch(Exception)
					logDebug("Package supplier %s failed. Trying next fallback.", m_fallback);
			}
			return m_fallbacks.back.%1$s(args);
		}
		return m_default.%1$s(args);
	}.format(__traits(identifier, func));
}

private enum PackagesPath = "packages";
