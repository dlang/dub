/*******************************************************************************

    Contains struct definition for settings.json files

    User settings are file that allow to configure dub default behavior.

*******************************************************************************/

module dub.data.settings;

import dub.internal.configy.Attributes;
import dub.internal.vibecompat.inet.path;

/// Determines which of the default package suppliers are queried for packages.
public enum SkipPackageSuppliers {
    none,       /// Uses all configured package suppliers.
    standard,   /// Does not use the default package suppliers (`defaultPackageSuppliers`).
    configured, /// Does not use default suppliers or suppliers configured in DUB's configuration file
    all,        /// Uses only manually specified package suppliers.
}

/**
 * User-provided settings (configuration)
 *
 * All fields in this struct should be optional.
 * Fields that are *not* optional should be mandatory from the POV
 * of the application, not the POV of file parsing.
 * For example, git's `core.author` and `core.email` are required to commit,
 * but the error happens on the commit, not when the gitconfig is parsed.
 *
 * We have multiple configuration locations, and two kinds of fields:
 * additive and non-additive. Additive fields are fields which are the union
 * of all configuration files (e.g. `registryURLs`). Non-additive fields
 * will ignore values set in lower priorities configuration, although parsing
 * must still succeed. Additive fields are marked as `@Optional`,
 * non-additive are marked as `SetInfo`.
 */
package(dub) struct Settings {
    @Optional string[] registryUrls;
    @Optional NativePath[] customCachePaths;

    SetInfo!(SkipPackageSuppliers) skipRegistry;
    SetInfo!(string) defaultCompiler;
    SetInfo!(string) defaultArchitecture;
    SetInfo!(bool) defaultLowMemory;

    SetInfo!(string[string]) defaultEnvironments;
    SetInfo!(string[string]) defaultBuildEnvironments;
    SetInfo!(string[string]) defaultRunEnvironments;
    SetInfo!(string[string]) defaultPreGenerateEnvironments;
    SetInfo!(string[string]) defaultPostGenerateEnvironments;
    SetInfo!(string[string]) defaultPreBuildEnvironments;
    SetInfo!(string[string]) defaultPostBuildEnvironments;
    SetInfo!(string[string]) defaultPreRunEnvironments;
    SetInfo!(string[string]) defaultPostRunEnvironments;
    SetInfo!(string) dubHome;

    /// Merge a lower priority config (`this`) with a `higher` priority config
    public Settings merge(Settings higher)
        return @safe pure nothrow
    {
        import std.traits : hasUDA;
        Settings result;

        static foreach (idx, _; Settings.tupleof) {
            static if (hasUDA!(Settings.tupleof[idx], Optional))
                result.tupleof[idx] = higher.tupleof[idx] ~ this.tupleof[idx];
            else static if (IsSetInfo!(typeof(this.tupleof[idx]))) {
                if (higher.tupleof[idx].set)
                    result.tupleof[idx] = higher.tupleof[idx];
                else
                    result.tupleof[idx] = this.tupleof[idx];
            } else
                static assert(false,
                              "Expect `@Optional` or `SetInfo` on: `" ~
                              __traits(identifier, this.tupleof[idx]) ~
                              "` of type : `" ~
                              typeof(this.tupleof[idx]).stringof ~ "`");
        }

        return result;
    }

    /// Workaround multiple `E` declaration in `static foreach` when inline
    private template IsSetInfo(T) { enum bool IsSetInfo = is(T : SetInfo!E, E); }
}

unittest {
    import dub.internal.configy.Read;

    const str1 = `{
  "registryUrls": [ "http://foo.bar\/optional\/escape" ],
  "customCachePaths": [ "foo/bar", "foo/foo" ],

  "skipRegistry": "all",
  "defaultCompiler": "dmd",
  "defaultArchitecture": "fooarch",
  "defaultLowMemory": false,

  "defaultEnvironments": {
    "VAR2": "settings.VAR2",
    "VAR3": "settings.VAR3",
    "VAR4": "settings.VAR4"
  }
}`;

    const str2 = `{
  "registryUrls": [ "http://bar.foo" ],
  "customCachePaths": [ "bar/foo", "bar/bar" ],

  "skipRegistry": "none",
  "defaultCompiler": "ldc",
  "defaultArchitecture": "bararch",
  "defaultLowMemory": true,

  "defaultEnvironments": {
    "VAR": "Hi",
  }
}`;

     auto c1 = parseConfigString!Settings(str1, "/dev/null");
     assert(c1.registryUrls == [ "http://foo.bar/optional/escape" ]);
     assert(c1.customCachePaths == [ NativePath("foo/bar"), NativePath("foo/foo") ]);
     assert(c1.skipRegistry == SkipPackageSuppliers.all);
     assert(c1.defaultCompiler == "dmd");
     assert(c1.defaultArchitecture == "fooarch");
     assert(c1.defaultLowMemory == false);
     assert(c1.defaultEnvironments.length == 3);
     assert(c1.defaultEnvironments["VAR2"] == "settings.VAR2");
     assert(c1.defaultEnvironments["VAR3"] == "settings.VAR3");
     assert(c1.defaultEnvironments["VAR4"] == "settings.VAR4");

     auto c2 = parseConfigString!Settings(str2, "/dev/null");
     assert(c2.registryUrls == [ "http://bar.foo" ]);
     assert(c2.customCachePaths == [ NativePath("bar/foo"), NativePath("bar/bar") ]);
     assert(c2.skipRegistry == SkipPackageSuppliers.none);
     assert(c2.defaultCompiler == "ldc");
     assert(c2.defaultArchitecture == "bararch");
     assert(c2.defaultLowMemory == true);
     assert(c2.defaultEnvironments.length == 1);
     assert(c2.defaultEnvironments["VAR"] == "Hi");

     auto m1 = c2.merge(c1);
     // c1 takes priority, so its registryUrls is first
     assert(m1.registryUrls == [ "http://foo.bar/optional/escape", "http://bar.foo" ]);
     // Same with CCP
     assert(m1.customCachePaths == [
         NativePath("foo/bar"), NativePath("foo/foo"),
         NativePath("bar/foo"), NativePath("bar/bar"),
     ]);

     // c1 fields only
     assert(m1.skipRegistry == c1.skipRegistry);
     assert(m1.defaultCompiler == c1.defaultCompiler);
     assert(m1.defaultArchitecture == c1.defaultArchitecture);
     assert(m1.defaultLowMemory == c1.defaultLowMemory);
     assert(m1.defaultEnvironments == c1.defaultEnvironments);

     auto m2 = c1.merge(c2);
     assert(m2.registryUrls == [ "http://bar.foo", "http://foo.bar/optional/escape" ]);
     assert(m2.customCachePaths == [
         NativePath("bar/foo"), NativePath("bar/bar"),
         NativePath("foo/bar"), NativePath("foo/foo"),
     ]);
     assert(m2.skipRegistry == c2.skipRegistry);
     assert(m2.defaultCompiler == c2.defaultCompiler);
     assert(m2.defaultArchitecture == c2.defaultArchitecture);
     assert(m2.defaultLowMemory == c2.defaultLowMemory);
     assert(m2.defaultEnvironments == c2.defaultEnvironments);

     auto m3 = Settings.init.merge(c1);
     assert(m3 == c1);
}
