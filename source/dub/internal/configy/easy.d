/*******************************************************************************

    Provide the suggested default configuration for applications

    This module provide the basic tool to quickly get configuration parsing with
    environment and command-line overrides. It assumes a YAML configuration.

    Note:
      This module name is inspired inspired by cURL's 'easy' API.

*******************************************************************************/

module dub.internal.configy.easy;

public import dub.internal.configy.attributes;
public import dub.internal.configy.exceptions : ConfigException;
public import dub.internal.configy.read;

import std.getopt;
import std.typecons : Nullable, nullable;

/// Command-line arguments
public struct CLIArgs
{
    /// Path to the config file
    public string config_path = "config.yaml";

    /// Overrides for config options
    public string[][string] overrides;

    /// Helper to add items to `overrides`
    public void overridesHandler (string, string value)
    {
        import std.string;
        const idx = value.indexOf('=');
        if (idx < 0) return;
        string k = value[0 .. idx], v = value[idx + 1 .. $];
        if (auto val = k in this.overrides)
            (*val) ~= v;
        else
            this.overrides[k] = [ v ];
    }

    /***************************************************************************

        Parses the base command line arguments

        This can be composed with the program argument.
        For example, consider a program which wants to expose a `--version`
        switch, the definition could look like this:
        ---
        public struct ProgramCLIArgs
        {
            public CLIArgs base; // This struct

            public alias base this; // For convenience

            public bool version_; // Program-specific part
        }
        ---
        Then, an application-specific configuration routine would be:
        ---
        public GetoptResult parse (ref ProgramCLIArgs clargs, ref string[] args)
        {
            auto r = clargs.base.parse(args);
            if (r.helpWanted) return r;
            return getopt(
                args,
                "version", "Print the application version, &clargs.version_");
        }
        ---

        Params:
          args = The command line args to parse (parsed options will be removed)
          passThrough = Whether to enable `config.passThrough` and
                        `config.keepEndOfOptions`. `true` by default, to allow
                        composability. If your program doesn't have other
                        arguments, pass `false`.

        Returns:
          The result of calling `getopt`

    ***************************************************************************/

    public GetoptResult parse (ref string[] args, bool passThrough = true)
    {
        return getopt(
            args,
            // `caseInsensistive` is the default, but we need something
            // with the same type for the ternary
            passThrough ? config.keepEndOfOptions : config.caseInsensitive,
            // Also the default, same reasoning
            passThrough ? config.passThrough : config.noPassThrough,
            "config|c",
                "Path to the config file. Defaults to: " ~ this.config_path,
                &this.config_path,

            "override|O",
                "Override a config file value\n" ~
                "Example: -O foo.bar=true -O dns=1.1.1.1 -O dns=2.2.2.2\n" ~
                "Array values are additive, other items are set to the last override",
                &this.overridesHandler,
        );
    }
}

/*******************************************************************************

    Attempt to read and deserialize the config file at `path` into the `struct`
    type `Config` and print any error on failure

    This 'simple' overload of the more detailed `parseConfigFile` will attempt
    to deserialize the content of the file at `path` into an instance of
    `ConfigT`, and return a `Nullable` instance of it.
    If an error happens, either because the file isn't readable or
    the configuration has an issue, a message will be printed to `stderr`,
    with colors if the output is a TTY, and a `null` instance will be returned.

    The calling code can hence just read a config file via:
    ```
    int main ()
    {
        auto configN = parseConfigFileSimple!Config("config.yaml");
        if (configN.isNull()) return 1; // Error path
        auto config = configN.get();
        // Rest of the program ...
    }
    ```
    An overload accepting `CLIArgs args` also exists.

    Params:
        path = Path of the file to read from
        args = Command line arguments on which `parse` has been called
        strict = Whether the parsing should reject unknown keys in the
                 document, warn, or ignore them (default: `StrictMode.Error`)

    Returns:
        An initialized `ConfigT` instance if reading/parsing was successful;
        a `null` instance otherwise.

*******************************************************************************/

public Nullable!ConfigT parseConfigFileSimple (ConfigT)
    (string path, StrictMode strict = StrictMode.Error)
{
    return wrapException(parseConfigFile!(ConfigT)(CLIArgs(path), strict));
}

/// Ditto
public Nullable!ConfigT parseConfigFileSimple (ConfigT)
    (in CLIArgs args, StrictMode strict = StrictMode.Error)
{
    return wrapException(parseConfigFile!(ConfigT)(args, strict));
}

/*******************************************************************************

    Parses the config file or string and returns a `Config` instance.

    Params:
        ConfigT = A `struct` type used to drive the deserialization and
                  validation. This type definition is the most important aspect
                  of how Configy works.

        args = command-line arguments (containing the path to the config)
        path = When parsing a string, the path corresponding to it
        data = A string containing a valid YAML document to be processed
        strict = Whether the parsing should reject unknown keys in the
                 document, warn, or ignore them (default: `StrictMode.Error`)

    Throws:
        `ConfigException` if deserializing the configuration into `ConfigT`
         failed, or an underlying `Exception` if a backend failed (e.g.
         `path` was not found).

    Returns:
        A valid `ConfigT` instance

*******************************************************************************/

public ConfigT parseConfigFile (ConfigT)
    (in CLIArgs args, StrictMode strict = StrictMode.Error)
{
    import dub.internal.configy.backend.yaml;

    auto root = parseFile(args.config_path);
    return parseConfig!ConfigT(root, strict);
}

/// ditto
public ConfigT parseConfigString (ConfigT)
    (string data, string path, StrictMode strict = StrictMode.Error)
{
    CLIArgs args = { config_path: path };
    return parseConfigString!(ConfigT)(data, args, strict);
}

/// ditto
public ConfigT parseConfigString (ConfigT)
    (string data, in CLIArgs args, StrictMode strict = StrictMode.Error)
{
    import dub.internal.configy.backend.yaml;

    assert(args.config_path.length, "No config_path provided to parseConfigString");
    auto root = parseString(data, args.config_path);
    return parseConfig!ConfigT(root, strict);
}

/// ditto
public ConfigT parseConfigStringJSON (ConfigT)
    (string data, string path, StrictMode strict = StrictMode.Error)
{
    import std.exception;
    import dub.internal.configy.backend.json;
    import dub.internal.vibecompat.data.json;

    assert(path.length, "No path provided to parseConfigStringJSON");
    auto root = new JSONNode(parseJsonString(data, path), path).asMapping();
    enforce(root !is null, "Parsing '" ~ path ~ "' didn't yield an object");
    return parseConfig!ConfigT(root, strict);

}
