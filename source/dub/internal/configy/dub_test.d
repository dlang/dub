/*******************************************************************************

    Contains tests for dub-specific extensions

    Whenever integrating changes from upstream configy, most conflicts tend
    to be on `configy.Test`, and as the structure is very similar,
    the default diff algorithms are useless. Having a separate module simplify
    this greatly.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module dub.internal.configy.dub_test;

import dub.internal.configy.attributes;
import dub.internal.configy.easy;

/// Test name pattern matching
unittest
{
    static struct Config
    {
        @StartsWith("names")
        string[][string] names_;
    }

    auto c = parseConfigString!Config(`{ "names-x86": [ "John", "Luca" ], "names": [ "Marie" ] }`, "/dev/null");
    assert(c.names_[null] == [ "Marie" ]);
    assert(c.names_["x86"] == [ "John", "Luca" ]);
}
