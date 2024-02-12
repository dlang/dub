/*******************************************************************************

    Base utilities (types, functions) used in tests

    The main type in this module is `TestDub`. `TestDub` is a class that
    inherits from `Dub` and inject dependencies in it to avoid relying on IO.
    First and foremost, by overriding `makePackageManager` and returning a
    `TestPackageManager` instead, we avoid hitting the local filesystem and
    instead present a view of the "local packages" that is fully in-memory.
    Likewise, by providing a `MockPackageSupplier`, we can imitate the behavior
    of the registry without relying on it.

    Leftover_IO:
    Note that reliance on IO was originally all over the place in the Dub
    codebase. For this reason, **new tests might find themselves doing I/O**.
    When that happens, one should isolate the place which does I/O and refactor
    the code to make dependency injection possible and practical.
    An example of this is any place calling `Package.load`, `readPackageRecipe`,
    or `Package.findPackageFile`.

    Supported_features:
    In order to make writing tests possible and practical, not every features
    where implemented in `TestDub`. Notably, path-based packages are not
    supported at the moment, as they would need a better filesystem abstraction.
    However, it would be desirable to add support for them at some point in the
    future.

    Writing_tests:
    `TestDub` exposes a few extra features to make writing tests easier.
    Ideally, those extra features should be kept to a minimum, as a convenient
    API for writing tests is likely to be a convenient API for library and
    application developers as well.
    It is expected that most tests will be centered about the `Project`,
    also known as the "main package" that is loaded and drives Dub's logic
    when common operations such as `dub build` are performed.
    A minimalistic and documented unittest can be found in this module,
    showing the various features of the test framework.

    Logging:
    Dub writes to stdout / stderr in various places. While it would be desirable
    to do dependency injection on it, the benefits brought by doing so currently
    doesn't justify the amount of work required. If unittests for some reason
    trigger messages being written to stdout/stderr, make sure that the logging
    functions are being used instead of bare `write` / `writeln`.

*******************************************************************************/

module dub.test.base;

version (unittest):

import std.array;
public import std.algorithm;
import std.exception;
import std.format;
import std.string;

import dub.data.settings;
public import dub.dependency;
public import dub.dub;
public import dub.package_;
import dub.internal.vibecompat.core.file : FileInfo;
import dub.internal.vibecompat.inet.path;
import dub.packagemanager;
import dub.packagesuppliers.packagesupplier;
import dub.project;
import dub.recipe.io : parsePackageRecipe;

/// Example of a simple unittest for a project with a single dependency
unittest
{
    // `a` will be loaded as the project while `b` will be loaded
    // as a simple package. The recipe files can be in JSON or SDL format,
    // here we use both to demonstrate this.
    const a = `{ "name": "a", "dependencies": { "b": "~>1.0" } }`;
    const b = `name "b"`;

    // Enabling this would provide some more verbose output, which makes
    // debugging a failing unittest much easier.
    version (none) {
        enableLogging();
        scope(exit) disableLogging();
    }

    scope dub = new TestDub();
    // Let the `PackageManager` know about the `b` package
    dub.addTestPackage("b", Version("1.0.0"), b, PackageFormat.sdl);
    // And about our main package
    auto mainPackage = dub.addTestPackage("a", Version("1.0.0"), a);
    // `Dub.loadPackage` will set this package as the project
    // While not required, it follows the common Dub use case.
    dub.loadPackage(mainPackage);
    // This triggers the dependency resolution process that happens
    // when one does not have a selection file in the project.
    // Dub will resolve dependencies and generate the selection file
    // (in memory). If your test has set dependencies / no dependencies,
    // this will not be needed.
    dub.upgrade(UpgradeOptions.select);

    // Simple tests can be performed using the public API
    assert(dub.project.hasAllDependencies(), "project has missing dependencies");
    assert(dub.project.getDependency("b", true), "Missing 'b' dependency");
    // While it is important to make your tests fail before you make them pass,
    // as is common with TDD, it can also be useful to test simple assumptions
    // as part of your basic tests. Here we want to make sure `getDependency`
    // doesn't always return something regardless of its first argument.
    // Note that this package segments modules by categories, e.g. dependencies,
    // and tests are run serially in a module, so one may rely on previous tests
    // having passed to avoid repeating some assumptions.
    assert(dub.project.getDependency("no", true) is null, "Returned unexpected dependency");
}

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
 *
 * Note that since the design of Dub was centered on the file system for so long,
 * `NativePath` is still a core part of how one interacts with this class.
 * In order to be as close to the production code as possible, this class
 * use the following conventions:
 * - The project is located under `/dub/project/`;
 * - The user and system packages are under `/dub/user/packages/` and
 *   `/dub/system/packages/`, respectively;
 * Those paths don't need to exists, but they are what one might see
 * when writing and debugging unittests.
 */
public class TestDub : Dub
{
    /// Convenience constants for use in unittets
    public static immutable ProjectPath = NativePath("/dub/project/");
    /// Ditto
    public static immutable SpecialDirs Paths = {
        temp: "/dub/temp/",
        systemSettings: "/dub/system/",
        userSettings: "/dub/user/",
        userPackages: "/dub/user/",
        cache: "/dub/user/cache/",
    };

    /// Forward to base constructor
    public this (string root = ProjectPath.toNativeString(),
        PackageSupplier[] extras = null,
        SkipPackageSuppliers skip = SkipPackageSuppliers.none)
    {
        super(root, extras, skip);
    }

    /// Avoid loading user configuration
    protected override Settings loadConfig(ref SpecialDirs dirs) const
    {
        dirs = Paths;
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
	public Package addTestPackage(string name, Version vers, string content,
		PackageFormat fmt = PackageFormat.json)
	{
		return this.packageManager.add(PackageName(name), vers, content, fmt);
	}
}

/**
 *
 */
public class TestSelectedVersions : SelectedVersions {
	import dub.recipe.selection;

	/// Forward to parent's constructor
	public this(uint version_ = FileVersion) @safe pure
	{
		super(version_);
	}

	/// Ditto
	public this(Selections!1 data) @safe pure nothrow @nogc
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
    /// The virtual filesystem that this PackageManager acts on
    protected FSEntry fs;

    this()
    {
        NativePath local = TestDub.ProjectPath;
        NativePath user = TestDub.Paths.userSettings;
        NativePath system = TestDub.Paths.systemSettings;
        this.fs = new FSEntry();
        super(local, user, system, false);
    }

    // Re-introduce hidden/deprecated overloads
    public alias loadSCMPackage = PackageManager.loadSCMPackage;
    public alias store = PackageManager.store;

    /// Disabled as semantic are not implementable unless a virtual FS is created
	public override @property void customCachePaths(NativePath[] custom_cache_paths)
    {
        assert(0, "Function not implemented");
    }

    /// Ditto
    public override Package store(NativePath src, PlacementLocation dest, in PackageName name, in Version vers)
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
		// Local packages are not yet implemented
		version (none) {
			foreach (ref repository; this.m_repositories)
				repository.scanLocalPackages(false, this);
		}
		this.m_internal.scan(this, false);
		foreach (ref repository; this.m_repositories)
			repository.scan(this, false);

		// Removed override loading usually done here as they are deprecated
		this.m_initialized = true;
	}

	/**
	 * Loads a `Package`
	 *
	 * This is currently not implemented, and any call to it will trigger
	 * an assert, as that would otherwise be an access to the filesystem.
	 */
	protected override Package load(NativePath path, NativePath recipe = NativePath.init,
		Package parent = null, string version_ = null,
		StrictMode mode = StrictMode.Ignore)
	{
		import dub.internal.utils : stripUTF8Bom;
		if (recipe.empty)
			recipe = this.findPackageFile(path);

		enforce(!recipe.empty,
			"No package file found in %s, expected one of %s"
				.format(path.toNativeString(),
					packageInfoFiles.map!(f => cast(string)f.filename).join("/")));

		const PackageName parent_name = parent
			? PackageName(parent.name) : PackageName.init;

		string text = stripUTF8Bom(cast(string)this.fs.readFile(recipe));
		auto content = parsePackageRecipe(text, recipe.toNativeString(),
			parent_name, null, mode);

		auto ret = new Package(content, path, parent, version_);
		ret.m_infoFile = recipe;
		return ret;
	}

	/// Reimplementation of `Package.findPackageFile`
	public NativePath findPackageFile(NativePath directory)
	{
		foreach (file; packageInfoFiles) {
			auto filename = directory ~ file.filename;
			if (this.fs.existsFile(filename)) return filename;
		}
		return NativePath.init;
	}

	/**
	 * Re-Implementation of `loadSCMPackage`.
	 *
	 * The base implementation will do a `git` clone, which we would like to avoid.
	 * Instead, we allow unittests to explicitly define what packages should be
	 * reachable in a given test.
	 */
	public override Package loadSCMPackage(in PackageName name, in Repository repo)
	{
        import std.string : chompPrefix;

		// We're trying to match `loadGitPackage` as much as possible
		if (!repo.ref_.startsWith("~") && !repo.ref_.isGitHash)
			return null;

		string gitReference = repo.ref_.chompPrefix("~");
		NativePath destination = this.getPackagePath(PlacementLocation.user, name, repo.ref_);

		foreach (p; getPackageIterator(name.toString()))
			if (p.path == destination)
				return p;

		return this.loadSCMRepository(name, repo);
	}

	/// The private part of `loadSCMPackage`
	protected Package loadSCMRepository(in PackageName name, in Repository repo)
	{
		if (auto prepo = repo in this.scm) {
			this.addPackages(this.m_internal.fromPath, *prepo);
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
	public Package add(in PackageName pkg, in Version vers, string content,
		PackageFormat fmt, PlacementLocation loc = PlacementLocation.user)
	{
		import dub.recipe.io : serializePackageRecipe;

		auto path = this.getPackagePath(loc, pkg, vers.toString());
		this.fs.mkdir(path);

		final switch (fmt) {
		case PackageFormat.json:
			path ~= "dub.json";
			break;
		case PackageFormat.sdl:
			path ~= "dub.sdl";
			break;
		}

		auto recipe = parsePackageRecipe(content, path.toNativeString());
		recipe.version_ = vers.toString();
		auto app = appender!string();
		serializePackageRecipe(app, recipe, path.toNativeString());
		this.fs.writeFile(path, app.data());

		this.refresh();
		return this.getPackage(pkg, vers, loc);
	}

    /// Add a reachable SCM package to this `PackageManager`
    public void addTestSCMPackage(Repository repo, Package pkg)
    {
        this.scm[repo] = pkg;
    }

    ///
    protected override bool existsDirectory(NativePath path)
    {
        return this.fs.existsDirectory(path);
    }

    ///
    protected override IterateDirDg iterateDirectory(NativePath path)
    {
        enforce(this.fs.existsDirectory(path),
            path.toNativeString() ~ " does not exists or is not a directory");
        auto dir = this.fs.lookup(path);
        int iterator(scope int delegate(ref FileInfo) del) {
            foreach (c; dir.children) {
                FileInfo fi;
                fi.name = c.name;
                fi.size = (c.type == FSEntry.Type.Directory) ? 0 : c.content.length;
                fi.isDirectory = (c.type == FSEntry.Type.Directory);
                if (auto res = del(fi))
                    return res;
            }
            return 0;
        }
        return &iterator;
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
    protected Package[][PackageName] pkgs;

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
    public override Version[] getVersions(in PackageName name)
    {
        if (auto ppkgs = name.main in this.pkgs)
            return (*ppkgs).map!(pkg => pkg.version_).array;
        return null;
    }

    ///
    public override void fetchPackage(in NativePath path, in PackageName name,
        in VersionRange dep, bool pre_release)
    {
        assert(0, "%s - fetchPackage not implemented for: %s"
            .format(this.url, name.main));
    }

    ///
    public override Json fetchPackageRecipe(in PackageName name,
        in VersionRange dep, bool pre_release)
    {
        import dub.recipe.json;

        if (auto ppkgs = name.main in this.pkgs)
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

/// An abstract filesystem representation
public class FSEntry
{
    /// Type of file system entry
    public enum Type {
        Directory,
        File,
    }

    /// Ditto
    protected Type type;
    /// The name of this node
    protected string name;
    /// The parent of this entry (can be null for the root)
    protected FSEntry parent;
    union {
        /// Children for this FSEntry (with type == Directory)
        protected FSEntry[] children;
        /// Content for this FDEntry (with type == File)
        protected ubyte[] content;
    }

    /// Creates a new FSEntry
    private this (FSEntry p, Type t, string n)
    {
        this.type = t;
        this.parent = p;
        this.name = n;
    }

    /// Create the root of the filesystem, only usable from this module
    private this (bool initialize = true)
    {
        this.type = Type.Directory;

        if (initialize) {
            /// Create the base structure
            this.mkdir(TestDub.Paths.temp);
            this.mkdir(TestDub.Paths.systemSettings);
            this.mkdir(TestDub.Paths.userSettings);
            this.mkdir(TestDub.Paths.userPackages);
            this.mkdir(TestDub.Paths.cache);

            this.mkdir(TestDub.ProjectPath);
        }
    }

    /// Get a direct children node, returns `null` if it can't be found
    protected FSEntry lookup(string name)
    {
        assert(!name.canFind('/'));
        foreach (c; this.children)
            if (c.name == name)
                return c;
        return null;
    }

    /// Returns: A path relative to `this.path`
    protected NativePath relativePath(NativePath path)
    {
        assert(!path.absolute() || path.startsWith(this.path),
               "Calling relativePath with a differently rooted path");
        return path.absolute() ? path.relativeTo(this.path) : path;
    }

    /// Get an arbitrarily nested children node
    protected FSEntry lookup(NativePath path)
    {
        auto relp = this.relativePath(path);
        if (relp.empty)
            return this;
        auto segments = relp.bySegment;
        if (auto c = this.lookup(segments.front.name)) {
            segments.popFront();
            return !segments.empty ? c.lookup(NativePath(segments)) : c;
        }
        return null;
    }

    /// Returns: The `path` of this FSEntry
    public NativePath path() const
    {
        if (this.parent is null)
            return NativePath("/");
        auto thisPath = this.parent.path ~ this.name;
        thisPath.endsWithSlash = (this.type == Type.Directory);
        return thisPath;
    }

    /// Implements `mkdir -p`, returns the created directory
    public FSEntry mkdir (NativePath path)
    {
        auto relp = this.relativePath(path);
        // Check if the child already exists
        auto segments = relp.bySegment;
        auto child = this.lookup(segments.front.name);
        if (child is null) {
            child = new FSEntry(this, Type.Directory, segments.front.name);
            this.children ~= child;
        }
        // Recurse if needed
        segments.popFront();
        return !segments.empty ? child.mkdir(NativePath(segments)) : child;
    }

    /// Checks the existence of a file
    public bool existsFile (NativePath path)
    {
        auto entry = this.lookup(path);
        return entry !is null && entry.type == Type.File;
    }

    /// Checks the existence of a directory
    public bool existsDirectory (NativePath path)
    {
        auto entry = this.lookup(path);
        return entry !is null && entry.type == Type.Directory;
    }

    /// Reads a file, returns the content as `ubyte[]`
    public ubyte[] readFile (NativePath path)
    {
        auto entry = this.lookup(path);
        enforce(entry.type == Type.File, "Trying to read a directory");
        return entry.content.dup;
    }

    /// Write to this file
    public void writeFile (NativePath path, const(char)[] data)
    {
        this.writeFile(path, data.representation);
    }

    /// Ditto
    public void writeFile (NativePath path, const(ubyte)[] data)
    {
        if (auto file = this.lookup(path)) {
            enforce(file.type == Type.File,
                "Trying to write to directory: " ~ path.toNativeString());
            file.content = data.dup;
        } else {
            auto parentPath = path.parentPath();
            auto parent = this.lookup(parentPath);
            enforce(parent !is null, "No such directory: " ~ parentPath.toNativeString());
            enforce(parent.type == Type.Directory,
                "Parent path is not a directory: " ~ parentPath.toNativeString());
            auto file = new FSEntry(parent, Type.File, path.head.name());
            file.content = data.dup;
            parent.children ~= file;
        }
    }
}
