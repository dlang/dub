/*******************************************************************************

    Contains tests for dub-specific extensions

    Whenever integrating changes from upstream configy, most conflicts tend
    to be on `configy.Test`, and as the structure is very similar,
    the default diff algorithms are useless. Having a separate module simplify
    this greatly.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module configy.DubTest;

import configy.Attributes;
import configy.Read;

import dyaml.node;

/// Test name pattern matching
unittest
{
    static struct Config
    {
        @StartsWith("names")
        string[][string] names_;
    }

    auto c = parseConfigString!Config("names-x86:\n  - John\n  - Luca\nnames:\n  - Marie", "/dev/null");
    assert(c.names_[null] == [ "Marie" ]);
    assert(c.names_["x86"] == [ "John", "Luca" ]);
}

/// Test our `fromYAML` extension
unittest
{
    static struct PackageDef
    {
        string name;
        @Optional string target;
        int build = 42;
    }

    static struct Package
    {
        string path;
        PackageDef def;

        public static Package fromYAML (scope ConfigParser!Package parser)
        {
            if (parser.node.nodeID == NodeID.mapping)
                return Package(null, parser.parseAs!PackageDef);
            else
                return Package(parser.parseAs!string);
        }
    }

    static struct Config
    {
        string name;
        Package[] deps;
    }

    auto c = parseConfigString!Config(
`
name: myPkg
deps:
  - /foo/bar
  - name: foo
    target: bar
    build: 24
  - name: fur
  - /one/last/path
`, "/dev/null");
    assert(c.name == "myPkg");
    assert(c.deps.length == 4);
    assert(c.deps[0] == Package("/foo/bar"));
    assert(c.deps[1] == Package(null, PackageDef("foo", "bar", 24)));
    assert(c.deps[2] == Package(null, PackageDef("fur", null, 42)));
    assert(c.deps[3] == Package("/one/last/path"));
}
