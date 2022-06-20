
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

///YAML node formatting styles.
module dyaml.style;


///Scalar styles.
enum ScalarStyle : ubyte
{
    /// Invalid (uninitialized) style
    invalid = 0,
    /// `|` (Literal block style)
    literal,
    /// `>` (Folded block style)
    folded,
    /// Plain scalar
    plain,
    /// Single quoted scalar
    singleQuoted,
    /// Double quoted scalar
    doubleQuoted
}

///Collection styles.
enum CollectionStyle : ubyte
{
    /// Invalid (uninitialized) style
    invalid = 0,
    /// Block style.
    block,
    /// Flow style.
    flow
}
