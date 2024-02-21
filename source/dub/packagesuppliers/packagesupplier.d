module dub.packagesuppliers.packagesupplier;

public import dub.dependency : PackageName, Dependency, Version, VersionRange;
import dub.dependency : visit;
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
	deprecated("Use `getVersions(PackageName)` instead")
	final Version[] getVersions(string name)
	{
		return this.getVersions(PackageName(name));
	}

	Version[] getVersions(in PackageName name);


	/** Downloads a package and returns its binary content

		Params:
			name = Name of the package to retrieve
			dep = Version constraint to match against
			pre_release = If true, matches the latest pre-release version.
				Otherwise prefers stable versions.
	*/
	ubyte[] fetchPackage(in PackageName name, in VersionRange dep,
		bool pre_release);

	deprecated("Use `writeFile(path, fetchPackage(PackageName, VersionRange, bool))` instead")
	final void fetchPackage(in NativePath path, in PackageName name,
		in VersionRange dep, bool pre_release)
	{
		import dub.internal.vibecompat.core.file : writeFile;
		if (auto res = this.fetchPackage(name, dep, pre_release))
			writeFile(path, res);
	}

    deprecated("Use `fetchPackage(NativePath, PackageName, VersionRange, bool)` instead")
	final void fetchPackage(NativePath path, string name, Dependency dep, bool pre_release)
    {
        return dep.visit!(
            (const VersionRange rng) {
                return this.fetchPackage(path, PackageName(name), rng, pre_release);
            }, (any) {
                assert(0, "Trying to fetch a package with a non-version dependency: " ~ any.toString());
            },
        );
    }

	/** Retrieves only the recipe of a particular package.

		Params:
			package_id = Name of the package of which to retrieve the recipe
			dep = Version constraint to match against
			pre_release = If true, matches the latest pre-release version.
				Otherwise prefers stable versions.
	*/
	Json fetchPackageRecipe(in PackageName name, in VersionRange dep, bool pre_release);

    deprecated("Use `fetchPackageRecipe(PackageName, VersionRange, bool)` instead")
	final Json fetchPackageRecipe(string name, Dependency dep, bool pre_release)
    {
        return dep.visit!(
            (const VersionRange rng) {
                return this.fetchPackageRecipe(PackageName(name), rng, pre_release);
            }, (any) {
                return Json.init;
            },
        );
    }

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

package Json getBestPackage(Json metadata, in PackageName name,
	in VersionRange dep, bool pre_release)
{
	import std.exception : enforce;
	import std.format : format;

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
	enforce(best != null,
		"No package candidate found for %s@%s".format(name.main, dep));
	return best;
}
