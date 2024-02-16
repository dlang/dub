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
import dub.internal.vibecompat.inet.path : NativePath;

import dub.internal.configy.Attributes;
import dub.internal.dyaml.stdsumtype;

import std.exception;

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
    public static SelectionsFile fromYAML (scope ConfigParser!SelectionsFile parser)
    {
        import dub.internal.configy.Read;

        static struct OnlyVersion { uint fileVersion; }

        auto vers = parseConfig!OnlyVersion(
            CLIArgs.init, parser.node, StrictMode.Ignore);

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
private struct SelectedDependency
{
    public Dependency actual;
    alias actual this;

    /// Constructor, used in `fromYAML`
    public this (inout(Dependency) dep) inout @safe pure nothrow @nogc
    {
        this.actual = dep;
    }

    /// Allow external code to assign to this object as if it was a `Dependency`
    public ref SelectedDependency opAssign (Dependency dep) return pure nothrow @nogc
    {
        this.actual = dep;
        return this;
    }

    /// Read a `Dependency` from the config file - Required to support both short and long form
    static SelectedDependency fromYAML (scope ConfigParser!SelectedDependency p)
    {
        import dub.internal.dyaml.node;

        if (p.node.nodeID == NodeID.scalar)
            return SelectedDependency(Dependency(Version(p.node.as!string)));

        auto d = p.parseAs!YAMLFormat;
        if (d.path.length)
            return SelectedDependency(Dependency(NativePath(d.path)));
        else
        {
            assert(d.version_.length);
            if (d.repository.length)
                return SelectedDependency(Dependency(Repository(d.repository, d.version_)));
            return SelectedDependency(Dependency(Version(d.version_)));
        }
    }

	/// In-file representation of a dependency as permitted in `dub.selections.json`
	private struct YAMLFormat
	{
		@Optional @Name("version") string version_;
		@Optional string path;
		@Optional string repository;

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
		}
	}
}

// Ensure we can read all type of dependencies
unittest
{
    import dub.internal.configy.Read : parseConfigString;

    immutable string content = `{
    "fileVersion": 1,
    "versions": {
        "simple": "1.5.6",
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
    assert(s.versions.length == 5);
    assert(s.versions["simple"]     == Dependency(Version("1.5.6")));
    assert(s.versions["branch"]     == Dependency(Version("~master")));
    assert(s.versions["branch2"]    == Dependency(Version("~main")));
    assert(s.versions["path"]       == Dependency(NativePath("../some/where")));
    assert(s.versions["repository"] == Dependency(Repository("git+https://github.com/dlang/dub", "123456123456123456")));
}

// with optional `inheritable` Boolean
unittest
{
    import dub.internal.configy.Read : parseConfigString;

    immutable string content = `{
    "fileVersion": 1,
    "inheritable": true,
    "versions": {
        "simple": "1.5.6",
    }
}`;

    auto s = parseConfigString!Selected(content, "/dev/null");
    assert(s.fileVersion == 1);
    assert(s.inheritable);
    assert(s.versions.length == 1);
}

// Test reading an unsupported version
unittest
{
    import dub.internal.configy.Read : parseConfigString;

    immutable string content = `{"fileVersion": 9999, "thisis": "notrecognized"}`;
    auto s = parseConfigString!SelectionsFile(content, "/dev/null");
    assert(s.fileVersion == 9999);
}
