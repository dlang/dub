/*******************************************************************************

    Implement a template to keep track of a field references

    Passing field references by `alias` template parameter creates many problem,
    and is extremely cumbersome to work with. Instead, we pass an instance of
    a `FieldRef` around, which also contains structured information.

    Copyright:
        Copyright (c) 2019-2022 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module dub.internal.configy.FieldRef;

// Renamed imports as the names exposed by `FieldRef` shadow the imported ones.
import dub.internal.configy.Attributes : CAName = Name, CAOptional = Optional, SetInfo;

import std.meta;
import std.traits;

/*******************************************************************************

    A reference to a field in a `struct`

    The compiler sometimes rejects passing fields by `alias`, or complains about
    missing `this` (meaning it tries to evaluate the value). Sometimes, it also
    discards the UDAs.

    To prevent this from happening, we always pass around a `FieldRef`,
    which wraps the parent struct type (`T`), the name of the field
    as `FieldName`, and other informations.

    To avoid any issue, eponymous usage is also avoided, hence the reference
    needs to be accessed using `Ref`.

*******************************************************************************/

package template FieldRef (alias T, string name, bool forceOptional = false)
{
    /// The reference to the field
    public alias Ref = __traits(getMember, T, name);

    /// Type of the field
    public alias Type = typeof(Ref);

    /// The name of the field in the struct itself
    public alias FieldName = name;

    /// The name used in the configuration field (taking `@Name` into account)
    static if (hasUDA!(Ref, CAName))
    {
        static assert (getUDAs!(Ref, CAName).length == 1,
                       "Field `" ~ fullyQualifiedName!(Ref) ~
                       "` cannot have more than one `Name` attribute");

        public immutable Name = getUDAs!(Ref, CAName)[0].name;

        public immutable Pattern = getUDAs!(Ref, CAName)[0].startsWith;
    }
    else
    {
        public immutable Name = FieldName;
        public immutable Pattern = false;
    }

    /// Default value of the field (may or may not be `Type.init`)
    public enum Default = __traits(getMember, T.init, name);

    /// Evaluates to `true` if this field is to be considered optional
    /// (does not need to be present in the YAML document)
    public enum Optional = forceOptional ||
        hasUDA!(Ref, CAOptional) ||
        is(immutable(Type) == immutable(bool)) ||
        is(Type : SetInfo!FT, FT) ||
        (Default != Type.init);
}

unittest
{
    import dub.internal.configy.Attributes : Name;

    static struct Config1
    {
        int integer2 = 42;
        @Name("notStr2")
        @(42) string str2;
    }

    static struct Config2
    {
        Config1 c1dup = { 42, "Hello World" };
        string message = "Something";
    }

    static struct Config3
    {
        Config1 c1;
        int integer;
        string str;
        Config2 c2 = { c1dup: { integer2: 69 } };
    }

    static assert(is(FieldRef!(Config3, "c2").Type == Config2));
    static assert(FieldRef!(Config3, "c2").Default != Config2.init);
    static assert(FieldRef!(Config2, "message").Default == Config2.init.message);
    alias NFR1 = FieldRef!(Config3, "c2");
    alias NFR2 = FieldRef!(NFR1.Ref, "c1dup");
    alias NFR3 = FieldRef!(NFR2.Ref, "integer2");
    alias NFR4 = FieldRef!(NFR2.Ref, "str2");
    static assert(hasUDA!(NFR4.Ref, int));

    static assert(FieldRefTuple!(Config3)[1].Name == "integer");
    static assert(FieldRefTuple!(FieldRefTuple!(Config3)[0].Type)[1].Name == "notStr2");
}

/// A pseudo `FieldRef` used for structs which are not fields (top-level)
package template StructFieldRef (ST, string DefaultName = null)
{
    ///
    public enum Ref = ST.init;

    ///
    public alias Type = ST;

    ///
    public enum Default = ST.init;

    ///
    public enum Optional = false;

    /// Some places reference their parent's Name / FieldName
    public enum Name = DefaultName;
    /// Ditto
    public enum FieldName = DefaultName;
}

/// A pseudo `FieldRef` for nested types (e.g. arrays / associative arrays)
package template NestedFieldRef (ElemT, alias FR)
{
    ///
    public enum Ref = ElemT.init;
    ///
    public alias Type = ElemT;
    ///
    public enum Name = FR.Name;
    ///
    public enum FieldName = FR.FieldName;
    /// Element or keys are never optional
    public enum Optional = false;

}

/// Get a tuple of `FieldRef` from a `struct`
package template FieldRefTuple (T)
{
    static assert(is(T == struct),
                  "Argument " ~ T.stringof ~ " to `FieldRefTuple` should be a `struct`");

    ///
    static if (__traits(getAliasThis, T).length == 0)
        public alias FieldRefTuple = staticMap!(Pred, FieldNameTuple!T);
    else
    {
        /// Tuple of strings of aliased fields
        /// As of DMD v2.100.0, only a single alias this is supported in D.
        private immutable AliasedFieldNames = __traits(getAliasThis, T);
        static assert(AliasedFieldNames.length == 1, "Multiple `alias this` are not supported");

        // Ignore alias to functions (if it's a property we can't do anything)
        static if (isSomeFunction!(__traits(getMember, T, AliasedFieldNames)))
            public alias FieldRefTuple = staticMap!(Pred, FieldNameTuple!T);
        else
        {
            /// "Base" field names minus aliased ones
            private immutable BaseFields = Erase!(AliasedFieldNames, FieldNameTuple!T);
            static assert(BaseFields.length == FieldNameTuple!(T).length - 1);

            public alias FieldRefTuple = AliasSeq!(
                staticMap!(Pred, BaseFields),
                FieldRefTuple!(typeof(__traits(getMember, T, AliasedFieldNames))));
        }
    }

    private alias Pred (string name) = FieldRef!(T, name);
}

/// Returns: An alias sequence of field names, taking UDAs (`@Name` et al) into account
package alias FieldsName (T) = staticMap!(FieldRefToName, FieldRefTuple!T);

/// Helper template for `staticMap` used for strict mode
private enum FieldRefToName (alias FR) = FR.Name;

/// Dub extension
package enum IsPattern (alias FR) = FR.Pattern;
/// Dub extension
package alias Patterns (T) = staticMap!(FieldRefToName, Filter!(IsPattern, FieldRefTuple!T));
