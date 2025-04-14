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

module dub.internal.configy.attributes;

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

    A field which carries informations about whether it was set or not

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

    Interface that is passed to `fromConfig` hook

    The `ConfigParser` exposes the raw underlying node (see `node` method),
    the path within the file (`path` method), and a simple ability to recurse
    via `parseAs`. This allows to implement complex logic independent of the
    underlying configuration format.

*******************************************************************************/

public interface ConfigParser
{
    import dub.internal.configy.backend.node;
    import dub.internal.configy.fieldref : StructFieldRef;
    import dub.internal.configy.read : Context, parseField;

    /// Returns: the node being processed
    public inout(Node) node () inout @safe pure nothrow @nogc;

    /// Returns: current location we are parsing
    public string path () const @safe pure nothrow @nogc;

    /***************************************************************************

        Parse this struct as another type

        This allows implementing union-like behavior, where a `struct` which
        implements `fromConfig` can parse a simple representation as one type,
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

/*******************************************************************************

    Specify that a field only accept a limited set of string values.

    This is similar to how `enum` symbolic names are treated, however the `enum`
    symbolic names may not contain spaces or special character.

    Params:
      Values = Permissible values (case sensitive)

*******************************************************************************/

public struct Only (string[] Values) {
    public string value;

    alias value this;

    public static Only fromString (scope string str) {
        import std.algorithm.searching : canFind;
        import std.exception : enforce;
        import std.format;

        enforce(Values.canFind(str),
            "%s is not a valid value for this field, valid values are: %(%s, %)"
            .format(str, Values));
        return Only(str);
    }
}

///
unittest {
    import dub.internal.configy.attributes : Only, Optional;
    import dub.internal.configy.easy : parseConfigString;

    static struct CountryConfig {
        Only!(["France", "Malta", "South Korea"]) country;
        // Compose with other attributes too
        @Optional Only!(["citizen", "resident", "alien"]) status;
    }
    static struct Config {
        CountryConfig[] countries;
    }

    auto conf = parseConfigString!Config(`countries:
  - country: France
    status: citizen
  - country: Malta
  - country: South Korea
    status: alien
`, "/dev/null");

    assert(conf.countries.length == 3);
    assert(conf.countries[0].country == `France`);
    assert(conf.countries[0].status  == `citizen`);
    assert(conf.countries[1].country == `Malta`);
    assert(conf.countries[1].status  is null);
    assert(conf.countries[2].country == `South Korea`);
    assert(conf.countries[2].status  == `alien`);

    import dub.internal.configy.exceptions : ConfigException;

    try parseConfigString!Config(`countries:
  - country: France
    status: expatriate
`, "/etc/config");
    catch (ConfigException exc)
        assert(exc.toString() == `/etc/config(3:13): countries[0].status: expatriate is not a valid value for this field, valid values are: "citizen", "resident", "alien"`);
}
