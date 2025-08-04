/*******************************************************************************

    Base class for API clients

    API clients need to be able to provide an authentication token, and to save
    rate limits. They use cURL under the hood. This exposes a base class for
    for them to use.

*******************************************************************************/

module dub.index.client;

import dub.index.data;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.path;
import dub.internal.vibecompat.inet.url;

import std.algorithm.searching;
import std.algorithm.iteration;
import std.array;
import std.conv;
import std.datetime;
import std.encoding : EncodingScheme;
import std.exception;
import std.format;
import std.net.curl;
import std.regex : matchAll;
import std.string : indexOf;
import std.typecons;
import std.uni;

/**
 * Base class that specific API derive from
 */
package class APIClient {
    /// The connection itself
    version (DubUseCurl) protected HTTP connection;
    /// Optional token to authenticate requests
    protected string token;
    /// URL of the GitLab API
    protected URL url;
    /// Rate limit informations from the last query
    protected RateLimit rate_limit;

    /**
     * Construct an instance of this client
     *
     * Params:
     *   url   = URL of the API to use.
     *   token = Optional token to use to authenticate requests.
     */
    public this (URL url, string token = null) {
        this.url   = url;
        this.token = token;
        version (DubUseCurl) {
            this.connection = HTTP(url.toString());
            import dub.internal.utils : setupHTTPClient;
            setupHTTPClient(this.connection, 8 /* seconds */);
        }
    }

    /**
     * Get the latest known rate limit
     *
     * The return of the function is the latest known rate-limit,
     * based on the last time a query was performed. If no query has been
     * performed, all values will be 0.
     */
    public RateLimit getRateLimit () const scope @safe pure nothrow @nogc {
        return this.rate_limit;
    }

    /**
     * Perform an HTTP GET request and returns the result as JSON
     *
     * This is a thin wrapper around the other `get` overload to return
     * Json, or an empty object if there is a cache match.
     *
     * Params:
     *   path = Path that is added to `this.url` to form the target
     *   cache = Optional cache information
     *   query = Optional query string
     *
     * Returns:
     *   A request result that is set to `Json.emptyObject` if there was
     *   a cache hit, or the data if the request was successful.
     *
     * Throws:
     *   As the other `get` overload (in case of error).
     */
    public RequestResult!Json get (InetPath path, CacheInfo cache, string query = null) {
        auto url = (this.url ~ path);
        url.normalize(path.endsWithSlash);
        url.queryString = query;
        auto res = this.get!char(url, cache.etag, cache.last_modified);
        return res.convert(res.notModified ? Json.emptyObject : res.result.parseJson());
    }

    /**
     * Perform an HTTP GET request and returns the result, using etags if possible
     *
     * This behaves similarly to `std.net.curl.get`, but in addition handles
     * authorization, Etag, and saves the rate limit values to `this.rate_limit`.
     *
     * Params:
     *   T = Encoding type, defaults to `char`, `ubyte` can also be used.
     *   url = The URL to request
     *   etag = Optional etag value to use for `if-none-match` value, allowing
     *          us to issue conditional requests which do not use up our API
     *          quota.
     *   last_modified = Used for caching via `if-modified-since` header.
     *                   If etag is also provided, both will be used,
     *                   however servers tend to prioritize etags.
     *
     * Returns:
     *   The resulting data, or null if a 304 was returned (cache hit).
     *
     * Throws:
     *   If status code different from 2xx or 304 is returned.
     */
    version (DubUseCurl)
    public RequestResult!(T[]) get (T = char) (URL url,
        string etag = null, string last_modified = null) {

        auto content = appender!(ubyte[])();
        HTTP.StatusLine statusLine;
        CacheInfo cache;
        string charset = "utf-8", next;

        if (this.token.length)
            this.connection.addRequestHeader("authorization", "Bearer " ~ token);
        if (etag.length)
            this.connection.addRequestHeader("if-none-match", etag);
        if (last_modified.length)
            this.connection.addRequestHeader("if-modified-since", last_modified);
        scope (exit) this.connection.clearRequestHeaders();

        this.connection.onReceiveHeader = (in char[] key, in char[] value) {
            // Required for things to work
            if (!icmp(key, "content-length"))
                content.reserve(value.to!size_t);
            else if (!icmp(key, "content-type")) {
                auto io = indexOf(value, "charset=", No.caseSensitive);
                if (io != -1)
                    charset = value[io + "charset=".length .. $].findSplit(";")[0].idup;
            }

            // Pagination
            else if (!icmp(key, "link")) {
                foreach (lnk; value.splitter(",")) {
                    auto matches = matchAll(lnk, `^\s*<([^>]*)>;\s*rel="(.*)"$`);
                    // If we have a match, first one is the whole string, then
                    // the URL, then the `rel`
                    if (matches.empty) continue;
                    if (matches.front.length != 3) continue;
                    if (matches.front[2] != "next") continue;
                    next = matches.front[1].idup;
                    break;
                }
            }

            // Caching
            else if (!icmp(key, "etag"))
                cache.etag = value.idup;
            else if (!icmp(key, "last-modified"))
                cache.last_modified = value.idup;

            // Handle rate limiting
            else if (!icmp(key, "x-ratelimit-limit"))
                this.rate_limit.limit = value.to!size_t;
            else if (!icmp(key, "x-ratelimit-remaining"))
                this.rate_limit.remaining = value.to!size_t;
            else if (!icmp(key, "x-ratelimit-used"))
                this.rate_limit.used = value.to!size_t;
            else if (!icmp(key, "x-ratelimit-reset"))
                this.rate_limit.reset = SysTime.fromUnixTime(value.to!long, UTC());

        };
        this.connection.onReceive = (ubyte[] data) {
            content ~= data;
            return data.length;
        };

        this.connection.onReceiveStatusLine = (HTTP.StatusLine l) { statusLine = l; };
        this.connection.url = url.toString();
        this.connection.perform();
        if (statusLine.code == 304)
            return typeof(return)(true, null, cache, next); // Cache hit
        enforce(statusLine.code / 100 == 2, new HTTPStatusException(statusLine.code,
            format("HTTP request returned status code %d (%s)", statusLine.code, statusLine.reason)));

        return typeof(return)(false, _decodeContent!T(content.data, charset), cache, next);
    }
    else
        public RequestResult!(T[]) get (T = char) (URL url,
            string etag = null, string last_modified = null) {
            assert(0, "Need `DubUseCurl` to be able to use index client");
        }
}

/**
 * Represent the functionality a single repository implements
 */
package(dub) interface RepositoryClient {
    import dub.recipe.packagerecipe;

    /**
     * Get the project description as filled in the provider
     *
     * This can be used as a fallback if the recipe file does not
     * contain a description.
     */
    public string getDescription (CacheInfo cache);

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
    public RequestResult!(TagDescription[]) getTags (CacheInfo cache);

    /**
     * Get the deserialized `PackageRecipe`
     *
     * This finds the package recipe in the repository, then fetches and
     * deserializes it.
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
    public RequestResult!PackageRecipe findRecipe (
        ref InetPath path, string reference, CacheInfo cache);
}

/// Simple wrapper for a request result
package struct RequestResult (T) {
    /// Whether or not there was a cache hit
    public bool notModified;

    /// The data, may be null if there was a cache hit
    public T result;

    /// Cache information
    public CacheInfo cache;

    /// Link information (for paginated result)
    public string next;

    /// Convenience function for various convertion
    public RequestResult!OT convert (OT) (OT value = OT.init) {
        return typeof(return)(this.notModified, value, this.cache, this.next);
    }
}

/// https://docs.github.com/en/rest/rate-limit/rate-limit?apiVersion=2022-11-28
/// https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api?apiVersion=2022-11-28#checking-the-status-of-your-rate-limit
public struct RateLimit {
    /// `x-ratelimit-limit`
    /// The maximum number of requests that you can make per hour
    public size_t limit;
    /// x-ratelimit-remaining
	/// The number of requests remaining in the current rate limit window
    public size_t remaining;
    /// x-ratelimit-used
	/// The number of requests you have made in the current rate limit window
    public size_t used;
    /// x-ratelimit-reset
    /// The time at which the current rate limit window resets, in UTC epoch seconds
    public SysTime reset;
}

/// Wrapper for tag information
public struct TagDescription {
    /// Name of this tag
    public string name;

    /// Commit SHA this refers to
    public string commit;
}

// Taken from `std.net.curl`
private auto _decodeContent (T) (ubyte[] content, string encoding)
{
    static if (is(T == ubyte))
        return content;
    else
    {
        import std.exception : enforce;
        import std.format : format;
        import std.uni : icmp;

        // Optimally just return the utf8 encoded content
        if (icmp(encoding, "UTF-8") == 0)
            return cast(char[])(content);

        // The content has to be re-encoded to utf8
        auto scheme = EncodingScheme.create(encoding);
        enforce!CurlException(scheme !is null,
            format("Unknown encoding '%s'", encoding));

        auto strInfo = decodeString(content, scheme);
        enforce!CurlException(strInfo[0] != size_t.max,
            format("Invalid encoding sequence for encoding '%s'", encoding));

        return strInfo[1];
    }
}

// Taken from `std.net.curl`
private Tuple!(size_t,Char[]) decodeString(Char = char)(const(ubyte)[] data,
    EncodingScheme scheme, size_t maxChars = size_t.max)
{
    import std.encoding : INVALID_SEQUENCE;
    Char[] res;
    immutable startLen = data.length;
    size_t charsDecoded = 0;
    while (data.length && charsDecoded < maxChars)
    {
        immutable dchar dc = scheme.safeDecode(data);
        if (dc == INVALID_SEQUENCE)
        {
            return typeof(return)(size_t.max, cast(Char[]) null);
        }
        charsDecoded++;
        res ~= dc;
    }
    return typeof(return)(startLen-data.length, res);
}
