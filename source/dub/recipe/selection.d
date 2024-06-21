/**
 * Contains type definition for the selections file
 *
 * The selections file, commonly known by its file name
 * `dub.selections.json`, is used by Dub to store resolved
 * dependencies. Its purpose is identical to other package
 * managers' lock file.
 */
module dub.recipe.selection;

import dub.dependency;
import dub.internal.vibecompat.data.json : Json;
import dub.internal.vibecompat.inet.path : NativePath;

import dub.internal.configy.attributes;
import dub.internal.dyaml.stdsumtype;

import std.algorithm.iteration : each;
import std.algorithm.searching : canFind;
import std.exception;
import std.format : format;
import std.range : enumerate;
import std.string : indexOf;

deprecated("Use either `Selections!1` or `SelectionsFile` instead")
public alias Selected = Selections!1;

/**
 * Top level type for `dub.selections.json`
 *
 * To support multiple version, we expose a `SumType` which
 * contains the "real" version being parsed.
 */
public struct SelectionsFile
{
    /// Private alias to avoid repetition
    private alias DataType = SumType!(Selections!0, Selections!1);

    /**
     * Get the `fileVersion` of this selection file
     *
     * The `fileVersion` is always present, no matter the version.
     * This is a convenience function that matches any version and allows
     * one to retrieve it.
     *
     * Note that the `fileVersion` can be an unsupported version.
     */
    public uint fileVersion () const @safe pure nothrow @nogc
    {
        return this.content.match!((s) => s.fileVersion);
    }

    /**
     * Whether this dub.selections.json can be inherited by nested projects
     * without local dub.selections.json
     */
    public bool inheritable () const @safe pure nothrow @nogc
    {
        return this.content.match!(
            (const Selections!0 _) => false,
            (const Selections!1 s) => s.inheritable,
        );
    }

    /**
     * The content of this selections file
     *
     * The underlying content can be accessed using
     * `dub.internal.yaml.stdsumtype : match`, for example:
     * ---
     * SelectionsFile file = readSelectionsFile();
     * file.content.match!(
     *     (Selections!0 s) => logWarn("Unsupported version: %s", s.fileVersion),
     *     (Selections!1 s) => logWarn("Old version (1), please upgrade!"),
     *     (Selections!2 s) => logInfo("You are up to date"),
     * );
     * ---
     */
    public DataType content;

    /**
     * Deserialize the selections file according to its version
     *
     * This will first deserialize the `fileVersion` only, and then
     * the expected version if it is supported. Unsupported versions
     * will be returned inside a `Selections!0` struct,
     * which only contains a `fileVersion`.
     */
    public static SelectionsFile fromConfig (scope ConfigParser parser)
    {
        import dub.internal.configy.read;

        static struct OnlyVersion { uint fileVersion; }

        auto vers = parseConfig!OnlyVersion(parser.node, StrictMode.Ignore);

        switch (vers.fileVersion) {
        case 1:
            return SelectionsFile(DataType(parser.parseAs!(Selections!1)));
        default:
            return SelectionsFile(DataType(Selections!0(vers.fileVersion)));
        }
    }
}

/**
 * A specific version of the selections file
 *
 * Currently, only two instantiations of this struct are possible:
 * - `Selections!0` is an invalid/unsupported version;
 * - `Selections!1` is the most widespread version;
 */
public struct Selections (ushort Version)
{
    ///
    public uint fileVersion = Version;

    static if (Version == 0) { /* Invalid version */ }
    else static if (Version == 1) {
        /// The selected package and their matching versions
        public SelectedDependency[string] versions;

        /// Whether this dub.selections.json can be inherited by nested projects
        /// without local dub.selections.json
        @Optional public bool inheritable;
    }
    else
        static assert(false, "This version is not supported");
}


/// Wrapper around `SelectedDependency` to do deserialization but still provide
/// a `Dependency` object to client code.
package(dub) struct SelectedDependency
{
    public Dependency actual;
    alias actual this;
    public IntegrityTag integrity;

    /// Constructor, used in `fromConfig`
    public this (inout(Dependency) dep, const IntegrityTag tag = IntegrityTag.init)
         inout @safe pure nothrow @nogc
    {
        this.actual = dep;
        this.integrity = tag;
    }

    /// Allow external code to assign to this object as if it was a `Dependency`
    public ref SelectedDependency opAssign (Dependency dep) return pure nothrow @nogc
    {
        this.actual = dep;
        this.integrity = IntegrityTag.init;
        return this;
    }

    /// Read a `Dependency` from the config file - Required to support both short and long form
    static SelectedDependency fromConfig (scope ConfigParser p)
    {
        if (scope scalar = p.node.asScalar())
            return SelectedDependency(Dependency(Version(scalar.str)));

        auto d = p.parseAs!YAMLFormat;
        if (d.path.length)
            return SelectedDependency(Dependency(NativePath(d.path)));
        else
        {
            assert(d.version_.length);
            if (d.repository.length)
                return SelectedDependency(Dependency(Repository(d.repository, d.version_)));
            return SelectedDependency(Dependency(Version(d.version_)), d.integrity);
        }
    }

    /// Serializes a selected version to JSON for `dub.selections.json`
    public Json toJsonDep () const {
        version (none) {
            // The following is not yet enabled, because we're currently only
            // able to get an integrity tag value when the package is first
            // downloaded. This is problematic as most of the time, we try
            // to reuse packages, and most common use of `dub upgrade` would
            // make the integrity tag flip between empty or not.
            // However, with this code enabled, one may get an integrity tag
            // written to their `dub.selections.json` under two conditions:
            // 1) The package is not present on the file system;
            // 2) The package is upgraded (e.g. `dub upgrade` would normally trigger);
            if (this.integrity.value.length && this.actual.isExactVersion()) {
                const vers = this.actual.version_();
                Json result = Json.emptyObject;
                result["version"] = Json(vers.toString());
                result["integrity"] = Json(
                    "%s-%s".format(this.integrity.algorithm, this.integrity.value));
                return result;
            }
        }
        return this.actual.toJson(true);
    }

	/// In-file representation of a dependency as permitted in `dub.selections.json`
	private struct YAMLFormat
	{
		@Optional @Name("version") string version_;
		@Optional string path;
		@Optional string repository;
		@Optional IntegrityTag integrity;

		public void validate () const scope @safe pure
		{
			enforce(this.version_.length || this.path.length || this.repository.length,
				"Need to provide a version string, or an object with one of the following fields: `version`, `path`, or `repository`");
			enforce(!this.path.length || !this.repository.length,
				"Cannot provide a `path` dependency if a repository dependency is used");
			enforce(!this.path.length || !this.version_.length,
				"Cannot provide a `path` dependency if a `version` dependency is used");
			enforce(!this.repository.length || this.version_.length,
				"Cannot provide a `repository` dependency without a `version`");
			enforce(!this.integrity.algorithm.length || (!this.path.length && !this.repository.length),
				"`integrity` property is only supported for `version` dependencies");
		}
	}
}

/**
 * A subresource integrity declaration
 *
 * Implement the SRI (Subresource Integrity) standard, used to validate that
 * a given dependency is of the expected version.
 *
 * One may get an integrity tag in base64 using openssl:
 * ```
 * $ cat vibe.d-0.10.1.zip |  openssl dgst -binary -sha512 | base64
 * vwQ9tYTjLb981j41+3GZZUgKXm/5PlKpmY2bplRSUM8ajL03++LGm/TcfFFarJrHex8CTb5ZLWdi
 * Y1fFAOSkSw==
 * ```
 *
 * See_Also:
 *   https://w3c.github.io/webappsec-subresource-integrity/#the-integrity-attribute
 */
public struct IntegrityTag
{
	/// The hash function to use
	public string algorithm;
	/// The value of the digest computed with `algorithm`, base64-encoded
	public string value;

	/// Parses a string representation as an `IntegrityTag`
	public this (string value)
	{
		auto sep = indexOf(value, '-');
		enforce(sep > 0, `Expected a string in the form 'hash-algorithm "-" base64-value', e.g. 'sha512-...'`);
		this.algorithm = value[0 .. sep];
		this.value = value[sep + 1 .. $];
		switch (this.algorithm) {
		case "sha512":
			enforce(this.value.length == 88,
				"Excepted a base64-encoded sha512 digest of 88 characters, not %s"
				.format(this.value.length));
			break;
		case "sha384":
			enforce(this.value.length == 64,
				"Excepted a base64-encoded sha384 digest of 64 characters, not %s"
				.format(this.value.length));
			break;
		case "sha256":
			enforce(this.value.length == 40,
				"Excepted a base64-encoded sha256 digest of 40 characters, not %s"
				.format(this.value.length));
			break;
		default:
			throw new Exception("Algorithm '" ~ this.algorithm ~
				"' is not supported, expected one of: 'sha512', 'sha384', 'sha256'");
		}
		this.value.enumerate.each!((size_t idx, dchar c) {
			enforce("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=".canFind(c),
				"Expected digest to be base64 encoded, found non-base64 character '%s' at index '%s'"
				.format(c, idx));
		});
	}

    /// Internal constructor for `IntegrityTag.make`
    public this (string algorithm, string value) inout @safe pure nothrow @nogc {
        this.algorithm = algorithm;
        this.value = value;
    }

    /**
     * Verify if the data passed in parameter matches this `IntegrityTag`
     *
     * Params:
     *   data = The content of the archive to check for a match
     *
     * Returns:
     *   Whether the hash of `data` (using `this.algorithm)` matches
     *   the value that is `base64` encoded.
     */
    public bool matches (in ubyte[] data) const @safe pure {
        import std.base64;
        import std.digest.sha;

        ubyte[64] buffer; // 32, 48, or 64 bytes used
        auto decoded = Base64.decode(this.value, buffer[]);
        switch (this.algorithm) {
            case "sha512":
                return sha512Of(data) == decoded;
            case "sha384":
                return sha384Of(data) == decoded;
            case "sha256":
                return sha256Of(data) == decoded;
            default:
                assert(0, "An `IntegrityTag` with non-supported algorithm was created: " ~ this.algorithm);
        }
    }

    /**
     * Build and returns an `IntegrityTag`
     *
     * This is a convenience function to build an `IntegrityTag` from the
     * archive data. Use sha512 by default.
     *
     * Params:
     *   data = The content of the archive to check hash into a digest
     *   algorithm = One of `sha256`, `sha384`, `sha512`. Default to the latter.
     *
     * Returns:
     *   A populated `IntegrityTag`.
     */
    public static IntegrityTag make (in ubyte[] data, string algorithm = "sha512")
	    @safe pure {
        import std.base64;
        import std.digest.sha;

        switch (algorithm) {
            case "sha512":
                return IntegrityTag(algorithm, Base64.encode(sha512Of(data)));
            case "sha384":
                return IntegrityTag(algorithm, Base64.encode(sha384Of(data)));
            case "sha256":
                return IntegrityTag(algorithm, Base64.encode(sha256Of(data)));
            default:
                assert(0, "`IntegrityTag.make` was called with non-supported algorithm: " ~ algorithm);
        }
    }
}

// Ensure we can read all type of dependencies
unittest
{
    import dub.internal.configy.easy : parseConfigString;

    immutable string content = `{
    "fileVersion": 1,
    "versions": {
        "simple": "1.5.6",
        "complex": { "version": "1.2.3" },
        "digest": { "version": "1.2.3", "integrity": "sha256-abcdefghijklmnopqrstuvwxyz0123456789+/==" },
        "digest1": { "version": "1.2.3", "integrity": "sha384-Li9vy3DqF8tnTXuiaAJuML3ky+er10rcgNR/VqsVpcw+ThHmYcwiB1pbOxEbzJr7" },
        "digest2": { "version": "1.2.3", "integrity": "sha512-Q2bFTOhEALkN8hOms2FKTDLy7eugP2zFZ1T8LCvX42Fp3WoNr3bjZSAHeOsHrbV1Fu9/A0EzCinRE7Af1ofPrw==" },
        "branch": "~master",
        "branch2": "~main",
        "path": { "path": "../some/where" },
        "repository": { "repository": "git+https://github.com/dlang/dub", "version": "123456123456123456" }
    }
}`;

    auto file = parseConfigString!SelectionsFile(content, "/dev/null");
    assert(file.fileVersion == 1);
    auto s = file.content.match!(
        (Selections!1 s) => s,
        (s) { assert(0); return Selections!(1).init; },
    );
    assert(!s.inheritable);
    assert(s.versions.length == 9);
    assert(s.versions["simple"]     == Dependency(Version("1.5.6")));
    assert(s.versions["complex"]    == Dependency(Version("1.2.3")));
    assert(s.versions["digest"]     == Dependency(Version("1.2.3")));
    assert(s.versions["digest1"]    == Dependency(Version("1.2.3")));
    assert(s.versions["digest2"]    == Dependency(Version("1.2.3")));
    assert(s.versions["branch"]     == Dependency(Version("~master")));
    assert(s.versions["branch2"]    == Dependency(Version("~main")));
    assert(s.versions["path"]       == Dependency(NativePath("../some/where")));
    assert(s.versions["repository"] == Dependency(Repository("git+https://github.com/dlang/dub", "123456123456123456")));
}

// with optional `inheritable` Boolean
unittest
{
    import dub.internal.configy.easy : parseConfigString;

    immutable string content = `{
    "fileVersion": 1,
    "inheritable": true,
    "versions": {
        "simple": "1.5.6",
    }
}`;

    auto s = parseConfigString!SelectionsFile(content, "/dev/null");
    assert(s.inheritable);
}

// Test reading an unsupported version
unittest
{
    import dub.internal.configy.easy : parseConfigString;

    immutable string content = `{"fileVersion": 9999, "thisis": "notrecognized"}`;
    auto s = parseConfigString!SelectionsFile(content, "/dev/null");
    assert(s.fileVersion == 9999);
}
