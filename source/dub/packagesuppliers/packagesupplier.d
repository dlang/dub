module dub.packagesuppliers.packagesupplier;

public import dub.dependency : Dependency, Version;
public import dub.internal.vibecompat.core.file : NativePath;
public import dub.internal.vibecompat.data.json : Json;

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
			dep = Version constraint to match against
			pre_release = If true, matches the latest pre-release version.
				Otherwise prefers stable versions.
	*/
	void fetchPackage(NativePath path, string package_id, Dependency dep, bool pre_release);

	/** Retrieves only the recipe of a particular package.

		Params:
			package_id = Name of the package of which to retrieve the recipe
			dep = Version constraint to match against
			pre_release = If true, matches the latest pre-release version.
				Otherwise prefers stable versions.
	*/
	Json fetchPackageRecipe(string package_id, Dependency dep, bool pre_release);

	/** Searches for packages matching the given search query term.

		Search queries are currently a simple list of words separated by
		white space. Results will get ordered from best match to worst.
	*/
	SearchResult[] searchPackages(string query);
}

// TODO: Could drop the "best package" behavior and let retrievePackage/
//       getPackageDescription take a Version instead of Dependency. But note
//       this means that two requests to the registry are necessary to retrieve
//       a package recipe instead of one (first get version list, then the
//       package recipe)

package Json getBestPackage(Json metadata, string packageId, Dependency dep, bool pre_release)
{
	import std.exception : enforce;
	if (metadata.type == Json.Type.null_)
		return metadata;
	Json best = null;
	Version bestver;
	foreach (json; metadata["versions"]) {
		auto cur = Version(json["version"].get!string);
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
