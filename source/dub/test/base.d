/*******************************************************************************

    Base utilities (types, functions) used in tests

*******************************************************************************/

module dub.test.base;

version (unittest):

import std.array;
public import std.algorithm;

import dub.data.settings;
public import dub.dependency;
import dub.dub;
import dub.package_;
import dub.packagemanager;
import dub.packagesuppliers.packagesupplier;

// TODO: Remove and handle logging the same way we handle other IO
import dub.internal.logging;

public void enableLogging()
{
    setLogLevel(LogLevel.debug_);
}

public void disableLogging()
{
    setLogLevel(LogLevel.none);
}

/**
 * An instance of Dub that does not rely on the environment
 *
 * This instance of dub should not read any environment variables,
 * nor should it do any file IO, to make it usable and reliable in unittests.
 * Currently it reads environment variables but does not read the configuration.
 */
public class TestDub : Dub
{
    /// Forward to base constructor
    public this (string root = ".", PackageSupplier[] extras = null,
                 SkipPackageSuppliers skip = SkipPackageSuppliers.none)
    {
        super(root, extras, skip);
    }

    /// Avoid loading user configuration
    protected override Settings loadConfig(ref SpecialDirs dirs) const
    {
        // No-op
        return Settings.init;
    }

    /// See `MockPackageSupplier` documentation for this class' implementation
    protected override PackageSupplier makePackageSupplier(string url) const
    {
        return new MockPackageSupplier(url);
    }
}

/**
 * Implements a `PackageSupplier` that doesn't do any IO
 *
 * This `PackageSupplier` needs to be pre-loaded with `Package` it can
 * find during the setup phase of the unittest.
 */
public class MockPackageSupplier : PackageSupplier
{
    /// Mapping of package name to packages, ordered by `Version`
    protected Package[][string] pkgs;

    /// URL this was instantiated with
    protected string url;

    ///
    public this(string url)
    {
        this.url = url;
    }

    ///
    public override @property string description()
    {
        return "unittest PackageSupplier for: " ~ this.url;
    }

    ///
    public override Version[] getVersions(string package_id)
    {
        if (auto ppkgs = package_id in this.pkgs)
            return (*ppkgs).map!(pkg => pkg.version_).array;
        return null;
    }

    ///
    public override void fetchPackage(
        NativePath path, string package_id, in VersionRange dep, bool pre_release)
    {
        assert(0, this.url ~ " - fetchPackage not implemented for: " ~ package_id);
    }

    ///
    public override Json fetchPackageRecipe(
        string package_id, in VersionRange dep, bool pre_release)
    {
        import dub.recipe.json;

        if (auto ppkgs = package_id in this.pkgs)
            foreach_reverse (pkg; *ppkgs)
                if ((!pkg.version_.isPreRelease || pre_release) &&
                    dep.matches(pkg.version_))
                    return toJson(pkg.recipe);
        return Json.init;
    }

    ///
    public override SearchResult[] searchPackages(string query)
    {
        assert(0, this.url ~ " - searchPackages not implemented for: " ~ query);
    }
}
