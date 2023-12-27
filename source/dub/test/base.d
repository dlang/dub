/*******************************************************************************

    Base utilities (types, functions) used in tests

*******************************************************************************/

module dub.test.base;

version (unittest):

import std.array;
public import std.algorithm;

import dub.data.settings;
public import dub.dependency;
public import dub.dub;
public import dub.package_;
import dub.packagemanager;
import dub.packagesuppliers.packagesupplier;
import dub.project;

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

	///
	protected override PackageManager makePackageManager() const
	{
		return new TestPackageManager();
	}

    /// See `MockPackageSupplier` documentation for this class' implementation
    protected override PackageSupplier makePackageSupplier(string url) const
    {
        return new MockPackageSupplier(url);
    }

	/// Loads the package from the specified path as the main project package.
	public override void loadPackage(NativePath path)
	{
		assert(0, "Not implemented");
	}

	/// Loads a specific package as the main project package (can be a sub package)
	public override void loadPackage(Package pack)
	{
		m_project = new Project(m_packageManager, pack, new TestSelectedVersions());
	}

	/// Reintroduce parent overloads
	public alias loadPackage = Dub.loadPackage;

	/**
	 * Returns a fully typed `TestPackageManager`
	 *
	 * This exposes the fully typed `PackageManager`, so that client
	 * can call convenience functions on it directly.
	 */
	public override @property inout(TestPackageManager) packageManager() inout
	{
		return cast(inout(TestPackageManager)) this.m_packageManager;
	}

	/**
	 * Creates a package with the provided recipe
	 *
	 * This is a convenience function provided to create a package based on
	 * a given recipe. This is to allow test-cases to be written based off
	 * issues more easily.
     *
     * In order for the `Package` to be visible to `Dub`, use `addTestPackage`,
     * as `makeTestPackage` simply creates the `Package` without adding it.
	 *
	 * Params:
	 *	 str = The string representation of the `PackageRecipe`
	 *	 recipe = The `PackageRecipe` to use
	 *	 vers = The version the package is at, e.g. `Version("1.0.0")`
	 *	 fmt = The format `str` is in, either JSON or SDL
	 *
	 * Returns:
	 *	 The created `Package` instance
	 */
	public Package makeTestPackage(string str, Version vers, PackageFormat fmt = PackageFormat.json)
	{
		import dub.recipe.io;
		final switch (fmt) {
			case PackageFormat.json:
				auto recipe = parsePackageRecipe(str, "dub.json");
                recipe.version_ = vers.toString();
                return new Package(recipe);
			case PackageFormat.sdl:
				auto recipe = parsePackageRecipe(str, "dub.sdl");
                recipe.version_ = vers.toString();
                return new Package(recipe);
		}
	}

    /// Ditto
	public Package addTestPackage(string str, Version vers, PackageFormat fmt = PackageFormat.json)
    {
        return this.packageManager.add(this.makeTestPackage(str, vers, fmt));
    }
}

/**
 *
 */
public class TestSelectedVersions : SelectedVersions {
	import dub.recipe.selection;

	/// Forward to parent's constructor
	public this(uint version_ = FileVersion) @safe pure nothrow @nogc
	{
		super(version_);
	}

	/// Ditto
	public this(Selected data) @safe pure nothrow @nogc
	{
		super(data);
	}

	/// Do not do IO
	public override void save(NativePath path)
	{
		// No-op
	}
}

/**
 * A `PackageManager` suitable to be used in unittests
 *
 * This `PackageManager` does not perform any IO. It imitates the base
 * `PackageManager`, exposing 3 locations, but loading of packages is not
 * automatic and needs to be done by passing a `Package` instance.
 */
package class TestPackageManager : PackageManager
{
    /// List of all SCM packages that can be fetched by this instance
    protected Package[Repository] scm;

    this()
    {
        NativePath pkg = NativePath("/tmp/dub-testsuite-nonexistant/packages/");
        NativePath user = NativePath("/tmp/dub-testsuite-nonexistant/user/");
        NativePath system = NativePath("/tmp/dub-testsuite-nonexistant/system/");
        super(pkg, user, system, false);
    }

    /// Disabled as semantic are not implementable unless a virtual FS is created
	public override @property void customCachePaths(NativePath[] custom_cache_paths)
    {
        assert(0, "Function not implemented");
    }

    /// Ditto
    public override Package store(NativePath src, PlacementLocation dest, string name, Version vers)
    {
        assert(0, "Function not implemented");
    }

    /**
     * This function usually scans the filesystem for packages.
     *
     * We don't want to do IO access and rely on users adding the packages
     * before the test starts instead.
     *
     * Note: Deprecated `refresh(bool)` does IO, but it's deprecated
     */
    public override void refresh()
    {
        // Do nothing
    }

    /**
     * Looks up a specific package
     *
     * Unlike its parent class, no lazy loading is performed.
     * Additionally, as they are already deprecated, overrides are
     * disabled and not available.
     */
	public override Package getPackage(string name, Version vers, bool enable_overrides = false)
    {
        //assert(!enable_overrides, "Overrides are not implemented for TestPackageManager");

        // Implementation inspired from `PackageManager.lookup`,
        // except we replaced `load` with `lookup`.
        if (auto pkg = this.m_internal.lookup(name, vers, this))
			return pkg;

		foreach (ref location; this.m_repositories)
			if (auto p = location.lookup(name, vers, this))
				return p;

		return null;
    }

	/**
	 * Re-Implementation of `loadSCMPackage`.
	 *
	 * The base implementation will do a `git` clone, which we would like to avoid.
	 * Instead, we allow unittests to explicitly define what packages should be
	 * reachable in a given test.
	 */
	public override Package loadSCMPackage(string name, Repository repo)
	{
        import std.string : chompPrefix;

		// We're trying to match `loadGitPackage` as much as possible
		if (!repo.ref_.startsWith("~") && !repo.ref_.isGitHash)
			return null;

		string gitReference = repo.ref_.chompPrefix("~");
		NativePath destination = this.getPackagePath(PlacementLocation.user, name, repo.ref_);
		destination ~= name;
		destination.endsWithSlash = true;

		foreach (p; getPackageIterator(name))
			if (p.path == destination)
				return p;

		return this.loadSCMRepository(name, repo);
	}

	/// The private part of `loadSCMPackage`
	protected Package loadSCMRepository(string name, Repository repo)
	{
		if (auto prepo = repo in this.scm) {
            this.add(*prepo);
            return *prepo;
        }
		return null;
	}

    /**
     * Adds a `Package` to this `PackageManager`
     *
     * This is currently only available in unittests as it is a convenience
     * function used by `TestDub`, but could be generalized once IO has been
     * abstracted away from this class.
     */
	public Package add(Package pkg)
	{
		// See `PackageManager.addPackages` for inspiration.
		assert(!pkg.subPackages.length, "Subpackages are not yet supported");
		this.m_internal.fromPath ~= pkg;
		return pkg;
	}

    /// Add a reachable SCM package to this `PackageManager`
    public void addTestSCMPackage(Repository repo, Package pkg)
    {
        this.scm[repo] = pkg;
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
