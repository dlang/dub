/*******************************************************************************

    Define UDAs that can be applied to a configuration struct

    This module is stand alone (a leaf module) to allow importing the UDAs
    without importing the whole configuration parsing code.

    Copyright:
        Copyright (c) 2019-2022 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module dub.internal.configy.Attributes;

import std.traits;

/*******************************************************************************

    An optional parameter with an initial value of `T.init`

    The config parser automatically recognize non-default initializer,
    so that the following:
    ```
    public struct Config
    {
        public string greeting = "Welcome home";
    }
    ```
    Will not error out if `greeting` is not defined in the config file.
    However, this relies on the initializer of the field (`greeting`) being
    different from the type initializer (`string.init` is `null`).
    In some cases, the default value is also the desired initializer, e.g.:
    ```
    public struct Config
    {
        /// Maximum number of connections. 0 means unlimited.
        public uint connections_limit = 0;
    }
    ```
    In this case, one can add `@Optional` to the field to inform the parser.

*******************************************************************************/

public struct Optional {}

/*******************************************************************************

    Inform the config filler that this sequence is to be read as a mapping

    On some occasions, one might want to read a mapping as an array.
    One reason to do so may be to provide a better experience to the user,
    e.g. having to type:
    ```
    interfaces:
      eth0:
        ip: "192.168.0.1"
        private: true
      wlan0:
        ip: "1.2.3.4"
    ```
    Instead of the slightly more verbose:
    ```
    interfaces:
      - name: eth0
        ip: "192.168.0.1"
        private: true
      - name: wlan0
        ip: "1.2.3.4"
    ```

    The former would require to be expressed as an associative arrays.
    However, one major drawback of associative arrays is that they can't have
    an initializer, which makes them cumbersome to use in the context of the
    config filler. To remediate this issue, one may use `@Key("name")`
    on a field (here, `interfaces`) so that the mapping is flattened
    to an array. If `name` is `null`, the key will be discarded.

*******************************************************************************/

public struct Key
{
    ///
    public string name;
}

/*******************************************************************************

    Look up the provided name in the YAML node, instead of the field name.

    By default, the config filler will look up the field name of a mapping in
    the YAML node. If this is not desired, an explicit `Name` attribute can
    be given. This is especially useful for names which are keyword.

    ```
    public struct Config
    {
        public @Name("delete") bool remove;
    }
    ```

*******************************************************************************/

public struct Name
{
    ///
    public string name;

    ///
    public bool startsWith;
}

/// Short hand syntax
public Name StartsWith(string name) @safe pure nothrow @nogc
{
    return Name(name, true);
}

/*******************************************************************************

    A field which carries information about whether it was set or not

    Some configurations may need to know which fields were set explicitly while
    keeping defaults. An example of this is a `struct` where at least one field
    needs to be set, such as the following:
    ```
    public struct ProtoDuration
    {
        public @Optional long weeks;
        public @Optional long days;
        public @Optional long hours;
        public @Optional long minutes;
        public           long seconds = 42;
        public @Optional long msecs;
        public @Optional long usecs;
        public @Optional long hnsecs;
        public @Optional long nsecs;
    }
    ```
    In this case, it would be impossible to know if any field was explicitly
    provided. Hence, the struct should be written as:
    ```
    public struct ProtoDuration
    {
        public SetInfo!long weeks;
        public SetInfo!long days;
        public SetInfo!long hours;
        public SetInfo!long minutes;
        public SetInfo!long seconds = 42;
        public SetInfo!long msecs;
        public SetInfo!long usecs;
        public SetInfo!long hnsecs;
        public SetInfo!long nsecs;
    }
    ```
    Note that `SetInfo` implies `Optional`, and supports default values.

*******************************************************************************/

public struct SetInfo (T)
{
    /***************************************************************************

        Allow initialization as a field

        This sets the field as having been set, so that:
        ```
        struct Config { SetInfo!Duration timeout; }

        Config myConf = { timeout: 10.minutes }
        ```
        Will behave as if set explicitly. If this behavior is not wanted,
        pass `false` as second argument:
        ```
        Config myConf = { timeout: SetInfo!Duration(10.minutes, false) }
        ```

    ***************************************************************************/

    public this (T initVal, bool isSet = true) @safe pure nothrow @nogc
    {
        this.value = initVal;
        this.set = isSet;
    }

    /// Underlying data
    public T value;

    ///
    alias value this;

    /// Whether this field was set or not
    public bool set;
}

/*******************************************************************************

    Provides a means to convert a field from a `Node` to a complex type

    When filling the config, it might be useful to store types which are
    not only simple `string` and integer, such as `URL`, `BigInt`, or any other
    library type not directly under the user's control.

    To allow reading those values from the config file, a `Converter` may
    be used. The converter will tell the `ConfigFiller` how to convert from
    `Node` to the desired type `T`.

    If the type is under the user's control, one can also add a constructor
    accepting a single string, or define the `fromString` method, both of which
    are tried if no `Converter` is found.

    For types not under the user's control, there might be different ways
    to parse the same type within the same struct, or neither the ctor nor
    the `fromString` method may be defined under that name.
    The exmaple below uses `parse` in place of `fromString`, for example.

    ```
    /// Complex structure representing the age of a person based on its birthday
    public struct Age
    {
        ///
        public uint birth_year;
        ///
        public uint birth_month;
        ///
        public uint birth_day;

        /// Note that this will be picked up automatically if named `fromString`
        /// but this struct might be a library type.
        public static Age parse (string value) { /+ Magic +/ }
    }

    public struct Person
    {
        ///
        @Converter!Age((Node value) => Age.parse(value.as!string))
        public Age age;
    }
    ```

    Note that some fields may also be of multiple YAML types, such as DUB's
    `dependencies`, which is either a simple string (`"vibe-d": "~>1.0 "`),
    or an in its complex form (`"vibe-d": { "version": "~>1.0" }`).
    For those use cases, a `Converter` is the best approach.

    To avoid repeating the field type, a convenience function is provided:
    ```
    public struct Age
    {
        public uint birth_year;
        public uint birth_month;
        public uint birth_day;
        public static Age parse (string value) { /+ Magic +/ }
    }

    public struct Person
    {
        /// Here `converter` will deduct the type from the delegate argument,
        /// and return an instance  of `Converter`. Mind the case.
        @converter((Node value) => Age.parse(value.as!string))
        public Age age;
    }
    ```

*******************************************************************************/

public struct Converter (T)
{
    ///
    public alias ConverterFunc = T function (scope ConfigParser!T context);

    ///
    public ConverterFunc converter;
}

/// Ditto
public auto converter (FT) (FT func)
{
    static assert(isFunctionPointer!FT,
                  "Error: Argument to `converter` should be a function pointer, not: "
                  ~ FT.stringof);

    alias RType = ReturnType!FT;
    static assert(!is(RType == void),
                  "Error: Converter needs to be of the return type of the field, not `void`");
    return Converter!RType(func);
}

/*******************************************************************************

    Interface that is passed to `fromYAML` hook

    The `ConfigParser` exposes the raw YAML node (`see `node` method),
    the path within the file (`path` method), and a simple ability to recurse
    via `parseAs`.

    Params:
      T = The type of the structure which defines a `fromYAML` hook

*******************************************************************************/

public interface ConfigParser (T)
{
    import dub.internal.dyaml.node;
    import dub.internal.configy.FieldRef : StructFieldRef;
    import dub.internal.configy.Read : Context, parseField;

    /// Returns: the node being processed
    public inout(Node) node () inout @safe pure nothrow @nogc;

    /// Returns: current location we are parsing
    public string path () const @safe pure nothrow @nogc;

    /***************************************************************************

        Parse this struct as another type

        This allows implementing union-like behavior, where a `struct` which
        implements `fromYAML` can parse a simple representation as one type,
        and one more advanced as another type.

        Params:
          OtherType = The type to parse as
          defaultValue = The instance to use as a default value for fields

    ***************************************************************************/

    public final auto parseAs (OtherType)
        (auto ref OtherType defaultValue = OtherType.init)
    {
        alias TypeFieldRef = StructFieldRef!OtherType;
        return this.node().parseField!(TypeFieldRef)(
            this.path(), defaultValue, this.context());
    }

    /// Internal use only
    protected const(Context) context () const @safe pure nothrow @nogc;
}
