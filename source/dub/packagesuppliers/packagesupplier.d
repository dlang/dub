module dub.packagesuppliers.packagesupplier;

public import dub.dependency : Dependency, Version;
public import dub.internal.vibecompat.core.file : NativePath;
public import dub.internal.vibecompat.data.json : Json;

import dub.recipe.packagerecipe : PackageRecipe;
import std.typecons : Nullable;

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
	Nullable!PackageRecipe fetchPackageRecipe(string package_id, Dependency dep, bool pre_release);

	/** Searches for packages matching the given search query term.

		Search queries are currently a simple list of words separated by
		white space. Results will get ordered from best match to worst.
	*/
	SearchResult[] searchPackages(string query);
}

struct Metadata {
	PackageRecipe[] versions;
	static auto fromJson(Json json)
	{
		PackageRecipe[] versions;
		foreach (ver; json["versions"]) {
			import dub.recipe.json : parseJson;
			PackageRecipe recipe;
			parseJson(recipe, ver, null);
			versions ~= recipe;
		}
		return Metadata(versions);
	}
}

// TODO: Could drop the "best package" behavior and let retrievePackage/
//       getPackageDescription take a Version instead of Dependency. But note
//       this means that two requests to the registry are necessary to retrieve
//       a package recipe instead of one (first get version list, then the
//       package recipe)

package Nullable!PackageRecipe getBestPackage(Nullable!Metadata metadata, string packageId, Dependency dep, bool pre_release)
{
	if (metadata.isNull)
		return typeof(return).init;

	auto best = getBestPackage(metadata.get, packageId, dep, pre_release);
	return typeof(return)(best);
}

package PackageRecipe getBestPackage(Metadata metadata, string packageId, Dependency dep, bool pre_release)
{
	import std.exception : enforce;
	Nullable!PackageRecipe best;
	Version bestver;
	foreach (recipe; metadata.versions) {
		auto cur = Version(recipe.version_);
		if (!dep.matches(cur)) continue;
		if (best.isNull) best = recipe;
		else if (pre_release) {
			if (cur > bestver) best = recipe;
		} else if (bestver.isPreRelease) {
			if (!cur.isPreRelease || cur > bestver) best = recipe;
		} else if (!cur.isPreRelease && cur > bestver) best = recipe;
		bestver = Version(best.get.version_);
	}
	enforce(!best.isNull, "No package candidate found for "~packageId~" "~dep.toString());
	return best.get;
}
