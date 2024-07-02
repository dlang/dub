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
    default_,   /// The value wasn't specified. It is provided in order to know when it is safe to ignore it
}

/// Transitional structure used to mix `UserConfiguration` and `OldUserConfiguration`
package(dub) struct InternalSettings {
    /// registryUrls behaves differently with the new syntax
    public string[] registryUrls;
    /// This field is no longer present in the new syntax (absorbed)
    public SetInfo!(SkipPackageSuppliers) skipRegistry;

    /// Configuration itself
    public Settings config;

    ///
    alias config this;
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
    /// Configuration that affect all of dub
    private struct DubConfig
    {
        /**
         * Control where the user directory is placed.
         *
         * The user directory is the place where Dub downloads packages
         * and store build artifacts by default. This location defaults to:
         * - `$HOME/.dub/`, also known as `~/.dub/`, on Linux;
         * - A mix of `%APPDATA%/dub/` and `%LOCALAPPDATA%/dub/` on Windows;
         *
         * The `dub.home` settings allows to set Dub's home directory explicitly.
         * Not that if this is read from the config file located in the home
         * directory (using one of the location listed above), no configuration
         * will be read from the explicitly-set value, and only packages
         * will be stored there.
         *
         * This field supports environment variables.
         *
         * ```
         * # This file is located in /etc/dub/settings.yaml
         * # Overwrite the user repository to be in $HOME/dlang alongside `install.sh`
         * dub:
         *   home: /home/$USERNAME/dlang/dub-home/
         * ```
         *
         * ```
         * # This file is located in /home/$USERNAME/.dub/settings.yaml
         * # Store all packages downloaded in the temp folder.
         * dub:
         *   home: /tmp/dub-packages/
         * ```
         */
        public SetInfo!(string) home;

        /**
         * Extra locations where to look for packages
         *
         * This is usually used to load packages installed through other means
         * than `dub fetch`, such as a distribution's package manager.
         *
         * Those locations are assumed to be read only and to follow the same
         * directory structure as dub uses, which is
         * `$PACKAGE_FOLDER/$PACKAGE_NAME-$PACKAGE_VERSION/$PACKAGE_NAME/`.
         *
         * This property is additive: if `dub.extraPackages` is specified
         * in a system configuration and a user configuration,
         * the user-configured locations will be searched first,
         * then the system ones. Hence, is a package that is found both in
         * `extraPackages` and `dub fetch`-ed,
         * the fetched one will take precedence.
         *
         * ```
         * dub:
         *   extraPackages:
         *     - "/usr/lib/dlang/"
         * ```
         */
        public @Optional NativePath[] extraPackages;

        /**
         * Adds or overrides environment variables for each command
         *
         * Various parts of dub are able to use environment variables.
         * This variable allows to set global environment variables,
         * that will be available to every environment-user.
         *
         * The following, more fine grained variables are also accessible:
         * - `build.environment`: For variable only accessible when building a project;
         * - `build.preGenerateEnvironment`: For variable only accessible in `preGenerateCommands`;
         * - `build.postGenerateEnvironment`: For variable only accessible in `postGenerateCommands`;
         * - `build.preBuildEnvironment`: For variable only accessible in `preGenerateCommands`;
         * - `build.postBuildEnvironment`: For variable only accessible in `postGenerateCommands`;
         * - `run.environment`: For variable only accessible when running a project;
         *
         * ```
         * # Overwrite the global environment username and add some CI variable
         * dub:
         *   environment:
         *     USERNAME: dman
         *     CI_MAX_RUN_TIME_SECONDS: 180
         * ```
         *
         * Fields are additive: if `dub.environment`, `build.environment,
         * `build.preBuildEnvironment` are defined, all variables defined in
         * it will be available to `preBuildCommands`,
         * with variables in `build.preBuildEnvironment` taking precedence
         * over variables in `build.environment`, themselves taking precedence
         * over variables in `dub.environment`.
         *
         * However, while parsing configuration files, only the most-specialized
         * `environment` is retained.
         */
        public SetInfo!(string[string]) environment;
    }

    /// Ditto
    public DubConfig dub;

    /// Configuration that affects the `fetch` command or dependent
    private struct FetchConfig
    {
        /**
         * The list of registries to use
         *
         * By default, this is set to the list of default registries.
         * If you wish to use a different set of registries (e.g. company ones),
         * setting this properties overwrites them.
         *
         * ```
         * # This uses no registry
         * fetch:
         *   registries: []
         * ```
         *
         * ```
         * # This uses a corporate registry plus the default ones
         * fetch:
         *   registries:
         *     - https://dub.myfancy.corp/token/private
         *     - https://code.dlang.org/
         *     - https://codemirror.dlang.org/
         *     - https://dub.bytecraft.nl/
         *     - https://code-mirror.dlang.io/
         * ```
         */
        public SetInfo!(string[]) registries = SetInfo!(string[])(
            [ "https://code.dlang.org/", "https://codemirror.dlang.org/" ],
            false);
;
    }

    /// Ditto
    public FetchConfig fetch;

    /// Configuration that affects the `generate` command or indirect invocations
    private struct GenerateConfig
    {
        /**
         * Additional environment variables available in `preGenerateCommands`
         *
         * For an extended description of this field and how it interacts
         * with other similar variables, see `dub.environment` which includes
         * a complete description.
         */
        public SetInfo!(string[string]) preGenerateEnvironment;

        /**
         * Additional environment variables available in `postGenerateCommands`
         *
         * For an extended description of this field and how it interacts
         * with other similar variables, see `dub.environment` which includes
         * a complete description.
         */
        public SetInfo!(string[string]) postGenerateEnvironment;
    }

    /// Ditto
    public GenerateConfig generate;


    /// Configuration that affects the `build` command or indirect invocations
    private struct BuildConfig
    {
        /**
         * The default compiler to use when building a project
         *
         * This is similar to passing `--compiler` to every dub invocation.
         * The values can be either a path or a binary in the path.
         *
         * ```
         * build:
         *   compiler: /usr/bin/ldc2
         * ```
         *
         * ```
         * build:
         *   compiler: gdc-12
         * ```
         */
        public SetInfo!(string) compiler;

        /**
         * The default architecture to target when building a project
         *
         * This is similar to passing `--arch` to every dub invocation.
         * The values are expected to be a target triplet.
         *
         * ```
         * build:
         *   compiler: ldc2
         *   architecture: aarch64-unknown-linux-android
         * ```
         *
         * If not specified, the architecture targeted is the host one.
         */
        public SetInfo!(string) architecture;

        /**
         * Whether `-lowmem` is passed to the compiler on builds
         *
         * By default, `-lowmem` is not used, which can lead to large memory
         * usage while building, or even compiler aborting compilation.
         * Setting this value to `true` will enable the GC in the compiler.
         */
        public SetInfo!(bool) lowmem;


        /**
         * Additional environment variables available while building a project
         *
         * For an extended description of this field and how it interacts
         * with other similar variables, see `dub.environment` which includes
         * a complete description.
         */
        public SetInfo!(string[string]) environment;

        /**
         * Additional environment variables available in `preBuildCommands`
         *
         * For an extended description of this field and how it interacts
         * with other similar variables, see `dub.environment` which includes
         * a complete description.
         */
        public SetInfo!(string[string]) preBuildEnvironment;

        /**
         * Additional environment variables available in `postBuildCommands`
         *
         * For an extended description of this field and how it interacts
         * with other similar variables, see `dub.environment` which includes
         * a complete description.
         */
        public SetInfo!(string[string]) postBuildEnvironment;
    }

    /// Ditto
    public BuildConfig build;

    /// Configuration that affects the `run` command
    private struct RunConfig
    {
        /**
         * Additional environment variables available while running a project
         *
         * For an extended description of this field and how it interacts
         * with other similar variables, see `dub.environment` which includes
         * a complete description.
         */
        public SetInfo!(string[string]) environment;

        /**
         * Additional environment variables available in `preRunCommands`
         *
         * For an extended description of this field and how it interacts
         * with other similar variables, see `dub.environment` which includes
         * a complete description.
         */
        public SetInfo!(string[string]) preRunEnvironment;

        /**
         * Additional environment variables available in `postRunCommands`
         *
         * For an extended description of this field and how it interacts
         * with other similar variables, see `dub.environment` which includes
         * a complete description.
         */
        public SetInfo!(string[string]) postRunEnvironment;
    }

    /// Ditto
    public RunConfig run;

    /// Merge a lower priority config (`this`) with a `higher` priority config
    public Settings merge(Settings higher) return @safe pure nothrow
    {
        return .merge(this, higher);
    }

    /// Ditto
    public Settings merge(
        OldSettings higher, ref string[] registryUrls,
        ref SetInfo!(SkipPackageSuppliers) skipRegistry)
        return @safe pure nothrow
    {
        Settings result = this;
        // Handle `dub` section
        if (higher.dubHome.set)
            result.dub.home = higher.dubHome;
        if (higher.customCachePaths.length)
            result.dub.extraPackages ~= higher.customCachePaths;
        if (higher.defaultEnvironments.set)
            result.dub.environment = higher.defaultEnvironments;

        // Handle `generate`
        if (higher.defaultPreGenerateEnvironments.set)
            result.generate.preGenerateEnvironment = higher.defaultPreGenerateEnvironments;
        if (higher.defaultPostGenerateEnvironments.set)
            result.generate.postGenerateEnvironment = higher.defaultPostGenerateEnvironments;

        // Handle `build` section
        if (higher.defaultCompiler.set)
            result.build.compiler = higher.defaultCompiler;
        if (higher.defaultArchitecture.set)
            result.build.architecture = higher.defaultArchitecture;
        if (higher.defaultLowMemory.set)
            result.build.lowmem = higher.defaultLowMemory;
        if (higher.defaultBuildEnvironments.set)
            result.build.environment = higher.defaultBuildEnvironments;
        if (higher.defaultPreBuildEnvironments.set)
            result.build.preBuildEnvironment = higher.defaultPreBuildEnvironments;
        if (higher.defaultPostBuildEnvironments.set)
            result.build.postBuildEnvironment = higher.defaultPostBuildEnvironments;

        // Handling fetch is quite complex due to the two fields being reduced
        // to a single one, so we do it in the caller instead.
        if (higher.registryUrls.length)
            registryUrls ~= higher.registryUrls;
        if (higher.skipRegistry.set)
            skipRegistry = SetInfo!SkipPackageSuppliers(higher.skipRegistry.value);

        // Handle `run` section
        if (higher.defaultRunEnvironments.set)
            result.run.environment = higher.defaultRunEnvironments;
        if (higher.defaultPreRunEnvironments.set)
            result.run.preRunEnvironment = higher.defaultPreRunEnvironments;
        if (higher.defaultPostRunEnvironments.set)
            result.run.postRunEnvironment = higher.defaultPostRunEnvironments;

        return result;
    }
}

/// Ditto
package(dub) struct OldSettings {
    @Optional string[] registryUrls;
    @Optional NativePath[] customCachePaths;

    private struct SkipRegistry {
	    SkipPackageSuppliers skipRegistry;
	    static SkipRegistry fromString (string value) {
		    import std.conv : to;
		    auto result = value.to!SkipPackageSuppliers;
		    if (result == SkipPackageSuppliers.default_) {
			    throw new Exception(
				"skipRegistry value `default_` is only meant for interal use."
				~ " Instead, use one of `none`, `standard`, `configured`, or `all`."
						);
		    }
		    return SkipRegistry(result);
	    }
	    alias skipRegistry this;
    }
    SetInfo!(SkipRegistry) skipRegistry;
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
}

/// Merge a lower priority config (`this_`) with a `higher` priority config
public T merge(T)(T this_, T higher) @safe pure nothrow
{
    import std.traits : hasUDA;
    T result;

    static foreach (idx, _; T.tupleof) {
        static if (hasUDA!(T.tupleof[idx], Optional))
            result.tupleof[idx] = higher.tupleof[idx] ~ this_.tupleof[idx];
        else static if (IsSetInfo!(typeof(T.init.tupleof[idx]))) {
            if (higher.tupleof[idx].set)
                result.tupleof[idx] = higher.tupleof[idx];
            else
                result.tupleof[idx] = this_.tupleof[idx];
        } else static if (is(T == struct)) {
            result.tupleof[idx] = merge(this_.tupleof[idx], higher.tupleof[idx]);
        } else {
            static assert(false,
                "Expect `@Optional` or `SetInfo` on: `" ~
                __traits(identifier, this_.tupleof[idx]) ~
                "` of type : `" ~
                typeof(this_.tupleof[idx]).stringof ~ "`");
        }
    }

    return result;
}

/// Workaround multiple `E` declaration in `static foreach` when inline
private template IsSetInfo(T) { enum bool IsSetInfo = is(T : SetInfo!E, E); }

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

     auto c1 = parseConfigString!OldSettings(str1, "/dev/null");
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

     auto c2 = parseConfigString!OldSettings(str2, "/dev/null");
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

     auto m3 = OldSettings.init.merge(c1);
     assert(m3 == c1);
}

unittest {
    // Test that SkipPackageRegistry.default_ is not allowed

    import dub.internal.configy.Read;
    import std.exception : assertThrown;

    const str1 = `{
  "skipRegistry": "all"
`;
    assertThrown!Exception(parseConfigString!Settings(str1, "/dev/null"));
}
