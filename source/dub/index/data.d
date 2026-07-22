/*******************************************************************************

    Defines the configuration file format for Dub's index

    The index is a replacement for the registry that relies entirely on the
    state of a Git repository, using a similar approach as Nix packages, Rust's
    cargo, and Homebrew.

    As Dub needs data that would otherwise force users to duplicate the content
    of their recipe file, leading to sub-par experience, the package
    registration process is simply to add a description for the package in
    a configuration file, that is then processed by a special dub command to
    generate the index. This also allows us to extend the index in the future
    to support more data.

    This module contains type definitions for both the index file and the
    processed data types. All processed types start with `Indexed` to
    differentiate them.

*******************************************************************************/

module dub.index.data;

import dub.dependency;
import dub.internal.configy.attributes;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.path;
import dub.recipe.packagerecipe;

/**
 * Top level configuration for package index
 *
 * The source of truth for all packages registered with the Dub registry.
 * Each entry is a package description that gets processed by `dub index`
 * subcommands.
 */
public struct PackageList {
    public @Key(`name`) PackageEntry[] packages;
}

/**
 * A user-supplied description of a package, to be processed by `dub index`.
 */
public struct PackageEntry {
    /// Short-hand name of the package
    public MainPackageName name;
    /// The location of the package - e.g. Github or GitLab
    public PackageSource source;
    /// The list of version ranges to be indexed - if not provided, everything
    public VersionRange[] included = [ VersionRange.Any ];
    /// The list of version ranges to be excluded - if not provided, nothing
    public @Optional VersionRange[] excluded;
}

/**
 * A struct to do validation on main package name
 */
public struct MainPackageName {
    public string value;
    alias value this;

    public static MainPackageName fromConfig (scope ConfigParser parser) {
        import std.algorithm : all;
        import std.ascii : isASCII;
        import std.exception : enforce;

        if (scope sc = parser.node.asScalar) {
            const str = sc.str;
            enforce(str.length, "Empty package name");
            enforce(str.all!isASCII, "Package names need to be ASCII only");
            enforce(str[0] != ':', "Cannot register sub-package, use main package name instead");
            const name = PackageName(str);
            enforce(!name.sub.length, "Sub-packages are automatically registered, register main package name only");
            string mainName = name.main.toString(); // Work around dumb DIP1000 error
            return MainPackageName(mainName);
        }
        throw new Exception("Expected node to be a scalar");
    }
}

/**
 * The source from which an indexed package is fetched
 *
 * Packages can come from different sources. The most common ones
 * are Github and GitLab, and other providers may be added.
 */
public struct PackageSource {
    public Only!([`github`, `gitlab`, `bitbucket`]) kind;
    public string owner;
    public string project;

    /// JSON serialization for `kind`
    public Json toJson () const @safe {
        Json res = Json.emptyObject;
        res["kind"] = this.kind.value;
        res["owner"] = this.owner;
        res["project"] = this.project;
        return res;
    }

    // Required for `toJson` not to be ignored
    static PackageSource fromJson (Json src) @safe { assert(0); }
}

/**
 * A processed package description
 *
 * This describe a single package and is programmatically generated
 * by `dub index generate`.
 */
public struct IndexedPackage (uint vers) {
    /// Version of this index
    public @Name(`version`) version_ = vers;
    /// Copied verbatim from the index
    public string name;
    /// Description of the package
    public string description;
    /// Source of the package
    public PackageSource source;
    /// All known versions, sorted from most recent
    public IndexedPackageVersion[] versions;
    /// The cache information for the repository
    ///
    /// This is used to avoid needless refresh
    public @Optional CacheInfo cache;
}

public struct IndexedPackageVersion {
    /// The version this represent
    public @Name(`version`) Version version_;

    /**
     * Description of all sub-package.
     *
     * The first entry is always the main package.
     */
    public IndexedSubpackage[] subs;

    /**
     * Git commit SHA-1 corresponding to this version
     *
     * This may be empty, and is only used for caching so far.
     */
    public @Optional string commit;
}

public struct IndexedSubpackage {
    /// Name of this sub-package
    public string name;
    /**
     * A stripped down copy of the package's configuration.
     *
     * Currently only used for the `dependencies`.
     */
    public ConfigurationInfo[] configurations;

    /**
     * Cache information for this version
     *
     * This is used to avoid needless refresh. The cache instance will
     * be empty for subpackages that do not have their own package file,
     * such as inline subpackages. Subpackages being specified by `path`,
     * and the main package, will have this filled.
     */
    public @Optional CacheInfo cache;

    /// If this is a path-based subpackage, the path at which this subpackage is
    public @Optional InetPath path;

    /// JSON serialization for configurations
    public Json toJson () const @safe {
        import std.algorithm;
        import std.range;

        Json res = Json.emptyObject;
        res["name"] = this.name;
        if (!this.path.empty)
            res["path"] = this.path.toString();
        if (this.cache !is CacheInfo.init) {
            res["cache"] = Json.emptyObject;
            if (this.cache.etag.length)
                res["cache"]["etag"] = this.cache.etag;
            if (this.cache.last_modified.length)
                res["cache"]["last_modified"] = this.cache.last_modified;
        }
        if (!this.configurations.length) return res;

        Json[] cf = iota(this.configurations.length).map!(_ => Json.emptyObject).array;
        foreach (idx, ref conf; this.configurations) {
            cf[idx]["name"] = conf.name;
            if (conf.platforms.length)
                cf[idx]["platforms"] = serializeToJson(conf.platforms);
            if (conf.dependencies.data.length) {
                cf[idx]["dependencies"] = Json.emptyObject;
                foreach (key, value; conf.dependencies.data)
                    cf[idx]["dependencies"][key] = serializeToJson(value.dependency);
            }
        }
        res["configurations"] = cf;
        return res;
    }

    // Required for `toJson` not to be ignored
    static IndexedSubpackage fromJson (Json src) @safe { assert(0); }
}

/**
 * Utility struct used for caching
 *
 * Note that this can be used for files accross versions, as if the recipe file
 * does not change across versions, we will get a hit and can further reduce
 * the number of requests we emit.
 *
 * Note that the ETag differ between unauthenticated requests and authenticated
 * requests. TODO: Do they also differ depending on the user ?
 * Finally, unauthenticated conditional requests still count towards rate
 * limiting (for fully cached packages, we only issue 1 request).
 *
 * See_Also:
 * https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api?apiVersion=2022-11-28#use-conditional-requests-if-appropriate
 */
public struct CacheInfo {
    /// Etags returned by the request (may be null)
    public @Optional string etag;

    /// Last modified returned by the request (may be null)
    public @Optional string last_modified;
}
