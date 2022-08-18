/**
 * Contains type definition for `dub.selections.json`
 */
module dub.recipe.selection;

import dub.dependency;
import dub.internal.vibecompat.core.file : NativePath;

import configy.Attributes;

import std.exception;

public struct Selected
{
    /// The current version of the file format
    public uint fileVersion;

    /// The selected package and their matching versions
    public YAMLSelectedDependency[string] versions;
}


/// Actual representation of a dependency as permitted in `dub.selections.json`
private struct SelectedDependency
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

/// Wrapper around `SelectedDependency` to do deserialization but still provide
/// a `Dependency` object to client code.
private struct YAMLSelectedDependency
{
    public Dependency actual;
    alias actual this;

    /// Constructor, used in `fromYAML`
    public this (inout(Dependency) dep) inout @safe pure nothrow @nogc
    {
        this.actual = dep;
    }

    /// Allow external code to assign to this object as if it was a `Dependency`
    public ref YAMLSelectedDependency opAssign (Dependency dep) return pure nothrow @nogc
    {
        this.actual = dep;
        return this;
    }

    /// Read a `Dependency` from the config file - Required to support both short and long form
    static YAMLSelectedDependency fromYAML (scope ConfigParser!YAMLSelectedDependency p)
    {
        import dyaml.node;

        if (p.node.nodeID == NodeID.scalar)
            return YAMLSelectedDependency(Dependency(Version(p.node.as!string)));

        auto d = p.parseAs!SelectedDependency;
        if (d.path.length)
            return YAMLSelectedDependency(Dependency(NativePath(d.path)));
        else
        {
            assert(d.version_.length);
            if (d.repository.length)
                return YAMLSelectedDependency(Dependency(Repository(d.repository, d.version_)));
            return YAMLSelectedDependency(Dependency(Version(d.version_)));
        }
    }
}

// Ensure we can read all type of dependencies
unittest
{
    import configy.Read : parseConfigString;
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
}
