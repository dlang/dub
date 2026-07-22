/*******************************************************************************

    Utility functions for dealing with the index

*******************************************************************************/

module dub.index.utils;

import dub.dependency;
import dub.index.data;
import dub.internal.vibecompat.inet.path;

import std.exception;
static import std.file;
import std.format;
import std.typecons;

/**
 * Loads a package description from the index.
 *
 * This attempts to load a package description from the index.
 * If no such description exists, an `Exception` is thrown.
 *
 * Params:
 *   path = The base path of the index
 *   name = The name of the package to load a description for.
 */
public IndexedPackage!0 loadPackageDesc (in NativePath path, in PackageName name) {
    import dub.internal.configy.easy;

    const file = getPackageDescriptionPath(path, name).toNativeString();
    enforce(std.file.exists(file), "No such package: %s".format(name));
    return parseConfigString!(typeof(return))(std.file.readText(file), file);
}

/**
 * Gets the path the package should be indexed at.
 *
 * The index use a simple system where the first two letters of the package,
 * and the last two letters reversed are used. So for package `configy`,
 * the path would be `$BASE/co/yg/configy`. For `dub`, `$BASE/du/bu/dub`.
 * This scheme is used as it gives slightly better distribution.
 *
 * Params:
 *   path = The base path of the index
 *   name = The name of the package to get the path for.
 *
 * Returns:
 *   The path at which the package description should be stored.
 */
public NativePath getPackageDescriptionPath (in NativePath path, in PackageName name) {
    import std.range;

    const main = name.main.toString();
    if (main.length < 2)
        return (path ~ main ~ main ~ main);

    immutable char[2] end = [ main[$-1], main[$-2] ];
    return (path ~ main[0 .. 2] ~ end[] ~ main);
}

/**
 * From a package description, find the version that best matches the range
 *
 * Params:
 *   pkg = The package description to look at
 *   dep = The expected version range to match
 *
 * Returns:
 *   The highest version matching `dep`, or `nullable()` if none does.
 */
public Nullable!(const(IndexedPackageVersion)) bestMatch (
    in IndexedPackage!0 pkg, in VersionRange dep) {
    size_t idx = pkg.versions.length;
    foreach (eidx, ref vers; pkg.versions) {
        // Is it a match ?
        if (dep.matches(vers.version_)) {
            if (idx < pkg.versions.length) {
                // Is it a better match ?
                if (pkg.versions[idx].version_ < vers.version_)
                    eidx = idx;
            } else {
                // We don't have a match yet
                eidx = idx;
            }
        }
    }
    return idx < pkg.versions.length ? nullable(pkg.versions[idx]) : typeof(return).init;
}

/**
 * Checks whether a version should be processed or not
 *
 * Returns:
 *   Whether the package should be included. If any error happen, including
 *   if the tag does not start with the prefix `v`, `false` is returned.
 */
package bool isTagIncluded (in PackageEntry pkg, string name) nothrow {
    import std.algorithm.searching : startsWith;

    if (!name.startsWith("v")) return false;
    try {
        auto vers = Version(name[1 .. $]);
        foreach (excl; pkg.excluded)
            if (excl.matches(vers))
                return false;
        foreach (incl; pkg.included)
            if (incl.matches(vers))
                return true;
        return false;
    } catch (Exception exc)
        return false;
}
