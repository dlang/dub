/*******************************************************************************

    Base utilities (types, functions) used in tests

*******************************************************************************/

module dub.test.base;

version (unittest):

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
}
