/*******************************************************************************

    Types and functions to interface with the Github API to generate an index
    entry

    See_Also:
      https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api

*******************************************************************************/

module dub.index.github;

import dub.dependency;
import dub.index.client;
import dub.index.data;
import dub.index.utils;
import dub.internal.utils;
import dub.internal.logging;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.path;
import dub.internal.vibecompat.inet.url;
import dub.internal.vibecompat.inet.urlencode;
import dub.package_ : packageInfoFiles;
import dub.recipe.io;
import dub.recipe.packagerecipe;

import std.algorithm;
import std.exception;
import std.format;
import std.range;
import std.typecons;

/**
 * Using the Github API, generate a package description matching this package
 *
 * We try to cache things as much as possible to reduce the number of requests
 * counting towards our rate limit. There are a few ways we do this:
 * - As the tags are ordered from most to least recent, if getting the first
 *   page of tags is a cache hit, then we don't need to do anything
 * - If the tag list have changed, it's possible (likely even) that most tags
 *   are already known to us. If we have an existing cache, we compare to that
 *   as much as possible, using the `commit` for versions, and the `cache`
 *   for versions and subpackages;
 * - In many instances, the recipe do not change across tags, only the code.
 *   To improve caching, when there is no existing index, we use the cache
 *   (etag) of the most recent version when querying the recipe file so that
 *   we may get a hit.
 *
 * There are a couple pitfalls that hinder caching:
 * - We cannot cache what recipe file is being used by the package, as things
 *   would then break if a package is currently using `dub.json` but was
 *   previously using `dub.sdl` (or the other way around). Hence we always need
 *   to do a request content (and only one) to the contents endpoint.
 * - subpackages may be inline, but are likely to be using a path, hence for
 *   each package with path subpackages, we will need to query them even if
 *   there is a cache miss - as a version could have a change to one of the
 *   subpackage but not the main package.
 *
 * We use a similar caching strategy for subpackages (closest version).
 *
 * Params:
 *   gh = The Github client, used to make requests to the API
 *   pkg = The package entry as can be found in the index file
 *   existing = The existing entry for this package in the built index.
 *              This is used to avoid making too many requests to Github.
 *              If `null`, the package will be processed as if it was new.
 *
 * Returns:
 *   A completed / filled `IndexedPackage!0` describing the cached index entry
 *   for this package.
 *
 * Throws:
 *   If an error happened, e.g. the package is dead, the rate limit was reached,
 *   etc...
 */
public IndexedPackage!0 updateDescription (scope RepositoryClient client,
    in PackageEntry pkg, Nullable!(IndexedPackage!0) existing) {

    // In this function we refer to two different sources for cache:
    // 1) the existing version, which is what we currently have in the cache
    // 2) the previous version, which is the closest version, if any

    // Category: Tags ?
    // Popularity: Forks, stars;
    // Need last commit to establish which are the most active;

    const hasExisting = !existing.isNull();
    auto tags = client.getTags(hasExisting ? existing.get().cache : CacheInfo.init);
    if (tags.notModified) {
        const cache = existing.get().cache; // Frontend bug if inline below
        logInfo("[%s] Package was not modified (%s, %s)", pkg.name, cache.etag, cache.last_modified);
        return existing.get();
    }
    if (hasExisting)
        logInfo("[%s] Found %s tags (already cached: %s entries)", pkg.name,
            tags.result.length, existing.get().versions.length);
    else
        logInfo("[%s] Found %s tags (no cached entry exists)", pkg.name,
            tags.result.length);

    typeof(return) result;
    result.name = pkg.name;
    result.source = pkg.source;
    result.cache = tags.cache;

    foreach (tidx, tag; tags.result) {
        logInfo("[%s] Processing tag %s (%s/%s)", pkg.name, tag.name, tidx, tags.result.length);
        if (!isTagIncluded(pkg, tag.name)) {
            logInfo("[%s] Skipping tag %s", pkg.name, tag.name);
            continue;
        }

        // Then make sure there is not an already cached version of this tag
        // If a repository has new tags, we do not want to reprocess old tags
        // if they haven't changed.
        IndexedPackageVersion existingVersion = hasExisting ? existing.get().versions
            // There should always be at least one subs (the main), but better
            // safe than sorry in case someone messes with those files.
            // Note: Compare tags by string to avoid matching tags with metadata
            // with release ones.
            .filter!(ipv => ipv.version_.toString() == tag.name[1 .. $] && ipv.subs.length)
            // Default value in case this tag is not in `existing`
            .chain(only(IndexedPackageVersion.init)).front
            : IndexedPackageVersion.init;

        try
            result.versions ~= handleTag(client, pkg.name, tag,
                existingVersion, result.versions, result.description);
        catch (Exception exc)
            logError("[%s] Could not process tag '%s': %s", pkg.name, tag.name, exc.message());
    }
    // Fall back to the repository description if no version of the recipe
    // file contains one
    if (!result.description.length)
        result.description = client.getDescription(CacheInfo.init);

    return result;
}

/**
 * Handle a single tag
 *
 * This function is called once per tag to process. Any error will result
 * in the tag (and only this tag) being skipped.
 */
private IndexedPackageVersion handleTag (
    scope RepositoryClient client, string pkgname, TagDescription tag,
    IndexedPackageVersion existing, IndexedPackageVersion[] others,
    ref string description) {

    CacheInfo main_cache = existing.subs.length ?
        existing.subs[0].cache : CacheInfo.init;

    // Here we can simply check the commit - This is a more robust method
    // than relying on ETags as we would need to check ETags for all package
    // files (e.g. see unit-threaded or Vibe.d usage of subpackages).
    if (tag.commit == existing.commit) {
        logInfo("[%s] Tag %s was not modified: %s", pkgname, tag.name,
            existing.commit);
        return existing;
    }

    // If there was no match, use the CacheInfo of the closest version
    // If the recipe file hasn't changed between version, we'll get a match
    // We need to keep track where we got the cache from though.
    const bool hasExistingCache = main_cache !is CacheInfo.init;
    InetPath recipePath = hasExistingCache ? existing.subs[0].path
        : InetPath(`/`);
    if (!hasExistingCache && others.length) {
        main_cache = others[$ - 1].subs[0].cache;
        recipePath = others[$ - 1].subs[0].path;
    }

    auto recipeResult = client.findRecipe(recipePath, tag.name, main_cache);
    if (recipeResult.notModified) {
        if (hasExistingCache) {
            // We have an existing cache but the commit didn't match.
            // Perhaps the version was re-tagged on a different commit with
            // the same recipe.
            logWarn("[%s][%s] Cache match without commit match - The version was re-tagged?",
                pkgname, tag.name);
            logWarn("[%s][%s] Throwing away cache and processing anew...", pkgname, tag.name);
            return handleTag(client, pkgname, tag, IndexedPackageVersion.init, others, description);
        }
        // We don't have an *existing* cache, but we have a *previous* one
        assert(others.length, "Cache matched a previous version without previous version");
        return handleTagFromPrevious(client, pkgname, tag, others[$ - 1], recipePath);
    }

    logInfo("[%s] Found new tag with new package: %s", pkgname, tag.name);
    auto recipe = recipeResult.result;
    enforce(recipe.subPackages.length < 200,
        "Package has too many subpackages: %s".format(recipe.subPackages.length));
    if (!description.length && recipe.description.length)
        description = recipe.description;

    auto subs = new IndexedSubpackage[1 + recipe.subPackages.length];
    subs[0] = makeSubR(null, recipeResult.cache, recipe, recipePath);
    foreach (spidx, ref subpkg; recipe.subPackages) {
        if (subpkg.path.length) {
            // TODO: Try to find previous subpackage instead
            // Might give us a path or a cache
            auto path = InetPath(subpkg.path);
            auto res = client.findRecipe(path, tag.name, CacheInfo.init);
            enforce(res.result.name.length, "No response for subpackage");
            subs[1 + spidx] = makeSubR(res.result.name, res.cache, res.result, path);
        } else {
            subs[1 + spidx] = makeSubR(subpkg.recipe.name, CacheInfo.init, subpkg.recipe, InetPath.init);
        }
    }
    return IndexedPackageVersion(Version(tag.name[1 .. $]), subs, tag.commit);
}

/**
 * Fetches data related to a tag taking into account a previous match
 *
 * In many instances, the recipe file does not change between versions.
 * We take advantage of this fact by using the previous version's ETag
 * when requesting a recipe to avoid needlessly fetching package recipe
 * (as well as subpackage's) and reduce our API use.
 */
private IndexedPackageVersion handleTagFromPrevious (scope RepositoryClient client,
    string pkgname, TagDescription tag, IndexedPackageVersion previous,
    InetPath recipePath) {
    logInfo("[%s] Found new tag '%s' with package matching '%s'",
        pkgname, tag.name, previous.version_);
    // A previous version matches - however if there are subpackages
    // files we also need to check them as they might have changed.
    auto subs = new IndexedSubpackage[previous.subs.length];
    subs[0] = previous.subs[0];
    // The path might be different though, but the client handles this
    subs[0].path = recipePath;
    foreach (spidx, ref subpkg; previous.subs[1 .. $]) {
        if (!subpkg.path.empty) {
            auto subPath = subpkg.path;
            auto res = client.findRecipe(subPath, tag.name, subpkg.cache);
            if (res.notModified) {
                logInfo("[%s][%s] Subpackage '%s' matches previous version '%s'",
                    pkgname, tag.name, subpkg.name, previous.version_);
                subs[1 + spidx] = subpkg;
            } else {
                logInfo("[%s][%s] Subpackage '%s' (%s) differs from previous version '%s' (%s)",
                    pkgname, tag.name, subpkg.name, subPath, previous.version_, subpkg.path);
                enforce(res.result.name.length, "No response for subpackage");
                subs[1 + spidx] = makeSubR(res.result.name, res.cache, res.result, subPath);
            }
        } else {
            logInfo("[%s][%s] Inline subpackage '%s' matches previous version '%s'",
                pkgname, tag.name, subpkg.name, previous.version_);
            subs[1 + spidx] = subpkg;
        }
    }
    return IndexedPackageVersion(Version(tag.name[1 .. $]), subs, tag.commit);
}

private IndexedSubpackage makeSubR (string name, in CacheInfo cache,
    ref PackageRecipe recipe, InetPath path) {
    return IndexedSubpackage(name,
        [ ConfigurationInfo(null, null, recipe.buildSettings) ] ~ recipe.configurations,
        cache, path);
}

/**
 * Base client to interact with Github API
 *
 * This client handles authentication, rate limiting, and caching.
 * As we had ~2500 packages at the time of writing (2025-04) and the API is
 * limited to 5000 requests / hour, with each package taking multiple requests,
 * we needed a smart way to do regular refresh of packages, which this client
 * handles by saving and comparing ETags for repositories.
 */
public class GithubClient : APIClient {
    /**
     * Construct an instance of a Github client
     *
     * Params:
     *   token = Optional token to use to authenticate requests.
     *           It's use is highly recommended as otherwise the rate limit is
     *           quite low (60 / hour instead of 5000 / hour).
     *   url   = URL of the Github API to use, defaults to api.github.com
     */
    public this (string token = null, string url = `https://api.github.com`) {
        super(URL(url), token);
    }

    /**
     * Scoped client for repository-specific interaction
     *
     * This should be used via:
     * ```
     * scope gh = new GithubClient();
     * scope repo = gh.new Repository("dlang", "dub");
     * // Now get information on repository at https://github.com/dlang/dub
     * ```
     */
    public class Repository : RepositoryClient {
        /// Path to the repository
        private InetPath path;
        /// Detailed tag data cache (or empty if not queried)
        private Json[string] allTags;

        /**
         * Construct an instance of this object
         */
        public this (string owner, string project) @safe {
            this.path = InetPath("repos/") ~ owner ~ project;
        }

        /**
         * Get the project description as filled in Github
         *
         * This can be used as a fallback if the recipe file does not
         * contain a description.
         */
        public override string getDescription (CacheInfo cache = CacheInfo.init) {
            return this.outer.get(this.path, cache).result["description"].opt!string;
        }

        /**
         * Get all the tags for this repository.
         *
         * Returns:
         *   A `null` `Nullable` if there was a cache hit, the list of tags
         *   otherwise.
         *
         * See_Also:
         * https://docs.github.com/en/rest/repos/repos?apiVersion=2022-11-28#list-repository-tags
         */
        public override RequestResult!(TagDescription[]) getTags (CacheInfo cache) {
            static TagDescription[] jsonToTag (Json[] data) {
                return data.map!(t =>
                    TagDescription(t["name"].opt!string, t["commit"]["sha"].opt!string))
                    .array;
            }

            TagDescription[] getTagsInternal (string url) {
                if (!url.length) return null;
                auto res = this.outer.get(URL(url));
                auto ret = jsonToTag(res.result.parseJson().opt!(Json[]));
                if (res.next.length)
                    return ret ~ getTagsInternal(res.next);
                return ret;
            }

            auto res = this.outer.get(this.path ~ "tags", cache, "per_page=100");
            if (res.notModified) return res.convert!(TagDescription[])(null);
            return res.convert(jsonToTag(res.result.opt!(Json[])) ~ getTagsInternal(res.next));
        }

        /**
         * Get data on a specific tag
         *
         * See_Also:
         * https://docs.github.com/en/rest/git/tags?apiVersion=2022-11-28#get-a-tag
         */
        public Json getTag (string name) {
            if (scope resp = name in this.allTags)
                return *resp;
            auto res = this.outer.get(this.path ~ "tags" ~ name, CacheInfo.init);
            this.allTags[name] = res.result;
            return res.result;
        }

        /**
         * Get a Json object describing the recipe file for this reference
         *
         * We do not know ahead of time what type of recipe file a project uses,
         * as it could be `dub.json`, `dub.sdl`, or even `package.json`.
         * This endpoint will iterate through the list and find the file that
         * dub would have picked, and returns the JSON API object describing it.
         * Of interest in that object are the property `download_url` (to get
         * the raw content), and `name` / `path`.
         *
         * Params:
         *   reference = The reference at which the file is looked up, e.g.
         *               `master` or a tag such as `v1.0.0`.
         *   cache = Cache information about this recipe file, if any.
         *   where = Where to look for a recipe file. Can be used to look up
         *           subpackages.
         *
         * Returns:
         *   Either a filled `RequestResult!Json` or one in the empty state if
         *   no recipe file was found.
         *
         * See_Also:
         *   https://docs.github.com/en/rest/repos/contents
         */
        public RequestResult!Json findRecipeSummary (
            string reference, CacheInfo cache, InetPath where) {

            // We are either looking up the root directory or a subdirectory
            // (for subpackages), in both cases we get the directory content.
            if (where.absolute) {
                auto segments = where.bySegment();
                segments.popFront();
                where = InetPath(segments);
                assert(!where.absolute);
            }

            scope res = this.outer.get((this.path ~ "contents/" ~ where).normalized(),
                cache, "ref=" ~ urlEncode(reference));
            if (res.notModified) return res.convert(Json.emptyObject);
            auto dir = res.result.opt!(Json[]);
            foreach (info; packageInfoFiles) {
                auto resrng = dir.find!(entry => entry["name"].opt!string == info.filename);
                if (!resrng.empty)
                    return res.convert(resrng.front);
            }
            return res.convert(Json.emptyObject);
        }

        /**
         * Get the deserialized `PackageRecipe`
         *
         * This finds the package recipe in the repository (by calling
         * `findRecipeSummary`), then fetches and deserialize it.
         *
         * Params:
         *   path = This can be either where to look for the package file,
         *          or if the path is to a package file itself (ends with one
         *          of the recognized package name), where to look it up.
         *          If the package file is not found, this will fall back
         *          to calling `findRecipeSummary`.
         *          If the  recipe path doesn't match, this value will be
         *          changed to match the actual path.
         *   reference = The reference at which the file is looked up, e.g.
         *               `master` or a tag such as `v1.0.0`.
         *   cache = Cache information about this recipe file, if any.
         */
        public override RequestResult!PackageRecipe findRecipe (
            ref InetPath path, string reference, CacheInfo cache) {
            auto localPath = path;
            if (!packageInfoFiles.filter!(pif => path.head == pif.filename).empty) {
                try
                    return this.getRecipe(path, reference, cache);
                catch (Exception exc)
                    localPath = path.hasParentPath() ? path.parentPath() : InetPath(`/`);
            }

            // We don't cache `findRecipeSummary`, and if we reached this branch
            // our caching information is useless anyway as we didn't have the
            // right path.
            auto res = this.findRecipeSummary(reference, CacheInfo.init, localPath);
            enforce(res.result != Json.emptyObject,
                "Could not find recipe file at '%s' in repository".format(path));
            path = InetPath(res.result["path"].opt!string);
            return this.getRecipe(path, reference, CacheInfo.init);
        }

        /**
         * Get a recipe at a specified `path`
         *
         * Fetches and deserializes the package recipe at `path`.
         *
         * Params:
         *   path = Path to the recipe to fetch
         *   reference = Git reference at which to fetch
         *   cache = Caching information
         *
         * Throws:
         *   If no recipe exists, or if an underlying error happens.
         */
        public RequestResult!PackageRecipe getRecipe (InetPath path, string reference,
            CacheInfo cache) {
            import std.base64;
            import std.string : lineSplitter;
            import std.utf;

            auto res = this.outer.get((this.path ~ "contents/" ~ path),
                cache, "ref=" ~ urlEncode(reference));
            if (res.notModified)
                return res.convert(PackageRecipe.init);
            // Only support recipe files up to 1 Mb. Fair ?
            const size = res.result["size"].opt!uint;
            enforce(size < 1_000_000,
                "Recipe file size is over 1 Megabyte: %s bytes".format(size));
            ubyte[] buffer = new ubyte[size];
            auto slice = buffer;
            foreach (line; res.result["content"].opt!string.lineSplitter) {
                const decoded = Base64.decode(line, slice);
                enforce(decoded.length <= slice.length, "Reading past end of buffer?");
                slice = slice[decoded.length .. $];
            }
            const str = cast(string) buffer[0 .. $ - slice.length];
            validate(str);
            return res.convert(parsePackageRecipe(str, path.toString()));
        }
    }
}
