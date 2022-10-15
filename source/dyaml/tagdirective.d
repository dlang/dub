
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

///Tag directives.
module dyaml.tagdirective;

///Single tag directive. handle is the shortcut, prefix is the prefix that replaces it.
struct TagDirective
{
    string handle;
    string prefix;
}
