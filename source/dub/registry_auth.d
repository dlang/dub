/**
	Authenticated access to a DUB registry for package registration.

	The public registry (code.dlang.org) registers packages via a browser form
	(`POST /register_package` after session login). This module implements that
	flow for the `dub publish` command.

	Copyright: © 2026 DUB contributors
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module dub.registry_auth;

import dub.dub : SpecialDirs, defaultRegistryURLs;
import dub.internal.io.realfs : RealFS;
import dub.internal.logging;
import dub.internal.utils : getDUBVersion;
import dub.internal.vibecompat.inet.path;

import std.algorithm : canFind, endsWith, startsWith;
import std.array : appender, split;
import std.conv : to;
import std.exception : enforce;
import std.file : exists, mkdirRecurse, readText, write;
import std.process : Config, environment, execute;
import std.string : chomp, indexOf, strip, toLower;
import std.uri : encodeComponent;

version (DubUseCurl) {
	import std.net.curl : CurlException, HTTP;
}

/// Credentials / endpoint for registry authentication.
struct RegistryAuthConfig
{
	string registryUrl = "https://code.dlang.org";
	string user;
	string password;
	string cookieJar;
}

/// Result of a registry HTTP interaction.
struct RegistryAuthResult
{
	int status;
	string body_;
	bool ok() const @safe pure nothrow { return status >= 200 && status < 400; }
}

/// Resolve config from overrides, environment, then `~/.dub` credentials.
RegistryAuthConfig loadRegistryAuthConfig(string registryOverride = null,
	string userOverride = null, string passwordOverride = null)
{
	RegistryAuthConfig cfg;

	if (registryOverride.length)
		cfg.registryUrl = registryOverride;
	else if (auto r = environment.get("DUB_REGISTRY_URL"))
		cfg.registryUrl = r;
	else
		cfg.registryUrl = defaultRegistryURLs[0];

	if (userOverride.length)
		cfg.user = userOverride;
	else if (auto u = environment.get("DUB_REGISTRY_USER"))
		cfg.user = u;

	if (passwordOverride.length)
		cfg.password = passwordOverride;
	else if (auto p = environment.get("DUB_REGISTRY_PASSWORD"))
		cfg.password = p;

	scope fs = new RealFS();
	auto home = SpecialDirs.make(fs).userSettings;
	cfg.cookieJar = (home ~ "cookies.txt").toNativeString();

	if (!cfg.user.length || !cfg.password.length)
	{
		auto credPath = (home ~ "credentials").toNativeString();
		if (exists(credPath))
		{
			import std.string : lineSplitter;
			import std.array : array;
			auto lines = readText(credPath).lineSplitter.array;
			if (!cfg.user.length && lines.length >= 1)
				cfg.user = lines[0].strip;
			if (!cfg.password.length && lines.length >= 2)
				cfg.password = lines[1].strip;
		}
	}

	normalizeRegistryUrl(cfg.registryUrl);
	return cfg;
}

/// Persist username/password under the user settings directory (plain text).
void saveRegistryCredentials(string user, string password)
{
	scope fs = new RealFS();
	auto home = SpecialDirs.make(fs).userSettings;
	mkdirRecurse(home.toNativeString());
	write((home ~ "credentials").toNativeString(), user ~ "\n" ~ password ~ "\n");
}

void normalizeRegistryUrl(ref string url)
{
	if (!url.length)
		url = "https://code.dlang.org";
	while (url.endsWith("/"))
		url = url[0 .. $ - 1];
	// Strip dub+ / mvn+ scheme prefixes used by --registry package suppliers.
	if (url.startsWith("dub+"))
		url = url["dub+".length .. $];
	else if (url.startsWith("mvn+"))
		url = url["mvn+".length .. $];
}

/// Return the URL for a git remote (default `origin`), or `null` if unavailable.
string detectGitRemoteUrl(string remote = "origin", string cwd = ".")
{
	auto r = execute(["git", "-C", cwd, "remote", "get-url", remote], null,
		Config.stderrPassThrough);
	if (r.status != 0)
		return null;
	auto url = r.output.strip;
	if (!url.length)
		return null;
	return normalizeRepoUrl(url);
}

/// Turn common git remote forms into an https URL the registry accepts.
string normalizeRepoUrl(string url)
{
	url = url.strip;
	url = url.chomp(".git");

	// git@github.com:owner/repo
	if (url.startsWith("git@"))
	{
		auto rest = url[4 .. $]; // host:path
		auto colon = rest.indexOf(':');
		enforce(colon >= 0, "Unrecognized SSH remote: " ~ url);
		auto host = rest[0 .. colon];
		auto path = rest[colon + 1 .. $];
		return "https://" ~ host ~ "/" ~ path;
	}

	// ssh://git@host/owner/repo
	if (url.startsWith("ssh://"))
	{
		auto without = url["ssh://".length .. $];
		if (without.canFind("@"))
			without = without.split("@")[1];
		return "https://" ~ without;
	}

	if (!url.startsWith("http://") && !url.startsWith("https://"))
	{
		if (url.canFind("/"))
		{
			if (url.canFind("."))
				return "https://" ~ url;
			return "https://github.com/" ~ url;
		}
	}

	return url;
}

version (DubUseCurl)
{
	/// HTTP client for registry login / register / update / status.
	final class RegistryAuthClient
	{
		private RegistryAuthConfig cfg;

		this(RegistryAuthConfig cfg)
		{
			this.cfg = cfg;
			auto jarDir = NativePath(cfg.cookieJar).parentPath;
			if (!jarDir.empty && !exists(jarDir.toNativeString()))
				mkdirRecurse(jarDir.toNativeString());
		}

		/// Log in and store the session in the cookie jar.
		void login()
		{
			enforce(cfg.user.length, "Registry username required (--user or DUB_REGISTRY_USER)");
			enforce(cfg.password.length, "Registry password required (--password or DUB_REGISTRY_PASSWORD)");

			auto form = "name=" ~ encodeComponent(cfg.user)
				~ "&password=" ~ encodeComponent(cfg.password);

			auto res = request(HTTP.Method.post, cfg.registryUrl ~ "/login", form,
				"application/x-www-form-urlencoded");

			auto lower = res.body_.toLower;
			enforce(!lower.canFind("invalid user name or password")
				&& !lower.canFind("invalid username or password")
				&& !(res.status == 200 && lower.canFind("please enter your user name and password")),
				"Login failed — check username/password (account must be activated)");
		}

		/// Register a repository URL. Set `ignoreFork` to skip the fork warning.
		RegistryAuthResult registerPackage(string repoUrl, bool ignoreFork = false)
		{
			enforce(repoUrl.length, "Repository URL is required");
			auto form = "url=" ~ encodeComponent(repoUrl);
			if (ignoreFork)
				form ~= "&ignore_fork=true";

			auto res = request(HTTP.Method.post, cfg.registryUrl ~ "/register_package", form,
				"application/x-www-form-urlencoded");

			auto lower = res.body_.toLower;
			if (lower.canFind("warn_fork") || lower.canFind("this repository is a fork")
				|| lower.canFind("is a fork"))
			{
				throw new Exception(
					"Repository looks like a fork. Re-run with --ignore-fork if that is intentional.");
			}
			if (lower.canFind("redalert") || (res.status == 200 && lower.canFind("add new package")
				&& lower.canFind("error")))
			{
				throw new Exception("Registration failed:\n" ~ extractAlert(res.body_));
			}
			if (res.status == 401 || res.status == 403
				|| (res.status == 200 && lower.canFind("please enter your user name and password")))
			{
				throw new Exception("Not authenticated — login first");
			}
			return res;
		}

		/// Trigger a package metadata refresh (authenticated owner action).
		RegistryAuthResult triggerUpdate(string packageName)
		{
			enforce(packageName.length, "Package name required");
			return request(HTTP.Method.post,
				cfg.registryUrl ~ "/my_packages/" ~ encodeComponent(packageName) ~ "/update",
				null, null);
		}

		/// Trigger update via package webhook secret (no login).
		RegistryAuthResult triggerUpdateWithSecret(string packageName, string secret)
		{
			enforce(packageName.length, "Package name required");
			enforce(secret.length, "Package secret required");
			auto url = cfg.registryUrl ~ "/api/packages/" ~ encodeComponent(packageName)
				~ "/update?secret=" ~ encodeComponent(secret);
			return request(HTTP.Method.post, url, null, null);
		}

		/// Fetch latest version string, or `null` if the package is missing.
		string latestVersion(string packageName)
		{
			auto res = request(HTTP.Method.get,
				cfg.registryUrl ~ "/api/packages/" ~ encodeComponent(packageName) ~ "/latest",
				null, null);
			if (res.status == 404)
				return null;
			enforce(res.ok, "Lookup failed HTTP " ~ res.status.to!string);
			return unwrapJsonString(res.body_.strip);
		}

	private:
		RegistryAuthResult request(HTTP.Method method, string url, string body_, string contentType)
		{
			auto http = HTTP();
			http.url = url;
			http.method = method;
			http.setCookieJar(cfg.cookieJar);
			http.maxRedirects = 10;
			http.addRequestHeader("User-Agent",
				"dub/" ~ getDUBVersion() ~ " (+https://github.com/dlang/dub)");
			http.addRequestHeader("Accept", "text/html,application/json,*/*");

			if (body_ !is null)
			{
				if (contentType.length)
					http.setPostData(body_, contentType);
				else
					http.postData = body_;
			}

			auto buf = appender!string();
			http.onReceive = (ubyte[] data) {
				buf.put(cast(char[]) data);
				return data.length;
			};

			int status = 0;
			http.onReceiveStatusLine = (HTTP.StatusLine line) {
				status = cast(int) line.code;
			};

			try
				http.perform();
			catch (CurlException e)
				throw new Exception("HTTP request failed: " ~ e.msg);

			RegistryAuthResult res;
			res.status = status;
			res.body_ = buf.data;
			return res;
		}
	}
}
else
{
	final class RegistryAuthClient
	{
		this(RegistryAuthConfig) {}
		void login() { throw new Exception("dub publish requires curl support"); }
		RegistryAuthResult registerPackage(string, bool = false)
		{
			throw new Exception("dub publish requires curl support");
		}
		RegistryAuthResult triggerUpdate(string)
		{
			throw new Exception("dub publish requires curl support");
		}
		RegistryAuthResult triggerUpdateWithSecret(string, string)
		{
			throw new Exception("dub publish requires curl support");
		}
		string latestVersion(string)
		{
			throw new Exception("dub publish requires curl support");
		}
	}
}

private string unwrapJsonString(string s)
{
	if (s.length >= 2 && s[0] == '"' && s[$ - 1] == '"')
		return s[1 .. $ - 1];
	return s;
}

private string extractAlert(string html)
{
	import std.regex : ctRegex, matchFirst, regex, replaceAll;
	static re = ctRegex!(`<p[^>]*class="[^"]*redAlert[^"]*"[^>]*>([\s\S]*?)</p>`, "i");
	auto m = matchFirst(html, re);
	if (!m)
		return html.length > 500 ? html[0 .. 500] ~ "…" : html;
	auto text = m[1].replaceAll(regex(`<[^>]+>`), " ").strip;
	return text.length ? text : m[1].strip;
}

unittest
{
	assert(normalizeRepoUrl("git@github.com:org/repo.git") == "https://github.com/org/repo");
	assert(normalizeRepoUrl("https://github.com/org/repo.git") == "https://github.com/org/repo");
	assert(normalizeRepoUrl("ssh://git@gitlab.com/org/repo") == "https://gitlab.com/org/repo");
	assert(normalizeRepoUrl("org/repo") == "https://github.com/org/repo");

	string u = "https://code.dlang.org/";
	normalizeRegistryUrl(u);
	assert(u == "https://code.dlang.org");
	u = "dub+https://code.dlang.org";
	normalizeRegistryUrl(u);
	assert(u == "https://code.dlang.org");
}
