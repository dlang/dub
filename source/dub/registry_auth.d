/**
	Authenticated access to a DUB registry for package registration and owner
	settings (logo, docs URL, categories, webhooks, permissions, remove).

	The public registry (code.dlang.org) registers packages via a browser form
	(`POST /register_package` after session login). This module implements that
	flow for the `dub publish` command, plus the My packages owner actions.

	Copyright: © 2026 DUB contributors
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module dub.registry_auth;

import dub.dub : SpecialDirs, defaultRegistryURLs;
import dub.internal.io.realfs : RealFS;
import dub.internal.logging;
import dub.internal.utils : getDUBVersion;
import dub.internal.vibecompat.inet.path;
import dub.registry_secrets;

import std.algorithm : canFind, endsWith, startsWith;
import std.array : appender, split;
import std.conv : to;
import std.exception : enforce;
import std.file : exists, mkdirRecurse, read, readText, remove, write;
import std.process : Config, environment, execute;
import std.string : chomp, indexOf, representation, strip, toLower;
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

/// Webhook endpoint URLs (always built clean — avoids dub-registry #614 malformation).
struct WebhookUrls
{
	string generic;
	string github;
	string gitlab;
	string secret;
}

/// Build clean webhook URLs for a package (generic / GitHub / GitLab).
WebhookUrls buildWebhookUrls(string registryUrl, string packageName, string secret)
{
	normalizeRegistryUrl(registryUrl);
	auto base = registryUrl ~ "/api/packages/" ~ encodeComponent(packageName);
	WebhookUrls u;
	u.secret = secret;
	u.generic = base ~ "/update";
	u.github = base ~ "/update/github?secret=" ~ encodeComponent(secret);
	u.gitlab = base ~ "/update/gitlab";
	return u;
}

/// Thrown when register_package reports the repository is already registered.
class AlreadyRegisteredException : Exception
{
	this(string msg, string file = __FILE__, size_t line = __LINE__)
	{
		super(msg, file, line);
	}
}

bool isAlreadyRegisteredMessage(string alert)
{
	auto lower = alert.toLower;
	return lower.canFind("already registered")
		|| lower.canFind("already exists")
		|| lower.canFind("is already registered");
}

/// Path to the DUB user settings directory (`~/.dub` / `%APPDATA%\dub`).
NativePath registryUserSettingsDir()
{
	scope fs = new RealFS();
	return SpecialDirs.make(fs).userSettings;
}

string credentialsPath()
{
	return (registryUserSettingsDir() ~ "credentials.v1").toNativeString();
}

/**
	Default path for a one-shot plaintext password drop file.

	Agents/scripts write the password here (first line), then run
	`dub publish login --user … --save-credentials`. On success the app stores
	it with DPAPI (Windows) / mode 0600 (elsewhere) and deletes this file.
*/
string passwordDropPath()
{
	return (registryUserSettingsDir() ~ "password.incoming").toNativeString();
}

/// Create the user settings directory if needed (so an agent can write password.incoming).
string ensureUserSettingsDir()
{
	auto home = registryUserSettingsDir();
	mkdirRecurse(home.toNativeString());
	return home.toNativeString();
}

/// Delete the password drop file if present. Returns true when a file was removed.
bool clearPasswordDrop()
{
	auto path = passwordDropPath();
	if (!exists(path))
		return false;
	remove(path);
	return true;
}

/// Resolve config from overrides, environment, then DUB user settings credentials.
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

	auto home = registryUserSettingsDir();
	cfg.cookieJar = (home ~ "cookies.txt").toNativeString();

	if (!cfg.user.length || !cfg.password.length)
	{
		string loadedUser;
		string loadedPassword;
		bool fromLegacy;
		if (loadStoredCredentials(loadedUser, loadedPassword, fromLegacy))
		{
			if (!cfg.user.length)
				cfg.user = loadedUser;
			if (!cfg.password.length)
				cfg.password = loadedPassword;
			// Upgrade legacy plaintext files on first successful read.
			if (fromLegacy && cfg.user.length && cfg.password.length
				&& cfg.user == loadedUser && cfg.password == loadedPassword)
			{
				try
					saveRegistryCredentials(cfg.user, cfg.password);
				catch (Exception)
				{
					// Keep using the in-memory password; leave legacy file alone.
				}
			}
		}
	}

	normalizeRegistryUrl(cfg.registryUrl);
	return cfg;
}

/**
	Persist username/password under the DUB user settings directory.

	The password is not hashed: a hash cannot be sent to the registry on later
	logins. On Windows the secret is protected with DPAPI (bound to the current
	user). Elsewhere it is stored Base64-encoded under mode 0600 (OS file ACLs).
*/
void saveRegistryCredentials(string user, string password)
{
	auto home = registryUserSettingsDir();
	mkdirRecurse(home.toNativeString());
	auto path = credentialsPath();
	auto body_ = "version=1\n"
		~ "user=" ~ user ~ "\n"
		~ "password=" ~ protectSecret(password) ~ "\n";
	write(path, body_);
	version (Posix)
	{
		import core.sys.posix.sys.stat : chmod;
		import std.conv : octal;
		import std.string : toStringz;
		chmod(path.toStringz, octal!600);
	}
	// Remove legacy plaintext file if present alongside the new format.
	auto legacy = (home ~ "credentials").toNativeString();
	if (legacy != path && exists(legacy))
	{
		try
			remove(legacy);
		catch (Exception)
		{
		}
	}
}

/// Delete stored credentials (new + legacy filenames) and any leftover drop file.
bool clearRegistryCredentials()
{
	bool removed;
	auto home = registryUserSettingsDir();
	foreach (name; ["credentials.v1", "credentials", "password.incoming"])
	{
		auto path = (home ~ name).toNativeString();
		if (exists(path))
		{
			remove(path);
			removed = true;
		}
	}
	return removed;
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
	/// HTTP client for registry login / register / update / owner settings.
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

		/// Register a repository URL. Throws AlreadyRegisteredException when already present.
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
				&& (lower.canFind("error") || lower.canFind("failed"))))
			{
				auto alert = extractAlert(res.body_);
				if (isAlreadyRegisteredMessage(alert))
					throw new AlreadyRegisteredException(alert);
				throw new Exception("Registration failed:\n" ~ alert);
			}
			// Successful registration usually redirects away from the add form.
			if (res.status == 200 && lower.canFind("add new package")
				&& lower.canFind("register package"))
			{
				throw new Exception(
					"Registration did not complete (still on add-package form). "
					~ "Check credentials and repository URL.\n" ~ extractAlert(res.body_));
			}
			enforceAuth(res, lower);
			return res;
		}

		/// Trigger a package metadata refresh (authenticated owner action).
		RegistryAuthResult triggerUpdate(string packageName)
		{
			enforce(packageName.length, "Package name required");
			return request(HTTP.Method.post, pkgPath(packageName) ~ "/update", null, null);
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

		/// Enable or regenerate webhook secret. Returns plaintext secret (Accept: text/plain).
		string regenSecret(string packageName)
		{
			enforce(packageName.length, "Package name required");
			auto res = request(HTTP.Method.post, pkgPath(packageName) ~ "/regen_secret",
				null, null, "text/plain");
			enforce(res.ok, "regen_secret failed HTTP " ~ res.status.to!string ~ ": " ~ res.body_);
			auto secret = res.body_.strip;
			enforce(secret.length > 0, "Registry returned an empty webhook secret");
			return secret;
		}

		RegistryAuthResult unsetSecret(string packageName)
		{
			enforce(packageName.length, "Package name required");
			return request(HTTP.Method.post, pkgPath(packageName) ~ "/unset_secret", null, null);
		}

		RegistryAuthResult setDocumentationUrl(string packageName, string documentationUrl)
		{
			enforce(packageName.length, "Package name required");
			auto form = "documentation_url=" ~ encodeComponent(documentationUrl);
			return request(HTTP.Method.post, pkgPath(packageName) ~ "/set_documentation_url",
				form, "application/x-www-form-urlencoded");
		}

		RegistryAuthResult setCategories(string packageName, string[] categories)
		{
			enforce(packageName.length, "Package name required");
			enforce(categories.length <= 4, "At most 4 categories allowed");
			string form;
			foreach (i, cat; categories)
			{
				if (form.length)
					form ~= "&";
				form ~= "categories_" ~ i.to!string ~ "=" ~ encodeComponent(cat);
			}
			// Pad to 4 slots like the web UI (empty clears unused).
			foreach (i; categories.length .. 4)
			{
				if (form.length)
					form ~= "&";
				form ~= "categories_" ~ i.to!string ~ "=";
			}
			return request(HTTP.Method.post, pkgPath(packageName) ~ "/set_categories",
				form, "application/x-www-form-urlencoded");
		}

		RegistryAuthResult setLogo(string packageName, string logoPath)
		{
			enforce(packageName.length, "Package name required");
			enforce(exists(logoPath), "Logo file not found: " ~ logoPath);
			auto bytes = cast(const(ubyte)[]) read(logoPath);
			enforce(bytes.length < 1024 * 1024, "Logo too big (max 1 MiB)");
			enforce(bytes.length > 0, "Logo file is empty");

			import std.path : baseName;
			auto boundary = "----dubpublishBoundary7d4a6e";
			auto filename = baseName(logoPath);
			auto preamble = "--" ~ boundary ~ "\r\n"
				~ "Content-Disposition: form-data; name=\"logo\"; filename=\"" ~ filename ~ "\"\r\n"
				~ "Content-Type: application/octet-stream\r\n\r\n";
			auto epilogue = "\r\n--" ~ boundary ~ "--\r\n";
			auto bodyBytes = cast(ubyte[])(preamble.representation.dup)
				~ bytes
				~ cast(ubyte[])(epilogue.representation);

			return requestRaw(HTTP.Method.post, pkgPath(packageName) ~ "/set_logo",
				bodyBytes, "multipart/form-data; boundary=" ~ boundary);
		}

		RegistryAuthResult deleteLogo(string packageName)
		{
			enforce(packageName.length, "Package name required");
			return request(HTTP.Method.post, pkgPath(packageName) ~ "/delete_logo", null, null);
		}

		RegistryAuthResult setRepository(string packageName, string kind, string owner, string project)
		{
			enforce(packageName.length, "Package name required");
			auto form = "kind=" ~ encodeComponent(kind)
				~ "&owner=" ~ encodeComponent(owner)
				~ "&project=" ~ encodeComponent(project);
			return request(HTTP.Method.post, pkgPath(packageName) ~ "/set_repository",
				form, "application/x-www-form-urlencoded");
		}

		RegistryAuthResult addSharedUser(string packageName, string username, uint permissions)
		{
			enforce(packageName.length, "Package name required");
			enforce(username.length, "Username required");
			// Multiple permissions fields with same name; encode as repeated keys.
			string form = "username=" ~ encodeComponent(username);
			foreach (bit; [1u, 2u, 4u, 15u])
			{
				if (permissions & bit)
					form ~= "&permissions=" ~ bit.to!string;
			}
			return request(HTTP.Method.post, pkgPath(packageName) ~ "/add_shared_user",
				form, "application/x-www-form-urlencoded");
		}

		/// Step 1 of owner delete — shows confirm page; we immediately follow with remove_confirm.
		RegistryAuthResult removePackage(string packageName)
		{
			enforce(packageName.length, "Package name required");
			auto step1 = request(HTTP.Method.post, pkgPath(packageName) ~ "/remove", null, null);
			enforce(step1.ok || step1.status == 200,
				"remove failed HTTP " ~ step1.status.to!string ~ ": " ~ extractAlert(step1.body_));
			return request(HTTP.Method.post, pkgPath(packageName) ~ "/remove_confirm", null, null);
		}

		RegistryAuthResult leavePackage(string packageName)
		{
			enforce(packageName.length, "Package name required");
			return request(HTTP.Method.post, pkgPath(packageName) ~ "/leave", null, null);
		}

		/**
			True when the package document exists on the registry.

			`/latest` 404s when the package is registered but has no versions yet.
			`/info` returns the package document in that case.
		*/
		bool packageExists(string packageName)
		{
			auto info = request(HTTP.Method.get,
				cfg.registryUrl ~ "/api/packages/" ~ encodeComponent(packageName) ~ "/info",
				null, null);
			if (info.status == 404)
				return false;
			if (info.ok)
			{
				auto body_ = info.body_.strip;
				if (!body_.length || body_.canFind("\"statusMessage\"") && body_.canFind("not found"))
					return false;
				return body_.canFind("\"name\"");
			}
			auto res = request(HTTP.Method.get,
				cfg.registryUrl ~ "/api/packages/" ~ encodeComponent(packageName) ~ "/latest",
				null, null);
			if (res.status == 404)
				return false;
			if (!res.ok)
				throw new Exception("Status check failed HTTP " ~ res.status.to!string ~ ": " ~ res.body_);
			return res.body_.strip.length > 0 && !res.body_.canFind("Package not found");
		}

		/// Fetch latest version string, or `null` if the package is missing / has no versions.
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
		string pkgPath(string packageName)
		{
			return cfg.registryUrl ~ "/my_packages/" ~ encodeComponent(packageName);
		}

		void enforceAuth(RegistryAuthResult res, string lower)
		{
			if (res.status == 401 || res.status == 403
				|| (res.status == 200 && lower.canFind("please enter your user name and password")))
			{
				throw new Exception("Not authenticated — login first");
			}
		}

		RegistryAuthResult request(HTTP.Method method, string url, string body_, string contentType,
			string accept = "text/html,application/json,*/*")
		{
			const(ubyte)[] raw;
			if (body_ !is null)
				raw = cast(const(ubyte)[]) body_.representation;
			return requestRaw(method, url, raw, contentType, accept);
		}

		RegistryAuthResult requestRaw(HTTP.Method method, string url, const(ubyte)[] bodyBytes,
			string contentType, string accept = "text/html,application/json,*/*")
		{
			auto http = HTTP();
			http.url = url;
			http.method = method;
			http.setCookieJar(cfg.cookieJar);
			http.maxRedirects = 10;
			http.addRequestHeader("User-Agent",
				"dub/" ~ getDUBVersion() ~ " (+https://github.com/dlang/dub)");
			http.addRequestHeader("Accept", accept);

			if (bodyBytes !is null)
			{
				if (contentType.length)
					http.setPostData(cast(void[]) bodyBytes.dup, contentType);
				else
					http.postData = cast(void[]) bodyBytes.dup;
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
		string regenSecret(string)
		{
			throw new Exception("dub publish requires curl support");
		}
		RegistryAuthResult unsetSecret(string)
		{
			throw new Exception("dub publish requires curl support");
		}
		RegistryAuthResult setDocumentationUrl(string, string)
		{
			throw new Exception("dub publish requires curl support");
		}
		RegistryAuthResult setCategories(string, string[])
		{
			throw new Exception("dub publish requires curl support");
		}
		RegistryAuthResult setLogo(string, string)
		{
			throw new Exception("dub publish requires curl support");
		}
		RegistryAuthResult deleteLogo(string)
		{
			throw new Exception("dub publish requires curl support");
		}
		RegistryAuthResult setRepository(string, string, string, string)
		{
			throw new Exception("dub publish requires curl support");
		}
		RegistryAuthResult addSharedUser(string, string, uint)
		{
			throw new Exception("dub publish requires curl support");
		}
		RegistryAuthResult removePackage(string)
		{
			throw new Exception("dub publish requires curl support");
		}
		RegistryAuthResult leavePackage(string)
		{
			throw new Exception("dub publish requires curl support");
		}
		bool packageExists(string)
		{
			throw new Exception("dub publish requires curl support");
		}
		string latestVersion(string)
		{
			throw new Exception("dub publish requires curl support");
		}
	}
}

/// Load from credentials.v1 or legacy plaintext `credentials`.
private bool loadStoredCredentials(out string user, out string password, out bool fromLegacy)
{
	auto home = registryUserSettingsDir();
	auto v1 = credentialsPath();
	if (exists(v1))
	{
		parseCredentialFile(readText(v1), user, password);
		fromLegacy = false;
		return user.length > 0 || password.length > 0;
	}

	auto legacy = (home ~ "credentials").toNativeString();
	if (exists(legacy))
	{
		auto lines = splitLinesSafe(readText(legacy));
		if (lines.length >= 1)
			user = lines[0].strip;
		if (lines.length >= 2)
			password = lines[1].strip;
		fromLegacy = true;
		return user.length > 0 || password.length > 0;
	}
	return false;
}

private void parseCredentialFile(string text, out string user, out string password)
{
	foreach (line; splitLinesSafe(text))
	{
		auto s = line.strip;
		if (!s.length || s.startsWith("#"))
			continue;
		if (s.startsWith("user="))
			user = s["user=".length .. $];
		else if (s.startsWith("password="))
			password = unprotectSecret(s["password=".length .. $]);
	}
}

private string[] splitLinesSafe(string text)
{
	import std.array : array;
	import std.string : lineSplitter;
	return text.lineSplitter.array;
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

	auto hooks = buildWebhookUrls("https://code.dlang.org/", "mypkg", "sec");
	assert(hooks.generic == "https://code.dlang.org/api/packages/mypkg/update");
	assert(hooks.github == "https://code.dlang.org/api/packages/mypkg/update/github?secret=sec");
	assert(hooks.gitlab == "https://code.dlang.org/api/packages/mypkg/update/gitlab");
	assert(isAlreadyRegisteredMessage("Package is already registered"));
}
