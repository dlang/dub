/*******************************************************************************

    Index-based registry

    This implementation superseeds the legacy registry and queries Github
    directly for a well-known index that is cloned locally and always
    accessible. This ensures that our only dependency for fetching packages
    is Github, reducing the risk of downtime. This supplier also soft-fail when
    the network is not available, ensuring that users even offline can perform
    search if they have a checked out (but possibly outdated) index.

    As most use cases already know the package they are looking for, this index
    does not maintain an index, and `dub search` will simply open all package
    indices on the filesystem.

*******************************************************************************/

module dub.packagesuppliers.index;

import dub.dependency;
import dub.index.data;
import dub.index.utils;
import dub.internal.configy.easy;
import dub.internal.logging;
import dub.internal.utils;
import dub.internal.vibecompat.inet.path;
import dub.internal.vibecompat.inet.url;
import dub.packagesuppliers.packagesupplier;
import dub.recipe.packagerecipe;

import std.algorithm;
import std.array : array;
import std.exception;
static import std.file;
import std.format;
import std.range : retro;
import std.string;
import std.typecons;

/// Ditto
public class IndexPackageSupplier : PackageSupplier {
    /// The origin of the index - only used for initial checkout
    protected URL url;
    /// The path at which the index resides
    protected NativePath path;
    /// Whether git clone or git pull has been called during this program's
    /// lifetime (it is called at most once).
    protected bool initialized;

    /***************************************************************************

        Instantiate a new `IndexPackageSupplier`

        Params:
          path = The root path where the index is (to be) checked out

    ***************************************************************************/

    public this (URL url, NativePath path) @safe pure nothrow {
        this.url = url;
        this.path = path;
        this.path.endsWithSlash = true;
    }

    ///
	public override @property string description () {
        return "index-based registry (" ~ this.url.toString() ~ ` => ` ~
            this.path.toNativeString() ~ ")";
    }

    ///
	public override Version[] getVersions (in PackageName name) {
        this.ensureInitialized();
        const pkg = loadPackageDesc(this.path, name);
        return pkg.versions.map!(vers => Version(vers.version_.toString())).array;
    }

    /**
     * Fetch a package directly from the provider.
     *
     * See_Also:
     *   - https://docs.github.com/en/rest/repos/contents?apiVersion=2022-11-28#download-a-repository-archive-zip
     *   - https://docs.gitlab.com/api/repositories/
     *   - https://support.atlassian.com/bitbucket-cloud/kb/how-to-download-repositories-using-the-api/
     */
	public override ubyte[] fetchPackage (in PackageName name,
        in VersionRange dep, bool pre_release) {
        import dub.internal.git;
        import dub.internal.vibecompat.inet.urlencode;

        this.ensureInitialized();
        const pkgdesc = loadPackageDesc(this.path, name);
        auto vers = pkgdesc.bestMatch(dep);
        enforce(!vers.isNull(), "No package found matching dep");
        switch (pkgdesc.source.kind) {
            case "github":
                const url = "https://api.github.com/repos/%s/%s/zipball/%s".format(
                    pkgdesc.source.owner, pkgdesc.source.project, vers.get());
                return retryDownload(URL(url));
            case "gitlab":
                const url = "https://gitlab.com/api/v4/projects/%s/repository/archive.zip?sha=%s".format(
                    urlEncode((InetPath(pkgdesc.source.owner) ~ pkgdesc.source.project).toString()),
                    vers.get());
                return retryDownload(URL(url));
            case "bitbucket":
                const url = "https://bitbucket.org/%s/%s/get/%s.zip".format(
                    pkgdesc.source.owner, pkgdesc.source.project, vers.get());
                return retryDownload(URL(url));
            default:
                throw new Exception("Unhandled repository kind: " ~ pkgdesc.source.kind);
        }
    }

    ///
	public override Json fetchPackageRecipe(in PackageName name,
        in VersionRange dep, bool pre_release) {
        this.ensureInitialized();
        const pkgdesc = loadPackageDesc(this.path, name);
        const vers = pkgdesc.bestMatch(dep);
        enforce(!vers.isNull(),
            "Cannot fetch version '%s' of package '%s': No such version exists"
            .format(dep, name));
        // Note: Only 'version' is used from the return of 'fetchPackageRecipe'
        Json res;
        res["version"] = vers.get().version_.toString();
        return res;
    }

    /**
     * Search all packages matching the query
     *
     * Note that it is an expensive operation as it iterates over the whole
     * index locally. This is currently only called from `dub search` and
     * is unlikely to be called from any long-running processed so we're
     * not concerned about memory usage / speed (a couple seconds is fine).
     */
	public override SearchResult[] searchPackages (string query) {
        import std.path;

        static SearchResult addPackage (in IndexedPackage!0 idx) {
            auto maxVers = idx.bestMatch(VersionRange.Any);
            return SearchResult(idx.name, idx.description,
                !maxVers.isNull() ? maxVers.get().version_.toString() : null);
        }

        typeof(return) results;
        this.ensureInitialized();
        const origSound = query.soundexer();
        foreach (directory; std.file.dirEntries(this.path.toNativeString(), std.file.SpanMode.shallow)) {
            // Exclude any README, the .git directory / any dot files
            if (!directory.isDir()) continue;
            if (directory.baseName.length != 2) continue;
            foreach (entry; std.file.dirEntries(directory.name, std.file.SpanMode.breadth)) {
                if (!entry.isFile()) continue;
                try {
                    // D-YAML can't process some of the UTF-8 we might find in
                    // descriptions, so we use a pure JSON backend with no line
                    // information.
                    // See https://github.com/dlang-community/D-YAML/issues/342
                    const desc = parseConfigStringJSON!(IndexedPackage!0)(
                            std.file.readText(entry.name), entry.name);
                    if (!desc.versions.length) continue;
                    // Some heuristics
                    if (desc.name.canFind(query) || desc.description.canFind(query))
                        results ~= addPackage(desc);
                    else if (desc.name.soundexer == origSound)
                        results ~= addPackage(desc);
                } catch (ConfigException exc) {
                    logWarn("[%s] Internal error while reading package index: %S", entry.name, exc);
                    continue;
                }
                catch (Exception exc) {
                    logWarn("[%s] Internal error while reading package index: %s", entry.name, exc);
                    continue;
                }
            }
        }
        return results;
    }

    /**
     * Called by every method to ensure the index is available and up to date
     *
     * This method will hard fail if no index is available and the index cannot
     * be cloned, and soft-fail when the index cannot be updated.
     * It ensures that the index is updated at most once per program invocation.
     *
     * Returns:
     *   Whether this was the first call to `ensureInitialized`.
     *
     * Throws:
     *   If cloning the index failed.
     */
    public bool ensureInitialized () {
        import dub.internal.git;

        if (this.initialized) return false;
        scope (exit) this.initialized = true;

        if (!std.file.exists(this.path.toNativeString()))
            enforce(
                cloneRepository(this.url.toString(), "master", this.path),
                "Cloning the repository failed - ensure you have a working internet " ~
                "connection or use `--skip-registry`");
        else {
            updateRepository(this.path, "origin/HEAD");
        }
        return true;
    }
}
