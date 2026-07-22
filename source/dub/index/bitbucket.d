/*******************************************************************************

    Types and functions to interface with the Bitbucket API to generate an index
    entry

    See_Also:
      https://developer.atlassian.com/cloud/bitbucket/rest/intro/

*******************************************************************************/

module dub.index.bitbucket;

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
 * Client implementation for Bitbucket
 */
public class BitbucketClient : APIClient {
    /**
     * Construct an instance of this BitBucket client
     *
     * Params:
     *   url   = URL of the Bitbucket API to use, defaults to the cloud one
     */
    public this (string token = null, string url = `https://api.bitbucket.org/2.0/`) {
        super(URL(url), token);
    }

    /**
     * Scoped client for repository-specific interaction
     */
    public class Repository : RepositoryClient {
        /// Path to the repository
        private InetPath path;

        /**
         * Construct an instance of this object
         */
        public this (string owner, string project) @safe {
            this.path = InetPath("repositories/") ~ owner ~ project;
        }

        /// https://developer.atlassian.com/cloud/bitbucket/rest/api-group-repositories/#api-repositories-workspace-repo-slug-get
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
         * https://developer.atlassian.com/cloud/bitbucket/rest/api-group-refs/#api-repositories-workspace-repo-slug-refs-tags-get
         */
        public override RequestResult!(TagDescription[]) getTags (CacheInfo cache) {
            static TagDescription[] jsonToTag (Json[] data) {
                return data.filter!(t => t["target"]["type"].opt!string == "commit")
                    .map!(t => TagDescription(t["name"].opt!string, t["target"]["hash"].opt!string))
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

            auto res = this.outer.get(this.path ~ "refs" ~ "tags", cache);
            if (res.notModified) return res.convert!(TagDescription[])(null);
            return res.convert(jsonToTag(res.result["values"].opt!(Json[])) ~
                getTagsInternal(res.result["next"].opt!string));
        }

        /// Implementation of findRecipe
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
         * Get a PackageRecipe from Bitbucket
         *
         * Unlike Github or GitLab, Bitbucket returns the raw file by default.
         *
         * See_Also:
         *  https://developer.atlassian.com/cloud/bitbucket/rest/api-group-source/#api-repositories-workspace-repo-slug-src-commit-path-get
         */
        public RequestResult!PackageRecipe getRecipe (InetPath path, string reference,
            CacheInfo cache) {
            auto url = this.outer.url ~ (this.path ~ "src" ~ reference ~ path);
            auto res = this.outer.get(url, cache.etag, cache.last_modified);
            if (res.notModified)
                return res.convert(PackageRecipe.init);
            return res.convert(parsePackageRecipe(res.result.idup, path.toString()));
        }

        /**
         * Find a recipe in a directory
         */
        public RequestResult!Json findRecipeSummary (
            string reference, CacheInfo cache, InetPath where) {
            import std.path : baseName;

            if (where.absolute) {
                auto segments = where.bySegment();
                segments.popFront();
                where = InetPath(segments);
                assert(!where.absolute);
            }

            auto path = (this.path ~ "src" ~ reference ~ where);
            path.endsWithSlash = true;
            // TODO: We don't handle pagination here. Perhaps use Bitbucket
            // filtering language to make sure we get only the `dub` files ?
            scope res = this.outer.get(path, cache);
            if (res.notModified) return res.convert(Json.emptyObject);
            auto dir = res.result["values"].opt!(Json[]);
            foreach (info; packageInfoFiles) {
                auto resrng = dir.find!(entry => entry["path"].opt!string.baseName == info.filename);
                if (!resrng.empty)
                    return res.convert(resrng.front);
            }
            return res.convert(Json.emptyObject);
        }
    }
}
