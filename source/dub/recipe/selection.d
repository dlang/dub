/**
 * Contains type definition for `dub.selections.json`
 */
module dub.recipe.selection;

import dub.dependency;
import dub.internal.vibecompat.core.file : NativePath;

import dub.internal.configy.Attributes;

import std.exception;

public struct Selected
{
    /// The current version of the file format
    public uint fileVersion;

    /// The selected package and their matching versions
    public SelectedDependency[string] versions;

    /// Whether this dub.selections.json can be inherited by nested projects
    /// without local dub.selections.json
    @Optional public bool inheritable;
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
    import dub.internal.vibecompat.core.file : NativePath;

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

    auto s = parseConfigString!Selected(content, "/dev/null");
    assert(s.fileVersion == 1);
    assert(s.versions.length == 5);
    assert(s.versions["simple"]     == Dependency(Version("1.5.6")));
    assert(s.versions["branch"]     == Dependency(Version("~master")));
    assert(s.versions["branch2"]    == Dependency(Version("~main")));
    assert(s.versions["path"]       == Dependency(NativePath("../some/where")));
    assert(s.versions["repository"] == Dependency(Repository("git+https://github.com/dlang/dub", "123456123456123456")));
    assert(!s.inheritable);
}

// with optional `inheritable` Boolean
unittest
{
    import dub.internal.configy.Read : parseConfigString;

    immutable string content = `{
    "fileVersion": 1,
    "versions": {
        "simple": "1.5.6",
    },
    "inheritable": true
}`;

    auto s = parseConfigString!Selected(content, "/dev/null");
    assert(s.fileVersion == 1);
    assert(s.versions.length == 1);
    assert(s.inheritable);
}
