/*******************************************************************************

    Types and functions to interface with the GitLab API to generate an index
    entry

    As a lot of code for the GitLab API can be abstracted away to use a similar
    logic as the GitHub API, this only implements the clients.

    See_Also:
      https://docs.gitlab.com/api/rest/

*******************************************************************************/

module dub.index.gitlab;

import dub.index.client;
import dub.index.data;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.path;
import dub.internal.vibecompat.inet.url;
import dub.internal.vibecompat.inet.urlencode;
import dub.package_;
import dub.recipe.io;
import dub.recipe.packagerecipe;

import std.algorithm;
import std.array;
import std.exception;
import std.format;
import std.typecons;

/**
 * Base client to interact with GitLab API
 */
public class GitLabClient : APIClient {
    /**
     * Construct an instance of a GitLab client
     *
     * Params:
     *   token = Optional token to use to authenticate requests.
     *   url   = URL of the GitLab API to use, defaults to gitlab.com's
     */
    public this (string token = null, string url = `https://gitlab.com/api/v4/`) {
        // TODO: Token support
        super(URL(url), token);
    }

    /**
     * Scoped client for project-specific interaction
     *
     * This should be used via:
     * ```
     * scope client = new GitLabClient();
     * scope repo = client.new Project("dlang", "dub");
     * // Now get information on repository at https://gitlab.com/dlang/dub
     * ```
     */
    public class Project : RepositoryClient {
        /// Path to the project
        private InetPath path;

        /**
         * Construct an instance of this object
         */
        public this (string owner, string project) @safe {
            this.path = InetPath("projects") ~ urlEncode(
                (InetPath(owner) ~ project).toString());
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
         *   https://docs.gitlab.com/api/tags/
         */
        public override RequestResult!(TagDescription[]) getTags (CacheInfo cache) {
            static TagDescription[] jsonToTag (Json[] data) {
                return data.map!(t =>
                    TagDescription(t["name"].opt!string, t["commit"]["id"].opt!string))
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

            auto res = this.outer.get(this.path ~ "repository" ~ "tags", cache);
            if (res.notModified) return res.convert!(TagDescription[])(null);
            return res.convert(jsonToTag(res.result.opt!(Json[])) ~ getTagsInternal(res.next));
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
         *   https://docs.gitlab.com/api/repositories/#list-repository-tree
         */
        public RequestResult!Json findRecipeSummary (string reference, CacheInfo cache,
            InetPath where) {

            // We are either looking up the root directory or a subdirectory
            // (for subpackages), in both cases we get the directory content.
            if (where.absolute) {
                auto segments = where.bySegment();
                segments.popFront();
                where = InetPath(segments);
                assert(!where.absolute);
            }

            scope res = this.outer.get(
                (this.path ~ "repository" ~ "tree").normalized(),
                cache, "ref=%s&path=%s".format(urlEncode(reference),
                    urlEncode(where.empty ? "/" : where.toString())));
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
        public override RequestResult!PackageRecipe findRecipe (ref InetPath path,
            string reference, CacheInfo cache) {
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

            const wh = urlEncode(path.toString());
            scope res = this.outer.get((this.path ~ "repository" ~ "files" ~ wh).normalized(),
                cache, "ref=" ~ urlEncode(reference));
            if (res.notModified)
                return res.convert(PackageRecipe.init);
            // Only support recipe files up to 1 Mb. Fair ?
            const size = res.result["size"].opt!uint;
            enforce(size < 1_000_000,
                "Recipe file size is over 1 Megabyte: %s bytes".format(size));
            ubyte[] buffer = new ubyte[size];
            const str = cast(string) Base64.decode(res.result["content"].opt!string, buffer);
            validate(str);
            return res.convert(parsePackageRecipe(str, path.toString()));
        }
    }
}
