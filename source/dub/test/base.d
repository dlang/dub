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
import std.datetime.systime;
import std.exception;
import std.format;
import std.string;

import dub.data.settings;
public import dub.dependency;
public import dub.dub;
public import dub.package_;
import dub.internal.vibecompat.core.file : FileInfo;
public import dub.internal.vibecompat.inet.path;
import dub.packagemanager;
import dub.packagesuppliers.packagesupplier;
import dub.project;
import dub.recipe.io : parsePackageRecipe;
import dub.recipe.selection;

/// Example of a simple unittest for a project with a single dependency
unittest
{
    // Enabling this would provide some more verbose output, which makes
    // debugging a failing unittest much easier.
    version (none) {
        enableLogging();
        scope(exit) disableLogging();
    }

    // Initialization is best done as a delegate passed to `TestDub` constructor,
    // which receives an `FSEntry` representing the root of the filesystem.
    // Various low-level functions are exposed (mkdir, writeFile, ...),
    // as well as higher-level functions (`writePackageFile`).
    scope dub = new TestDub((scope FSEntry root) {
            // `a` will be loaded as the project while `b` will be loaded
            // as a simple package. The recipe files can be in JSON or SDL format,
            // here we use both to demonstrate this.
            root.writeFile(TestDub.ProjectPath ~ "dub.json",
                `{ "name": "a", "dependencies": { "b": "~>1.0" } }`);
            root.writeFile(TestDub.ProjectPath ~ "dub.selections.json",
                           `{"fileVersion": 1, "versions": {"b": "1.1.0"}}`);
            // Note that you currently need to add the `version` to the package
            root.writePackageFile("b", "1.0.0", `name "b"
version "1.0.0"`, PackageFormat.sdl);
            root.writePackageFile("b", "1.1.0", `name "b"
version "1.1.0"`, PackageFormat.sdl);
            root.writePackageFile("b", "1.2.0", `name "b"
version "1.2.0"`, PackageFormat.sdl);
    });

    // `Dub.loadPackage` will set this package as the project
    // While not required, it follows the common Dub use case.
    dub.loadPackage();

    // Simple tests can be performed using the public API
    assert(dub.project.hasAllDependencies(), "project has missing dependencies");
    assert(dub.project.getDependency("b", true), "Missing 'b' dependency");
    assert(dub.project.getDependency("b", true).version_ == Version("1.1.0"));
    // While it is important to make your tests fail before you make them pass,
    // as is common with TDD, it can also be useful to test simple assumptions
    // as part of your basic tests. Here we want to make sure `getDependency`
    // doesn't always return something regardless of its first argument.
    // Note that this package segments modules by categories, e.g. dependencies,
    // and tests are run serially in a module, so one may rely on previous tests
    // having passed to avoid repeating some assumptions.
    assert(dub.project.getDependency("no", true) is null, "Returned unexpected dependency");

    // This triggers the dependency resolution process that happens
    // when one does not have a selection file in the project.
    // Dub will resolve dependencies and generate the selection file
    // (in memory). If your test has set dependencies / no dependencies,
    // this will not be needed.
    dub.upgrade(UpgradeOptions.select);
    assert(dub.project.getDependency("b", true).version_ == Version("1.1.0"));

    /// Now actually upgrade dependencies in memory
    dub.upgrade(UpgradeOptions.select | UpgradeOptions.upgrade);
    assert(dub.project.getDependency("b", true).version_ == Version("1.2.0"));

    /// Adding a package to the registry require the version and at list a recipe
    dub.getRegistry().add(Version("1.3.0"), (scope FSEntry pkg) {
        // This is required
        pkg.writeFile(NativePath(`dub.sdl`), `name "b"`);
        // Any other files can be present, as a normal package
        pkg.mkdir(NativePath("source/b/")).writeFile(
            NativePath("main.d"), "module b.main; void main() {}");
    });
    // Fetch the package from the registry
    dub.upgrade(UpgradeOptions.select | UpgradeOptions.upgrade);
    assert(dub.project.getDependency("b", true).version_ == Version("1.3.0"));
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
    /// The virtual filesystem that this instance acts on
    public FSEntry fs;

    /**
     * Redundant reference to the registry
     *
     * We currently create 2 `MockPackageSupplier`s hidden behind a
     * `FallbackPackageSupplier` (see base implementation).
     * The fallback is never used, and we need to provide the user
     * a mean to access the registry so they can add packages to it.
     */
    protected MockPackageSupplier registry;

    /// Convenience constants for use in unittests
    version (Windows)
        public static immutable Root = NativePath("T:\\dub\\");
    else
        public static immutable Root = NativePath("/dub/");

    /// Ditto
    public static immutable ProjectPath = Root ~ "project";

    /// Ditto
    public static immutable SpecialDirs Paths = {
        temp: Root ~ "temp/",
        systemSettings: Root ~ "system/",
        userSettings: Root ~ "user/",
        userPackages: Root ~ "user/",
        cache: Root ~ "user/" ~ "cache/",
    };

    /***************************************************************************

        Instantiate a new `TestDub` instance with the provided filesystem state

        This exposes the raw virtual filesystem to the user, allowing any kind
        of customization to happen: Empty directory, non-writeable ones, etc...

        Params:
          dg = Delegate to be called with the filesystem, before `TestDub`
               instantiation is performed;
          root = The root path for this instance (forwarded to Dub)
          extras = Extras `PackageSupplier`s (forwarded to Dub)
          skip = What `PackageSupplier`s to skip (forwarded to Dub)

    ***************************************************************************/

    public this (scope void delegate(scope FSEntry root) dg = null,
        string root = ProjectPath.toNativeString(),
        PackageSupplier[] extras = null,
        SkipPackageSuppliers skip = SkipPackageSuppliers.none)
    {
        /// Create the fs & its base structure
        auto fs_ = new FSEntry();
        fs_.mkdir(Paths.temp);
        fs_.mkdir(Paths.systemSettings);
        fs_.mkdir(Paths.userSettings);
        fs_.mkdir(Paths.userPackages);
        fs_.mkdir(Paths.cache);
        fs_.mkdir(ProjectPath);
        if (dg !is null) dg(fs_);
        this(fs_, root, extras, skip);
    }

    /// Workaround https://issues.dlang.org/show_bug.cgi?id=24388 when called
    /// when called with (null, ...).
    public this (typeof(null) _,
        string root = ProjectPath.toNativeString(),
        PackageSupplier[] extras = null,
        SkipPackageSuppliers skip = SkipPackageSuppliers.none)
    {
        alias TType = void delegate(scope FSEntry);
        this(TType.init, root, extras, skip);
    }

    /// Internal constructor
    private this(FSEntry fs_, string root, PackageSupplier[] extras,
        SkipPackageSuppliers skip)
    {
        this.fs = fs_;
        super(root, extras, skip);
    }

    /***************************************************************************

        Get a new `Dub` instance with the same filesystem

        This creates a new `TestDub` instance with the existing filesystem,
        allowing one to write tests that would normally require multiple Dub
        instantiation (e.g. test that `fetch` is idempotent).
        Like the main `TestDub` constructor, it allows to do modifications to
        the filesystem before the new instantiation is made.

        Params:
          dg = Delegate to be called with the filesystem, before `TestDub`
               instantiation is performed;

        Returns:
          A new `TestDub` instance referencing the same filesystem as `this`.

    ***************************************************************************/

    public TestDub newTest (scope void delegate(scope FSEntry root) dg = null,
        string root = ProjectPath.toNativeString(),
        PackageSupplier[] extras = null,
        SkipPackageSuppliers skip = SkipPackageSuppliers.none)
    {
        if (dg !is null) dg(this.fs);
        return new TestDub(this.fs, root, extras, skip);
    }

    /// Avoid loading user configuration
    protected override InternalSettings loadConfig(ref SpecialDirs dirs) const
    {
        dirs = Paths;
        return typeof(return).init;
    }

	///
	protected override PackageManager makePackageManager()
	{
		assert(this.fs !is null);
		return new TestPackageManager(this.fs);
	}

    /// See `MockPackageSupplier` documentation for this class' implementation
    protected override PackageSupplier makePackageSupplier(string url)
    {
        auto r = new MockPackageSupplier(url);
        if (this.registry is null)
            this.registry = r;
        return r;
    }

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
     * Returns a fully-typed `MockPackageSupplier`
     *
     * This exposes the first (and usually sole) `PackageSupplier` if typed
     * as `MockPackageSupplier` so that client can call convenience functions
     * on it directly.
     */
    public @property inout(MockPackageSupplier) getRegistry() inout
    {
        // This will not work with `SkipPackageSupplier`.
        assert(this.registry !is null, "The registry hasn't been instantiated?");
		return this.registry;
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
    /// `loadSCMPackage` will strip some part of the remote / repository,
    /// which we need to mimic to provide a usable API.
    private struct GitReference {
        ///
        this (in Repository repo) {
            this.remote = repo.remote.chompPrefix("git+");
            this.ref_ = repo.ref_.chompPrefix("~");
        }

        ///
        this (in string remote, in string gitref) {
            this.remote = remote;
            this.ref_ = gitref;
        }

        string remote;
        string ref_;
    }


    /// List of all SCM packages that can be fetched by this instance
    protected string[GitReference] scm;
    /// The virtual filesystem that this PackageManager acts on
    protected FSEntry fs;

    this(FSEntry filesystem)
    {
        NativePath local = TestDub.ProjectPath;
        NativePath user = TestDub.Paths.userSettings;
        NativePath system = TestDub.Paths.systemSettings;
        this.fs = filesystem;
        super(local, user, system, false);
    }

	/**
	 * Re-Implementation of `gitClone`.
	 *
	 * The base implementation will do a `git` clone, to the file-system.
	 * We need to mock both the `git` part and the write to the file system.
	 */
	protected override bool gitClone(string remote, string gitref, in NativePath dest)
	{
        if (auto pstr = GitReference(remote, gitref) in this.scm) {
            this.fs.mkdir(dest);
            this.fs.writeFile(dest ~ "dub.json", *pstr);
            return true;
        }
        return false;
	}

    /// Add a reachable SCM package to this `PackageManager`
    public void addTestSCMPackage(in Repository repo, string dub_json)
    {
        this.scm[GitReference(repo)] = dub_json;
    }

	/// Overriden because we currently don't have a way to do dependency
    /// injection on `dub.internal.utils : lockFile`.
	public override Package store(ubyte[] data, PlacementLocation dest,
		in PackageName name, in Version vers)
	{
        // Most of the code is copied from the base method
		assert(!name.sub.length, "Cannot store a subpackage, use main package instead");
		NativePath dstpath = this.getPackagePath(dest, name, vers.toString());
		this.ensureDirectory(dstpath.parentPath());

		if (this.existsFile(dstpath))
			return this.getPackage(name, vers, dest);
		return this.store_(data, dstpath, name, vers);
	}

    ///
    protected override bool existsDirectory(NativePath path)
    {
        return this.fs.existsDirectory(path);
    }

    ///
    protected override void ensureDirectory(NativePath path)
    {
        this.fs.mkdir(path);
    }

    ///
    protected override bool existsFile(NativePath path)
    {
        return this.fs.existsFile(path);
    }

    ///
    protected override void writeFile(NativePath path, const(ubyte)[] data)
    {
        return this.fs.writeFile(path, data);
    }

    ///
    protected override void writeFile(NativePath path, const(char)[] data)
    {
        return this.fs.writeFile(path, data);
    }

    ///
    protected override string readText(NativePath path)
    {
        return this.fs.readText(path);
    }

    ///
    protected override void removeFile(NativePath path)
    {
        return this.fs.removeFile(path);
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
                fi.timeModified = c.attributes.modification;
                final switch (c.attributes.type) {
                case FSEntry.Type.File:
                    fi.size = c.content.length;
                    break;
                case FSEntry.Type.Directory:
                    fi.isDirectory = true;
                    break;
                }
                if (auto res = del(fi))
                    return res;
            }
            return 0;
        }
        return &iterator;
    }

    /// Ditto
    protected override void setTimes(in NativePath path, in SysTime accessTime,
        in SysTime modificationTime)
    {
        this.fs.setTimes(path, accessTime, modificationTime);
    }

    /// Ditto
    protected override void setAttributes(in NativePath path, uint attributes)
    {
        this.fs.setAttributes(path, attributes);
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
    /// Internal duplication to avoid having to deserialize the zip content
    private struct PkgData {
        ///
        PackageRecipe recipe;
        ///
        ubyte[] data;
    }

    /// Mapping of package name to package zip data, ordered by `Version`
    protected PkgData[Version][PackageName] pkgs;

    /// URL this was instantiated with
    protected string url;

    ///
    public this(string url)
    {
        this.url = url;
    }

    /**
     * Adds a package to this `PackageSupplier`
     *
     * The registry API bakes in Zip files / binary data.
     * When adding a package here, just provide an `FSEntry`
     * representing the package directory, which will be converted
     * to ZipFile / `ubyte[]` and returned by `fetchPackage`.
     *
     * This use a delegate approach similar to `TestDub` constructor:
     * a delegate must be provided to initialize the package content.
     * The delegate will be called once and is expected to contain,
     * at its root, the package.
     *
     * The name of the package will be defined from the recipe file.
     * It's version, however, must be provided as parameter.
     *
     * Params:
     *   vers = The `Version` of this package.
     *   dg = A delegate that will populate its parameter with the
     *        content of the package.
     */
    public void add (in Version vers, scope void delegate(scope FSEntry root) dg)
    {
        scope pkgRoot = new FSEntry();
        dg(pkgRoot);

        scope recipe = pkgRoot.lookup("dub.json");
        if (recipe is null) recipe = pkgRoot.lookup("dub.sdl");
        if (recipe is null) recipe = pkgRoot.lookup("package.json");
        // Note: If you want to provide an invalid package, override
        // [Mock]PackageSupplier. Most tests will expect a well-behaving
        // registry so this assert is here to help with writing tests.
        assert(recipe !is null,
               "No package recipe found: Expected dub.json or dub.sdl");
        auto pkgRecipe = parsePackageRecipe(
            pkgRoot.readText(NativePath(recipe.name)), recipe.name);
        pkgRecipe.version_ = vers.toString();
        const name = PackageName(pkgRecipe.name);
        this.pkgs[name][vers] = PkgData(
            pkgRecipe, pkgRoot.serializeToZip("%s-%s/".format(name, vers)));
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
            return (*ppkgs).keys;
        return null;
    }

    ///
    public override ubyte[] fetchPackage(in PackageName name,
        in VersionRange dep, bool pre_release)
    {
        return this.getBestMatch(name, dep, pre_release).data;
    }

    ///
    public override Json fetchPackageRecipe(in PackageName name,
        in VersionRange dep, bool pre_release)
    {
        import dub.recipe.json;

        auto match = this.getBestMatch(name, dep, pre_release);
        if (!match.data.length)
            return Json.init;
        auto res = toJson(match.recipe);
        return res;
    }

    ///
    protected PkgData getBestMatch (
        in PackageName name, in VersionRange dep, bool pre_release)
    {
        auto ppkgs = name.main in this.pkgs;
        if (ppkgs is null)
            return typeof(return).init;

        PkgData match;
        foreach (vers, pr; *ppkgs)
            if ((!vers.isPreRelease || pre_release) &&
                dep.matches(vers) &&
                (!match.data.length || Version(match.recipe.version_) < vers)) {
                match.recipe = pr.recipe;
                match.data = pr.data;
            }
        return match;
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
    public enum Type : ubyte {
        Directory,
        File,
    }

    /// List FSEntry attributes
    protected struct Attributes {
        /// The type of FSEntry, see `FSEntry.Type`
        public Type type;
        /// System-specific attributes for this `FSEntry`
        public uint attrs;
        /// Last access time
        public SysTime access;
        /// Last modification time
        public SysTime modification;
    }
    /// Ditto
    protected Attributes attributes;

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
        // Avoid 'DOS File Times cannot hold dates prior to 1980.' exception
        import std.datetime.date;
        SysTime DefaultTime = SysTime(DateTime(2020, 01, 01));

        this.attributes.type = t;
        this.parent = p;
        this.name = n;
        this.attributes.access = DefaultTime;
        this.attributes.modification = DefaultTime;
    }

    /// Create the root of the filesystem, only usable from this module
    private this ()
    {
        import std.datetime.date;
        SysTime DefaultTime = SysTime(DateTime(2020, 01, 01));

        this.attributes.type = Type.Directory;
        this.attributes.access = DefaultTime;
        this.attributes.modification = DefaultTime;
    }

    /// Get a direct children node, returns `null` if it can't be found
    protected inout(FSEntry) lookup(string name) inout return scope
    {
        assert(!name.canFind('/'));
        foreach (c; this.children)
            if (c.name == name)
                return c;
        return null;
    }

    /// Get an arbitrarily nested children node
    protected inout(FSEntry) lookup(NativePath path) inout return scope
    {
        auto relp = this.relativePath(path);
        relp.normalize(); // try to get rid of `..`
        if (relp.empty)
            return this;
        auto segments = relp.bySegment;
        if (auto c = this.lookup(segments.front.name)) {
            segments.popFront();
            return !segments.empty ? c.lookup(NativePath(segments)) : c;
        }
        return null;
    }

    /** Get the parent `FSEntry` of a `NativePath`
     *
     * If the parent doesn't exist, an `Exception` will be thrown
     * unless `silent` is provided. If the parent path is a file,
     * an `Exception` will be thrown regardless of `silent`.
     *
     * Params:
     *   path = The path to look up the parent for
     *   silent = Whether to error on non-existing parent,
     *            default to `false`.
     */
    protected inout(FSEntry) getParent(NativePath path, bool silent = false)
        inout return scope
    {
        // Relative path in the current directory
        if (!path.hasParentPath())
            return this;

        // If we're not in the right `FSEntry`, recurse
        const parentPath = path.parentPath();
        auto p = this.lookup(parentPath);
        enforce(silent || p !is null,
            "No such directory: " ~ parentPath.toNativeString());
        enforce(p is null || p.attributes.type == Type.Directory,
            "Parent path is not a directory: " ~ parentPath.toNativeString());
        return p;
    }

    /// Returns: A path relative to `this.path`
    protected NativePath relativePath(NativePath path) const scope
    {
        assert(!path.absolute() || path.startsWith(this.path),
               "Calling relativePath with a differently rooted path");
        return path.absolute() ? path.relativeTo(this.path) : path;
    }

    /*+*************************************************************************

        Utility function

        Below this banners are functions that are provided for the convenience
        of writing tests for `Dub`.

    ***************************************************************************/

    /// Prints a visual representation of the filesystem to stdout for debugging
    public void print(bool content = false) const scope
    {
        import std.range : repeat;
        static import std.stdio;

        size_t indent;
        for (auto p = &this.parent; (*p) !is null; p = &p.parent)
            indent++;
        // Don't print anything (even a newline) for root
        if (this.parent is null)
            std.stdio.write('/');
        else
            std.stdio.write('|', '-'.repeat(indent), ' ', this.name, ' ');

        final switch (this.attributes.type) {
        case Type.Directory:
            std.stdio.writeln('(', this.children.length, " entries):");
            foreach (c; this.children)
                c.print(content);
            break;
        case Type.File:
            if (!content)
                std.stdio.writeln('(', this.content.length, " bytes)");
            else if (this.name.endsWith(".json") || this.name.endsWith(".sdl"))
                std.stdio.writeln('(', this.content.length, " bytes): ",
                    cast(string) this.content);
            else
                std.stdio.writeln('(', this.content.length, " bytes): ",
                    this.content);
            break;
        }
    }

    /// Returns: The final destination a specific package needs to be stored in
    public static NativePath getPackagePath(in string name_, string vers,
        PlacementLocation location = PlacementLocation.user)
    {
        PackageName name = PackageName(name_);
        // Keep in sync with `dub.packagemanager: PackageManager.getPackagePath`
        // and `Location.getPackagePath`
        NativePath result (in NativePath base)
        {
            NativePath res = base ~ name.main.toString() ~ vers ~
                name.main.toString();
            res.endsWithSlash = true;
            return res;
        }

        final switch (location) {
        case PlacementLocation.user:
            return result(TestDub.Paths.userSettings ~ "packages/");
        case PlacementLocation.system:
            return result(TestDub.Paths.systemSettings ~ "packages/");
        case PlacementLocation.local:
            return result(TestDub.ProjectPath ~ "/.dub/packages/");
        }
    }

    /*+*************************************************************************

        Public filesystem functions

        Below this banners are functions which mimic the behavior of a file
        system.

    ***************************************************************************/

    /// Returns: The `path` of this FSEntry
    public NativePath path() const scope
    {
        if (this.parent is null)
            return NativePath("/");
        auto thisPath = this.parent.path ~ this.name;
        thisPath.endsWithSlash = (this.attributes.type == Type.Directory);
        return thisPath;
    }

    /// Implements `mkdir -p`, returns the created directory
    public FSEntry mkdir (NativePath path) scope
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
    public bool existsFile (NativePath path) const scope
    {
        auto entry = this.lookup(path);
        return entry !is null && entry.attributes.type == Type.File;
    }

    /// Checks the existence of a directory
    public bool existsDirectory (NativePath path) const scope
    {
        auto entry = this.lookup(path);
        return entry !is null && entry.attributes.type == Type.Directory;
    }

    /// Reads a file, returns the content as `ubyte[]`
    public ubyte[] readFile (NativePath path) const scope
    {
        auto entry = this.lookup(path);
        enforce(entry !is null, "No such file: " ~ path.toNativeString());
        enforce(entry.attributes.type == Type.File, "Trying to read a directory");
        // This is a hack to make poisoning a file possible.
        // However, it is rather crude and doesn't allow to poison directory.
        // Consider introducing a derived type to allow it.
        assert(entry.content != "poison".representation,
            "Trying to access poisoned path: " ~ path.toNativeString());
        return entry.content.dup;
    }

    /// Reads a file, returns the content as text
    public string readText (NativePath path) const scope
    {
        import std.utf : validate;

        const content = this.readFile(path);
        // Ignore BOM: If it's needed for a test, add support for it.
        validate(cast(const(char[])) content);
        // `readFile` just `dup` the content, so it's safe to cast.
        return cast(string) content;
    }

    /// Write to this file
    public void writeFile (NativePath path, const(char)[] data) scope
    {
        this.writeFile(path, data.representation);
    }

    /// Ditto
    public void writeFile (NativePath path, const(ubyte)[] data) scope
    {
        enforce(!path.endsWithSlash(),
            "Cannot write to directory: " ~ path.toNativeString());
        if (auto file = this.lookup(path)) {
            // If the file already exists, override it
            enforce(file.attributes.type == Type.File,
                "Trying to write to directory: " ~ path.toNativeString());
            file.content = data.dup;
        } else {
            auto p = this.getParent(path);
            auto file = new FSEntry(p, Type.File, path.head.name());
            file.content = data.dup;
            p.children ~= file;
        }
    }

    /** Remove a file
     *
     * Always error if the target is a directory.
     * Does not error if the target does not exists
     * and `force` is set to `true`.
     *
     * Params:
     *   path = Path to the file to remove
     *   force = Whether to ignore non-existing file,
     *           default to `false`.
     */
    public void removeFile (NativePath path, bool force = false)
    {
        import std.algorithm.searching : countUntil;

        assert(!path.empty, "Empty path provided to `removeFile`");
        enforce(!path.endsWithSlash(),
            "Cannot remove file with directory path: " ~ path.toNativeString());
        auto p = this.getParent(path, force);
        const idx = p.children.countUntil!(e => e.name == path.head.name());
        if (idx < 0) {
            enforce(force,
                "removeFile: No such file: " ~ path.toNativeString());
        } else {
            enforce(p.children[idx].attributes.type == Type.File,
                "removeFile called on a directory: " ~ path.toNativeString());
            p.children = p.children[0 .. idx] ~ p.children[idx + 1 .. $];
        }
    }

    /** Remove a directory
     *
     * Remove an existing empty directory.
     * If `force` is set to `true`, no error will be thrown
     * if the directory is empty or non-existing.
     *
     * Params:
     *   path = Path to the directory to remove
     *   force = Whether to ignore non-existing / non-empty directories,
     *           default to `false`.
     */
    public void removeDir (NativePath path, bool force = false)
    {
        import std.algorithm.searching : countUntil;

        assert(!path.empty, "Empty path provided to `removeFile`");
        auto p = this.getParent(path, force);
        const idx = p.children.countUntil!(e => e.name == path.head.name());
        if (idx < 0) {
            enforce(force,
                "removeDir: No such directory: " ~ path.toNativeString());
        } else {
            enforce(p.children[idx].attributes.type == Type.Directory,
                "removeDir called on a file: " ~ path.toNativeString());
            enforce(force || p.children[idx].children.length == 0,
                "removeDir called on non-empty directory: " ~ path.toNativeString());
            p.children = p.children[0 .. idx] ~ p.children[idx + 1 .. $];
        }
    }

    /// Implement `std.file.setTimes`
    public void setTimes(in NativePath path, in SysTime accessTime,
        in SysTime modificationTime)
    {
        auto e = this.lookup(path);
        enforce(e !is null,
            "setTimes: No such file or directory: " ~ path.toNativeString());
        e.attributes.access = accessTime;
        e.attributes.modification = modificationTime;
    }

    /// Implement `std.file.setAttributes`
    public void setAttributes(in NativePath path, uint attributes)
    {
        auto e = this.lookup(path);
        enforce(e !is null,
            "setTimes: No such file or directory: " ~ path.toNativeString());
        e.attributes.attrs = attributes;
    }
}

/**
 * Convenience function to write a package file
 *
 * Allows to write a package file (and only a package file) for a certain
 * package name and version.
 *
 * Params:
 *   root = The root FSEntry
 *   name = The package name (typed as string for convenience)
 *   vers = The package version
 *   recipe = The text of the package recipe
 *   fmt = The format used for `recipe` (default to JSON)
 *   location = Where to place the package (default to user location)
 */
public void writePackageFile (FSEntry root, in string name, in string vers,
    in string recipe, in PackageFormat fmt = PackageFormat.json,
    in PlacementLocation location = PlacementLocation.user)
{
    const path = FSEntry.getPackagePath(name, vers, location);
    root.mkdir(path).writeFile(
        NativePath(fmt == PackageFormat.json ? "dub.json" : "dub.sdl"),
        recipe);
}

/**
 * Converts an `FSEntry` and its children to a `ZipFile`
 */
public ubyte[] serializeToZip (scope FSEntry root, string rootPath) {
    import std.path;
    import std.zip;

    scope z = new ZipArchive();
    void addToZip(scope string dir, scope FSEntry e) {
        auto m = new ArchiveMember();
        m.name = dir.buildPath(e.name);
        m.fileAttributes = e.attributes.attrs;
        m.time = e.attributes.modification;

        final switch (e.attributes.type) {
        case FSEntry.Type.Directory:
            // We need to ensure the directory entry ends with a slash
            // otherwise it will be considered as a file.
            if (m.name[$-1] != '/')
                m.name ~= '/';
            z.addMember(m);
            foreach (c; e.children)
                addToZip(m.name, c);
            break;
        case FSEntry.Type.File:
            m.expandedData = e.content;
            z.addMember(m);
        }
    }
    addToZip(rootPath, root);
    return cast(ubyte[]) z.build();
}
