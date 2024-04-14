/**
	Management of packages on the local computer.

	Copyright: © 2012-2016 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Matthias Dondorff
*/
module dub.packagemanager;

import dub.dependency;
import dub.internal.utils;
import dub.internal.vibecompat.core.file : FileInfo;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.path;
import dub.internal.logging;
import dub.package_;
import dub.recipe.io;
import dub.recipe.selection;
import dub.internal.configy.Exceptions;
public import dub.internal.configy.Read : StrictMode;

import dub.internal.dyaml.stdsumtype;

import std.algorithm : countUntil, filter, map, sort, canFind, remove;
import std.array;
import std.conv;
import std.datetime.systime;
import std.digest.sha;
import std.encoding : sanitize;
import std.exception;
import std.range;
import std.string;
import std.zip;


/// Indicates where a package has been or should be placed to.
public enum PlacementLocation {
	/// Packages retrieved with 'local' will be placed in the current folder
	/// using the package name as destination.
	local,
	/// Packages with 'userWide' will be placed in a folder accessible by
	/// all of the applications from the current user.
	user,
	/// Packages retrieved with 'systemWide' will be placed in a shared folder,
	/// which can be accessed by all users of the system.
	system,
}

/// Converts a `PlacementLocation` to a string
public string toString (PlacementLocation loc) @safe pure nothrow @nogc
{
    final switch (loc) {
    case PlacementLocation.local:
        return "Local";
    case PlacementLocation.user:
        return "User";
    case PlacementLocation.system:
        return "System";
    }
}

/// The PackageManager can retrieve present packages and get / remove
/// packages.
class PackageManager {
	protected {
		/**
		 * The 'internal' location, for packages not attributable to a location.
		 *
		 * There are two uses for this:
		 * - In `bare` mode, the search paths are set at this scope,
		 *	 and packages gathered are stored in `localPackage`;
		 * - In the general case, any path-based or SCM-based dependency
		 *	 is loaded in `fromPath`;
		 */
		Location m_internal;
		/**
		 * List of locations that are managed by this `PackageManager`
		 *
		 * The `PackageManager` can be instantiated either in 'bare' mode,
		 * in which case this array will be empty, or in the normal mode,
		 * this array will have 3 entries, matching values
		 * in the `PlacementLocation` enum.
		 *
		 * See_Also: `Location`, `PlacementLocation`
		 */
		Location[] m_repositories;
		/**
		 * Whether `refresh` has been called or not
		 *
		 * Dub versions because v1.31 eagerly scan all available repositories,
		 * leading to slowdown for the most common operation - `dub build` with
		 * already resolved dependencies.
		 * From v1.31 onward, those locations are not scanned eagerly,
		 * unless one of the function requiring eager scanning does,
		 * such as `getBestPackage` - as it needs to iterate the list
		 * of available packages.
		 */
		bool m_initialized;
	}

	/**
	   Instantiate an instance with a single search path

	   This constructor is used when dub is invoked with the '--bare' CLI switch.
	   The instance will not look up the default repositories
	   (e.g. ~/.dub/packages), using only `path` instead.

	   Params:
		 path = Path of the single repository
	 */
	this(NativePath path)
	{
		this.m_internal.searchPath = [ path ];
		this.refresh();
	}

	this(NativePath package_path, NativePath user_path, NativePath system_path, bool refresh_packages = true)
	{
		m_repositories = [
			Location(package_path ~ ".dub/packages/"),
			Location(user_path ~ "packages/"),
			Location(system_path ~ "packages/")];

		if (refresh_packages) refresh();
	}

	/** Gets/sets the list of paths to search for local packages.
	*/
	@property void searchPath(NativePath[] paths)
	{
		if (paths == this.m_internal.searchPath) return;
		this.m_internal.searchPath = paths.dup;
		this.refresh();
	}
	/// ditto
	@property const(NativePath)[] searchPath() const { return this.m_internal.searchPath; }

	/** Returns the effective list of search paths, including default ones.
	*/
	deprecated("Use the `PackageManager` facilities instead")
	@property const(NativePath)[] completeSearchPath()
	const {
		auto ret = appender!(const(NativePath)[])();
		ret.put(this.m_internal.searchPath);
		foreach (ref repo; m_repositories) {
			ret.put(repo.searchPath);
			ret.put(repo.packagePath);
		}
		return ret.data;
	}

	/** Sets additional (read-only) package cache paths to search for packages.

		Cache paths have the same structure as the default cache paths, such as
		".dub/packages/".

		Note that previously set custom paths will be removed when setting this
		property.
	*/
	@property void customCachePaths(NativePath[] custom_cache_paths)
	{
		import std.algorithm.iteration : map;
		import std.array : array;

		m_repositories.length = PlacementLocation.max+1;
		m_repositories ~= custom_cache_paths.map!(p => Location(p)).array;

		this.refresh();
	}

	/**
	 * Looks up a package, first in the list of loaded packages,
	 * then directly on the file system.
	 *
	 * This function allows for lazy loading of packages, without needing to
	 * first scan all the available locations (as `refresh` does).
	 *
	 * Note:
	 * This function does not take overrides into account. Overrides need
	 * to be resolved by the caller before `lookup` is called.
	 * Additionally, if a package of the same version is loaded in multiple
	 * locations, the first one matching (local > user > system)
	 * will be returned.
	 *
	 * Params:
	 *	 name  = The full name of the package to look up
	 *	 vers = The version the package must match
	 *
	 * Returns:
	 *	 A `Package` if one was found, `null` if none exists.
	 */
	protected Package lookup (in PackageName name, in Version vers) {
		if (!this.m_initialized)
			this.refresh();

		if (auto pkg = this.m_internal.lookup(name, vers))
			return pkg;

		foreach (ref location; this.m_repositories)
			if (auto p = location.load(name, vers, this))
				return p;

		return null;
	}

	/** Looks up a specific package.

		Looks up a package matching the given version/path in the set of
		registered packages. The lookup order is done according the the
		usual rules (see getPackageIterator).

		Params:
			name = The name of the package
			ver = The exact version of the package to query
			path = An exact path that the package must reside in. Note that
				the package must still be registered in the package manager.
			enable_overrides = Apply the local package override list before
				returning a package (enabled by default)

		Returns:
			The matching package or null if no match was found.
	*/
	Package getPackage(in PackageName name, in Version ver, bool enable_overrides = true)
	{
		if (enable_overrides) {
			foreach (ref repo; m_repositories)
				foreach (ovr; repo.overrides)
					if (ovr.package_ == name.toString() && ovr.source.matches(ver)) {
						Package pack = ovr.target.match!(
							(NativePath path) => getOrLoadPackage(path),
							(Version	vers) => getPackage(name, vers, false),
						);
						if (pack) return pack;

						ovr.target.match!(
							(any) {
								logWarn("Package override %s %s -> '%s' doesn't reference an existing package.",
										ovr.package_, ovr.source, any);
							},
						);
					}
		}

		return this.lookup(name, ver);
	}

	deprecated("Use the overload that accepts a `PackageName` instead")
	Package getPackage(string name, Version ver, bool enable_overrides = true)
	{
		return this.getPackage(PackageName(name), ver, enable_overrides);
	}

	/// ditto
	deprecated("Use the overload that accepts a `Version` as second argument")
	Package getPackage(string name, string ver, bool enable_overrides = true)
	{
		return getPackage(name, Version(ver), enable_overrides);
	}

	/// ditto
	deprecated("Use the overload that takes a `PlacementLocation`")
	Package getPackage(string name, Version ver, NativePath path)
	{
		foreach (p; getPackageIterator(name)) {
			auto pvm = isManagedPackage(p) ? VersionMatchMode.strict : VersionMatchMode.standard;
			if (p.version_.matches(ver, pvm) && p.path.startsWith(path))
				return p;
		}
		return null;
	}

	/// Ditto
	deprecated("Use the overload that accepts a `PackageName` instead")
	Package getPackage(string name, Version ver, PlacementLocation loc)
	{
		return this.getPackage(PackageName(name), ver, loc);
	}

	/// Ditto
	Package getPackage(in PackageName name, in Version ver, PlacementLocation loc)
	{
		// Bare mode
		if (loc >= this.m_repositories.length)
			return null;
		return this.m_repositories[loc].load(name, ver, this);
	}

	/// ditto
	deprecated("Use the overload that accepts a `Version` as second argument")
	Package getPackage(string name, string ver, NativePath path)
	{
		return getPackage(name, Version(ver), path);
	}

	/// ditto
	deprecated("Use another `PackageManager` API, open an issue if none suits you")
	Package getPackage(string name, NativePath path)
	{
		foreach( p; getPackageIterator(name) )
			if (p.path.startsWith(path))
				return p;
		return null;
	}


	/** Looks up the first package matching the given name.
	*/
	deprecated("Use `getBestPackage` instead")
	Package getFirstPackage(string name)
	{
		foreach (ep; getPackageIterator(name))
			return ep;
		return null;
	}

	/** Looks up the latest package matching the given name.
	*/
	deprecated("Use `getBestPackage` with `name, Dependency.any` instead")
	Package getLatestPackage(string name)
	{
		Package pkg;
		foreach (ep; getPackageIterator(name))
			if (pkg is null || pkg.version_ < ep.version_)
				pkg = ep;
		return pkg;
	}

	/** For a given package path, returns the corresponding package.

		If the package is already loaded, a reference is returned. Otherwise
		the package gets loaded and cached for the next call to this function.

		Params:
			path = NativePath to the root directory of the package
			recipe_path = Optional path to the recipe file of the package
			allow_sub_packages = Also return a sub package if it resides in the given folder
			mode = Whether to issue errors, warning, or ignore unknown keys in dub.json

		Returns: The packages loaded from the given path
		Throws: Throws an exception if no package can be loaded
	*/
	Package getOrLoadPackage(NativePath path, NativePath recipe_path = NativePath.init,
		bool allow_sub_packages = false, StrictMode mode = StrictMode.Ignore)
	{
		path.endsWithSlash = true;
		foreach (p; this.m_internal.fromPath)
			if (p.path == path && (!p.parentPackage || (allow_sub_packages && p.parentPackage.path != p.path)))
				return p;
		auto pack = this.load(path, recipe_path, null, null, mode);
		addPackages(this.m_internal.fromPath, pack);
		return pack;
	}

	/**
	 * Loads a `Package` from the filesystem
	 *
	 * This is called when a `Package` needs to be loaded from the path.
	 * This does not change the internal state of the `PackageManager`,
	 * it simply loads the `Package` and returns it - it is up to the caller
	 * to call `addPackages`.
	 *
	 * Throws:
	 *   If no package can be found at the `path` / with the `recipe`.
	 *
	 * Params:
	 *     path = The directory in which the package resides.
	 *     recipe = Optional path to the package recipe file. If left empty,
	 *              the `path` directory will be searched for a recipe file.
	 *     parent = Reference to the parent package, if the new package is a
	 *              sub package.
	 *     version_ = Optional version to associate to the package instead of
	 *                the one declared in the package recipe, or the one
	 *                determined by invoking the VCS (GIT currently).
	 *     mode = Whether to issue errors, warning, or ignore unknown keys in
	 *            dub.json
	 *
	 * Returns: A populated `Package`.
	 */
	protected Package load(NativePath path, NativePath recipe = NativePath.init,
		Package parent = null, string version_ = null,
		StrictMode mode = StrictMode.Ignore)
	{
		if (recipe.empty)
			recipe = this.findPackageFile(path);

		enforce(!recipe.empty,
			"No package file found in %s, expected one of %s"
				.format(path.toNativeString(),
					packageInfoFiles.map!(f => cast(string)f.filename).join("/")));

		const PackageName pname = parent
			? PackageName(parent.name) : PackageName.init;
		string text = this.readText(recipe);
		auto content = parsePackageRecipe(
			text, recipe.toNativeString(), pname, null, mode);
		auto ret = new Package(content, path, parent, version_);
		ret.m_infoFile = recipe;
		return ret;
	}

	/** Searches the given directory for package recipe files.
	 *
	 * Params:
	 *   directory = The directory to search
	 *
	 * Returns:
	 *   Returns the full path to the package file, if any was found.
	 *   Otherwise returns an empty path.
	 */
	public NativePath findPackageFile(NativePath directory)
	{
		foreach (file; packageInfoFiles) {
			auto filename = directory ~ file.filename;
			if (this.existsFile(filename)) return filename;
		}
		return NativePath.init;
	}

	/** For a given SCM repository, returns the corresponding package.

		An SCM repository is provided as its remote URL, the repository is cloned
		and in the dependency specified commit is checked out.

		If the target directory already exists, just returns the package
		without cloning.

		Params:
			name = Package name
			dependency = Dependency that contains the repository URL and a specific commit

		Returns:
			The package loaded from the given SCM repository or null if the
			package couldn't be loaded.
	*/
	Package loadSCMPackage(in PackageName name, in Repository repo)
	in { assert(!repo.empty); }
	do {
		Package pack;

		final switch (repo.kind)
		{
			case repo.Kind.git:
				return this.loadGitPackage(name, repo);
		}
	}

	deprecated("Use the overload that accepts a `dub.dependency : Repository`")
	Package loadSCMPackage(string name, Dependency dependency)
	in { assert(!dependency.repository.empty); }
	do { return this.loadSCMPackage(name, dependency.repository); }

	deprecated("Use `loadSCMPackage(PackageName, Repository)`")
	Package loadSCMPackage(string name, Repository repo)
	{
		return this.loadSCMPackage(PackageName(name), repo);
	}

	private Package loadGitPackage(in PackageName name, in Repository repo)
	{
		if (!repo.ref_.startsWith("~") && !repo.ref_.isGitHash) {
			return null;
		}

		string gitReference = repo.ref_.chompPrefix("~");
		NativePath destination = this.getPackagePath(PlacementLocation.user, name, repo.ref_);

		foreach (p; getPackageIterator(name.toString())) {
			if (p.path == destination) {
				return p;
			}
		}

		if (!this.gitClone(repo.remote, gitReference, destination))
			return null;

		Package result = this.load(destination);
		if (result !is null)
			this.addPackages(this.m_internal.fromPath, result);
		return result;
	}

	/**
	 * Perform a `git clone` operation at `dest` using `repo`
	 *
	 * Params:
	 *   remote = The remote to clone from
	 *   gitref = The git reference to use
	 *   dest   = Where the result of git clone operation is to be stored
	 *
	 * Returns:
	 *	 Whether or not the clone operation was successfull.
	 */
	protected bool gitClone(string remote, string gitref, in NativePath dest)
	{
		static import dub.internal.git;
		return dub.internal.git.cloneRepository(remote, gitref, dest.toNativeString());
	}

	/**
	 * Get the final destination a specific package needs to be stored in.
	 *
	 * See `Location.getPackagePath`.
	 */
	package(dub) NativePath getPackagePath(PlacementLocation base, in PackageName name, string vers)
	{
		assert(this.m_repositories.length == 3, "getPackagePath called in bare mode");
		return this.m_repositories[base].getPackagePath(name, vers);
	}

	/**
	 * Searches for the latest version of a package matching the version range.
	 *
	 * This will search the local file system only (it doesn't connect
	 * to the registry) for the "best" (highest version) that matches `range`.
	 * An overload with a single version exists to search for an exact version.
	 *
	 * Params:
	 *   name = Package name to search for
	 *   vers = Exact version to search for
	 *   range = Range of versions to search for, defaults to any
	 *
	 * Returns:
	 *	 The best package matching the parameters, or `null` if none was found.
	 */
	deprecated("Use the overload that accepts a `PackageName` instead")
	Package getBestPackage(string name, Version vers)
	{
		return this.getBestPackage(PackageName(name), vers);
	}

	/// Ditto
	Package getBestPackage(in PackageName name, in Version vers)
	{
		return this.getBestPackage(name, VersionRange(vers, vers));
	}

	/// Ditto
	deprecated("Use the overload that accepts a `PackageName` instead")
	Package getBestPackage(string name, VersionRange range = VersionRange.Any)
	{
		return this.getBestPackage(PackageName(name), range);
	}

	/// Ditto
	Package getBestPackage(in PackageName name, in VersionRange range = VersionRange.Any)
	{
		return this.getBestPackage_(name, Dependency(range));
	}

	/// Ditto
	deprecated("Use the overload that accepts a `Version` or a `VersionRange`")
	Package getBestPackage(string name, string range)
	{
		return this.getBestPackage(name, VersionRange.fromString(range));
	}

	/// Ditto
	deprecated("`getBestPackage` should only be used with a `Version` or `VersionRange` argument")
	Package getBestPackage(string name, Dependency version_spec, bool enable_overrides = true)
	{
		return this.getBestPackage_(PackageName(name), version_spec, enable_overrides);
	}

	// TODO: Merge this into `getBestPackage(string, VersionRange)`
	private Package getBestPackage_(in PackageName name, in Dependency version_spec,
		bool enable_overrides = true)
	{
		Package ret;
		foreach (p; getPackageIterator(name.toString())) {
			auto vmm = isManagedPackage(p) ? VersionMatchMode.strict : VersionMatchMode.standard;
			if (version_spec.matches(p.version_, vmm) && (!ret || p.version_ > ret.version_))
				ret = p;
		}

		if (enable_overrides && ret) {
			if (auto ovr = getPackage(name, ret.version_))
				return ovr;
		}
		return ret;
	}

	/** Gets the a specific sub package.

		Params:
			base_package = The package from which to get a sub package
			sub_name = Name of the sub package (not prefixed with the base
				package name)
			silent_fail = If set to true, the function will return `null` if no
				package is found. Otherwise will throw an exception.

	*/
	Package getSubPackage(Package base_package, string sub_name, bool silent_fail)
	{
		foreach (p; getPackageIterator(base_package.name~":"~sub_name))
			if (p.parentPackage is base_package)
				return p;
		enforce(silent_fail, "Sub package \""~base_package.name~":"~sub_name~"\" doesn't exist.");
		return null;
	}


	/** Determines if a package is managed by DUB.

		Managed packages can be upgraded and removed.
	*/
	bool isManagedPackage(const(Package) pack)
	const {
		auto ppath = pack.basePackage.path;
		return isManagedPath(ppath);
	}

	/** Determines if a specific path is within a DUB managed package folder.

		By default, managed folders are "~/.dub/packages" and
		"/var/lib/dub/packages".
	*/
	bool isManagedPath(NativePath path)
	const {
		foreach (rep; m_repositories)
			if (rep.isManaged(path))
				return true;
		return false;
	}

	/** Enables iteration over all known local packages.

		Returns: A delegate suitable for use with `foreach` is returned.
	*/
	int delegate(int delegate(ref Package)) getPackageIterator()
	{
		// See `m_initialized` documentation
		if (!this.m_initialized)
			this.refresh();

		int iterator(int delegate(ref Package) del)
		{
			// Search scope by priority, internal has the highest
			foreach (p; this.m_internal.fromPath)
				if (auto ret = del(p)) return ret;
			foreach (p; this.m_internal.localPackages)
				if (auto ret = del(p)) return ret;

			foreach (ref repo; m_repositories) {
				foreach (p; repo.localPackages)
					if (auto ret = del(p)) return ret;
				foreach (p; repo.fromPath)
					if (auto ret = del(p)) return ret;
			}
			return 0;
		}

		return &iterator;
	}

	/** Enables iteration over all known local packages with a certain name.

		Returns: A delegate suitable for use with `foreach` is returned.
	*/
	int delegate(int delegate(ref Package)) getPackageIterator(string name)
	{
		int iterator(int delegate(ref Package) del)
		{
			foreach (p; getPackageIterator())
				if (p.name == name)
					if (auto ret = del(p)) return ret;
			return 0;
		}

		return &iterator;
	}


	/** Returns a list of all package overrides for the given scope.
	*/
	deprecated(OverrideDepMsg)
	const(PackageOverride)[] getOverrides(PlacementLocation scope_)
	const {
		return cast(typeof(return)) this.getOverrides_(scope_);
	}

	package(dub) const(PackageOverride_)[] getOverrides_(PlacementLocation scope_)
	const {
		return m_repositories[scope_].overrides;
	}

	/** Adds a new override for the given package.
	*/
	deprecated("Use the overload that accepts a `VersionRange` as 3rd argument")
	void addOverride(PlacementLocation scope_, string package_, Dependency version_spec, Version target)
	{
		m_repositories[scope_].overrides ~= PackageOverride(package_, version_spec, target);
		m_repositories[scope_].writeOverrides(this);
	}
	/// ditto
	deprecated("Use the overload that accepts a `VersionRange` as 3rd argument")
	void addOverride(PlacementLocation scope_, string package_, Dependency version_spec, NativePath target)
	{
		m_repositories[scope_].overrides ~= PackageOverride(package_, version_spec, target);
		m_repositories[scope_].writeOverrides(this);
	}

	/// Ditto
	deprecated(OverrideDepMsg)
	void addOverride(PlacementLocation scope_, string package_, VersionRange source, Version target)
	{
		this.addOverride_(scope_, package_, source, target);
	}
	/// ditto
	deprecated(OverrideDepMsg)
	void addOverride(PlacementLocation scope_, string package_, VersionRange source, NativePath target)
	{
		this.addOverride_(scope_, package_, source, target);
	}

	// Non deprecated version that is used by `commandline`. Do not use!
	package(dub) void addOverride_(PlacementLocation scope_, string package_, VersionRange source, Version target)
	{
		m_repositories[scope_].overrides ~= PackageOverride_(package_, source, target);
		m_repositories[scope_].writeOverrides(this);
	}
	// Non deprecated version that is used by `commandline`. Do not use!
	package(dub) void addOverride_(PlacementLocation scope_, string package_, VersionRange source, NativePath target)
	{
		m_repositories[scope_].overrides ~= PackageOverride_(package_, source, target);
		m_repositories[scope_].writeOverrides(this);
	}

	/** Removes an existing package override.
	*/
	deprecated("Use the overload that accepts a `VersionRange` as 3rd argument")
	void removeOverride(PlacementLocation scope_, string package_, Dependency version_spec)
	{
		version_spec.visit!(
			(VersionRange src) => this.removeOverride(scope_, package_, src),
			(any) { throw new Exception(format("No override exists for %s %s", package_, version_spec)); },
		);
	}

	deprecated(OverrideDepMsg)
	void removeOverride(PlacementLocation scope_, string package_, VersionRange src)
	{
		this.removeOverride_(scope_, package_, src);
	}

	package(dub) void removeOverride_(PlacementLocation scope_, string package_, VersionRange src)
	{
		Location* rep = &m_repositories[scope_];
		foreach (i, ovr; rep.overrides) {
			if (ovr.package_ != package_ || ovr.source != src)
				continue;
			rep.overrides = rep.overrides[0 .. i] ~ rep.overrides[i+1 .. $];
			(*rep).writeOverrides(this);
			return;
		}
		throw new Exception(format("No override exists for %s %s", package_, src));
	}

	deprecated("Use `store(NativePath source, PlacementLocation dest, string name, Version vers)`")
	Package storeFetchedPackage(NativePath zip_file_path, Json package_info, NativePath destination)
	{
		import dub.internal.vibecompat.core.file;

		return this.store_(readFile(zip_file_path), destination,
			PackageName(package_info["name"].get!string),
			Version(package_info["version"].get!string));
	}

	/**
	 * Store a zip file stored at `src` into a managed location `destination`
	 *
	 * This will extracts the package supplied as (as a zip file) to the
	 * `destination` and sets a version field in the package description.
	 * In the future, we should aim not to alter the package description,
	 * but this is done for backward compatibility.
	 *
	 * Params:
	 *   src = The path to the zip file containing the package
	 *   dest = At which `PlacementLocation`  the package should be stored
	 *   name = Name of the package being stored
	 *   vers = Version of the package
	 *
	 * Returns:
	 *   The `Package` after it has been loaded.
	 *
	 * Throws:
	 *   If the package cannot be loaded / the zip is corrupted / the package
	 *   already exists, etc...
	 */
	deprecated("Use the overload that accepts a `PackageName` instead")
	Package store(NativePath src, PlacementLocation dest, string name, Version vers)
	{
		return this.store(src, dest, PackageName(name), vers);
	}

	/// Ditto
	Package store(NativePath src, PlacementLocation dest, in PackageName name,
		in Version vers)
	{
		import dub.internal.vibecompat.core.file;

		auto data = readFile(src);
		return this.store(data, dest, name, vers);
	}

	/// Ditto
	Package store(ubyte[] data, PlacementLocation dest,
		in PackageName name, in Version vers)
	{
		import dub.internal.vibecompat.core.file;

		assert(!name.sub.length, "Cannot store a subpackage, use main package instead");
		NativePath dstpath = this.getPackagePath(dest, name, vers.toString());
		this.ensureDirectory(dstpath.parentPath());
		const lockPath = dstpath.parentPath() ~ ".lock";

		// possibly wait for other dub instance
		import core.time : seconds;
		auto lock = lockFile(lockPath.toNativeString(), 30.seconds);
		if (this.existsFile(dstpath)) {
			return this.getPackage(name, vers, dest);
		}
		return this.store_(data, dstpath, name, vers);
	}

	/// Backward-compatibility for deprecated overload, simplify once `storeFetchedPatch`
	/// is removed
	private Package store_(ubyte[] data, NativePath destination,
		in PackageName name, in Version vers)
	{
		import dub.internal.vibecompat.core.file;
		import std.range : walkLength;

		logDebug("Placing package '%s' version '%s' to location '%s'",
			name, vers, destination.toNativeString());

		enforce(!this.existsFile(destination),
			"%s (%s) needs to be removed from '%s' prior placement."
			.format(name, vers, destination));

		ZipArchive archive = new ZipArchive(data);
		logDebug("Extracting from zip.");

		// In a GitHub zip, the actual contents are in a sub-folder
		alias PSegment = typeof(NativePath.init.head);
		PSegment[] zip_prefix;
		outer: foreach(ArchiveMember am; archive.directory) {
			auto path = NativePath(am.name).bySegment.array;
			foreach (fil; packageInfoFiles)
				if (path.length == 2 && path[$-1].name == fil.filename) {
					zip_prefix = path[0 .. $-1];
					break outer;
				}
		}

		logDebug("zip root folder: %s", zip_prefix);

		NativePath getCleanedPath(string fileName) {
			auto path = NativePath(fileName);
			if (zip_prefix.length && !path.bySegment.startsWith(zip_prefix)) return NativePath.init;
			static if (is(typeof(path[0 .. 1]))) return path[zip_prefix.length .. $];
			else return NativePath(path.bySegment.array[zip_prefix.length .. $]);
		}

		void setAttributes(NativePath path, ArchiveMember am)
		{
			import std.datetime : DosFileTimeToSysTime;

			auto mtime = DosFileTimeToSysTime(am.time);
			this.setTimes(path, mtime, mtime);
			if (auto attrs = am.fileAttributes)
				this.setAttributes(path, attrs);
		}

		// extract & place
		this.ensureDirectory(destination);
		logDebug("Copying all files...");
		int countFiles = 0;
		foreach(ArchiveMember a; archive.directory) {
			auto cleanedPath = getCleanedPath(a.name);
			if(cleanedPath.empty) continue;
			auto dst_path = destination ~ cleanedPath;

			logDebug("Creating %s", cleanedPath);
			if (dst_path.endsWithSlash) {
				this.ensureDirectory(dst_path);
			} else {
				this.ensureDirectory(dst_path.parentPath);
				// for symlinks on posix systems, use the symlink function to
				// create them. Windows default unzip doesn't handle symlinks,
				// so we don't need to worry about it for Windows.
				version(Posix) {
					import core.sys.posix.sys.stat;
					if( S_ISLNK(cast(mode_t)a.fileAttributes) ){
						import core.sys.posix.unistd;
						// need to convert name and target to zero-terminated string
						auto target = toStringz(cast(const(char)[])archive.expand(a));
						auto dstFile = toStringz(dst_path.toNativeString());
						enforce(symlink(target, dstFile) == 0, "Error creating symlink: " ~ dst_path.toNativeString());
						goto symlink_exit;
					}
				}

				this.writeFile(dst_path, archive.expand(a));
				setAttributes(dst_path, a);
symlink_exit:
				++countFiles;
			}
		}
		logDebug("%s file(s) copied.", to!string(countFiles));

		// overwrite dub.json (this one includes a version field)
		auto pack = this.load(destination, NativePath.init, null, vers.toString());

		if (pack.recipePath.head != defaultPackageFilename)
			// Storeinfo saved a default file, this could be different to the file from the zip.
			this.removeFile(pack.recipePath);
		pack.storeInfo();
		addPackages(this.m_internal.localPackages, pack);
		return pack;
	}

	/// Removes the given the package.
	void remove(in Package pack)
	{
		logDebug("Remove %s, version %s, path '%s'", pack.name, pack.version_, pack.path);
		enforce(!pack.path.empty, "Cannot remove package "~pack.name~" without a path.");
		enforce(pack.parentPackage is null, "Cannot remove subpackage %s".format(pack.name));

		// remove package from repositories' list
		bool found = false;
		bool removeFrom(Package[] packs, in Package pack) {
			auto packPos = countUntil!("a.path == b.path")(packs, pack);
			if(packPos != -1) {
				packs = .remove(packs, packPos);
				return true;
			}
			return false;
		}
		foreach(repo; m_repositories) {
			if (removeFrom(repo.fromPath, pack)) {
				found = true;
				break;
			}
			// Maintain backward compatibility with pre v1.30.0 behavior,
			// this is equivalent to remove-local
			if (removeFrom(repo.localPackages, pack)) {
				found = true;
				break;
			}
		}
		if(!found)
			found = removeFrom(this.m_internal.localPackages, pack);
		enforce(found, "Cannot remove, package not found: '"~ pack.name ~"', path: " ~ to!string(pack.path));

		logDebug("About to delete root folder for package '%s'.", pack.path);
		import std.file : rmdirRecurse;
		rmdirRecurse(pack.path.toNativeString());
		logInfo("Removed", Color.yellow, "%s %s", pack.name.color(Mode.bold), pack.version_);
	}

	/// Compatibility overload. Use the version without a `force_remove` argument instead.
	deprecated("Use `remove(pack)` directly instead, the boolean has no effect")
	void remove(in Package pack, bool force_remove)
	{
		remove(pack);
	}

	Package addLocalPackage(NativePath path, string verName, PlacementLocation type)
	{
		// As we iterate over `localPackages` we need it to be populated
		// In theory we could just populate that specific repository,
		// but multiple calls would then become inefficient.
		if (!this.m_initialized)
			this.refresh();

		path.endsWithSlash = true;
		auto pack = this.load(path);
		enforce(pack.name.length, "The package has no name, defined in: " ~ path.toString());
		if (verName.length)
			pack.version_ = Version(verName);

		// don't double-add packages
		Package[]* packs = &m_repositories[type].localPackages;
		foreach (p; *packs) {
			if (p.path == path) {
				enforce(p.version_ == pack.version_, "Adding the same local package twice with differing versions is not allowed.");
				logInfo("Package is already registered: %s (version: %s)", p.name, p.version_);
				return p;
			}
		}

		addPackages(*packs, pack);

		this.m_repositories[type].writeLocalPackageList(this);

		logInfo("Registered package: %s (version: %s)", pack.name, pack.version_);
		return pack;
	}

	void removeLocalPackage(NativePath path, PlacementLocation type)
	{
		// As we iterate over `localPackages` we need it to be populated
		// In theory we could just populate that specific repository,
		// but multiple calls would then become inefficient.
		if (!this.m_initialized)
			this.refresh();

		path.endsWithSlash = true;
		Package[]* packs = &m_repositories[type].localPackages;
		size_t[] to_remove;
		foreach( i, entry; *packs )
			if( entry.path == path )
				to_remove ~= i;
		enforce(to_remove.length > 0, "No "~type.to!string()~" package found at "~path.toNativeString());

		string[Version] removed;
		foreach (i; to_remove)
			removed[(*packs)[i].version_] = (*packs)[i].name;

		*packs = (*packs).enumerate
			.filter!(en => !to_remove.canFind(en.index))
			.map!(en => en.value).array;

		this.m_repositories[type].writeLocalPackageList(this);

		foreach(ver, name; removed)
			logInfo("Deregistered package: %s (version: %s)", name, ver);
	}

	/// For the given type add another path where packages will be looked up.
	void addSearchPath(NativePath path, PlacementLocation type)
	{
		m_repositories[type].searchPath ~= path;
		this.m_repositories[type].writeLocalPackageList(this);
	}

	/// Removes a search path from the given type.
	void removeSearchPath(NativePath path, PlacementLocation type)
	{
		m_repositories[type].searchPath = m_repositories[type].searchPath.filter!(p => p != path)().array();
		this.m_repositories[type].writeLocalPackageList(this);
	}

	deprecated("Use `refresh()` without boolean argument(same as `refresh(false)`")
	void refresh(bool refresh)
	{
		if (refresh)
			logDiagnostic("Refreshing local packages (refresh existing: true)...");
		this.refresh_(refresh);
	}

	void refresh()
	{
		this.refresh_(false);
	}

	private void refresh_(bool refresh)
	{
		if (!refresh)
			logDiagnostic("Scanning local packages...");

		foreach (ref repository; this.m_repositories)
			repository.scanLocalPackages(refresh, this);

		this.m_internal.scan(this, refresh);
		foreach (ref repository; this.m_repositories)
			repository.scan(this, refresh);

		foreach (ref repository; this.m_repositories)
			repository.loadOverrides(this);
		this.m_initialized = true;
	}

	alias Hash = ubyte[];
	/// Generates a hash digest for a given package.
	/// Some files or folders are ignored during the generation (like .dub and
	/// .svn folders)
	Hash hashPackage(Package pack)
	{
		import std.file;
		import dub.internal.vibecompat.core.file;

		string[] ignored_directories = [".git", ".dub", ".svn"];
		// something from .dub_ignore or what?
		string[] ignored_files = [];
		SHA256 hash;
		foreach(file; dirEntries(pack.path.toNativeString(), SpanMode.depth)) {
			const isDir = file.isDir;
			if(isDir && ignored_directories.canFind(NativePath(file.name).head.name))
				continue;
			else if(ignored_files.canFind(NativePath(file.name).head.name))
				continue;

			hash.put(cast(ubyte[])NativePath(file.name).head.name);
			if(isDir) {
				logDebug("Hashed directory name %s", NativePath(file.name).head);
			}
			else {
				hash.put(cast(ubyte[]) readFile(NativePath(file.name)));
				logDebug("Hashed file contents from %s", NativePath(file.name).head);
			}
		}
		auto digest = hash.finish();
		logDebug("Project hash: %s", digest);
		return digest[].dup;
	}

	/**
	 * Writes the selections file (`dub.selections.json`)
	 *
	 * The selections file is only used for the root package / project.
	 * However, due to it being a filesystem interaction, it is managed
	 * from the `PackageManager`.
	 *
	 * Params:
	 *   project = The root package / project to read the selections file for.
	 *   selections = The `SelectionsFile` to write.
	 *   overwrite = Whether to overwrite an existing selections file.
	 *               True by default.
	 */
	public void writeSelections(in Package project, in Selections!1 selections,
		bool overwrite = true)
	{
		const path = project.path ~ "dub.selections.json";
		if (!overwrite && this.existsFile(path))
			return;
		this.writeFile(path, selectionsToString(selections));
	}

	/// Package function to avoid code duplication with deprecated
	/// SelectedVersions.save, merge with `writeSelections` in
	/// the future.
	package static string selectionsToString (in Selections!1 s)
	{
		Json json = selectionsToJSON(s);
		assert(json.type == Json.Type.object);
		assert(json.length == 2 || json.length == 3);
		assert(json["versions"].type != Json.Type.undefined);

		auto result = appender!string();
		result.put("{\n\t\"fileVersion\": ");
		result.writeJsonString(json["fileVersion"]);
		if (s.inheritable)
			result.put(",\n\t\"inheritable\": true");
		result.put(",\n\t\"versions\": {");
		auto vers = json["versions"].get!(Json[string]);
		bool first = true;
		foreach (k; vers.byKey.array.sort()) {
			if (!first) result.put(",");
			else first = false;
			result.put("\n\t\t");
			result.writeJsonString(Json(k));
			result.put(": ");
			result.writeJsonString(vers[k]);
		}
		result.put("\n\t}\n}\n");
		return result.data;
	}

	/// Ditto
	package static Json selectionsToJSON (in Selections!1 s)
	{
		Json serialized = Json.emptyObject;
		serialized["fileVersion"] = s.fileVersion;
		if (s.inheritable)
			serialized["inheritable"] = true;
		serialized["versions"] = Json.emptyObject;
		foreach (p, dep; s.versions)
			serialized["versions"][p] = dep.toJson(true);
		return serialized;
	}

	/// Adds the package and scans for sub-packages.
	protected void addPackages(ref Package[] dst_repos, Package pack)
	{
		// Add the main package.
		dst_repos ~= pack;

		// Additionally to the internally defined sub-packages, whose metadata
		// is loaded with the main dub.json, load all externally defined
		// packages after the package is available with all the data.
		foreach (spr; pack.subPackages) {
			Package sp;

			if (spr.path.length) {
				auto p = NativePath(spr.path);
				p.normalize();
				enforce(!p.absolute, "Sub package paths must be sub paths of the parent package.");
				auto path = pack.path ~ p;
				sp = this.load(path, NativePath.init, pack);
			} else sp = new Package(spr.recipe, pack.path, pack);

			// Add the sub-package.
			try {
				dst_repos ~= sp;
			} catch (Exception e) {
				logError("Package '%s': Failed to load sub-package %s: %s", pack.name,
					spr.path.length ? spr.path : spr.recipe.name, e.msg);
				logDiagnostic("Full error: %s", e.toString().sanitize());
			}
		}
	}

	/// Used for dependency injection
	protected bool existsDirectory(NativePath path)
	{
		static import dub.internal.vibecompat.core.file;
		return dub.internal.vibecompat.core.file.existsDirectory(path);
	}

	/// Ditto
	protected void ensureDirectory(NativePath path)
	{
		static import dub.internal.vibecompat.core.file;
		return dub.internal.vibecompat.core.file.ensureDirectory(path);
	}

	/// Ditto
	protected bool existsFile(NativePath path)
	{
		static import dub.internal.vibecompat.core.file;
		return dub.internal.vibecompat.core.file.existsFile(path);
	}

	/// Ditto
	protected void writeFile(NativePath path, const(ubyte)[] data)
	{
		static import dub.internal.vibecompat.core.file;
		return dub.internal.vibecompat.core.file.writeFile(path, data);
	}

	/// Ditto
	protected void writeFile(NativePath path, const(char)[] data)
	{
		static import dub.internal.vibecompat.core.file;
		return dub.internal.vibecompat.core.file.writeFile(path, data);
	}

	/// Ditto
	protected string readText(NativePath path)
	{
		static import dub.internal.vibecompat.core.file;
		return dub.internal.vibecompat.core.file.readText(path);
	}

	/// Ditto
	protected alias IterateDirDg = int delegate(scope int delegate(ref FileInfo));

	/// Ditto
	protected IterateDirDg iterateDirectory(NativePath path)
	{
		static import dub.internal.vibecompat.core.file;
		return dub.internal.vibecompat.core.file.iterateDirectory(path);
	}

	/// Ditto
	protected void removeFile(NativePath path)
	{
		static import dub.internal.vibecompat.core.file;
		return dub.internal.vibecompat.core.file.removeFile(path);
	}

	/// Ditto
	protected void setTimes(in NativePath path, in SysTime accessTime,
		in SysTime modificationTime)
	{
		static import std.file;
		std.file.setTimes(
			path.toNativeString(), accessTime, modificationTime);
	}

	/// Ditto
	protected void setAttributes(in NativePath path, uint attributes)
	{
		static import std.file;
		std.file.setAttributes(path.toNativeString(), attributes);
	}
}

deprecated(OverrideDepMsg)
alias PackageOverride = PackageOverride_;

package(dub) struct PackageOverride_ {
	private alias ResolvedDep = SumType!(NativePath, Version);
	string package_;
	VersionRange source;
	ResolvedDep target;

	deprecated("Use `source` instead")
	@property inout(Dependency) version_ () inout return @safe {
		return Dependency(this.source);
	}

	deprecated("Assign `source` instead")
	@property ref PackageOverride version_ (Dependency v) scope return @safe pure {
		this.source = v.visit!(
			(VersionRange range) => range,
			(any) {
				int a; if (a) return VersionRange.init; // Trick the compiler
				throw new Exception("Cannot use anything else than a `VersionRange` for overrides");
			},
		);
		return this;
	}

	deprecated("Use `target.match` directly instead")
	@property inout(Version) targetVersion () inout return @safe pure nothrow @nogc {
		return this.target.match!(
			(Version v) => v,
			(any) => Version.init,
		);
	}

	deprecated("Assign `target` directly instead")
	@property ref PackageOverride targetVersion (Version v) scope return pure nothrow @nogc {
		this.target = v;
		return this;
	}

	deprecated("Use `target.match` directly instead")
	@property inout(NativePath) targetPath () inout return @safe pure nothrow @nogc {
		return this.target.match!(
			(NativePath v) => v,
			(any) => NativePath.init,
		);
	}

	deprecated("Assign `target` directly instead")
	@property ref PackageOverride targetPath (NativePath v) scope return pure nothrow @nogc {
		this.target = v;
		return this;
	}

	deprecated("Use the overload that accepts a `VersionRange` as 2nd argument")
	this(string package_, Dependency version_, Version target_version)
	{
		this.package_ = package_;
		this.version_ = version_;
		this.target = target_version;
	}

	deprecated("Use the overload that accepts a `VersionRange` as 2nd argument")
	this(string package_, Dependency version_, NativePath target_path)
	{
		this.package_ = package_;
		this.version_ = version_;
		this.target = target_path;
	}

	this(string package_, VersionRange src, Version target)
	{
		this.package_ = package_;
		this.source = src;
		this.target = target;
	}

	this(string package_, VersionRange src, NativePath target)
	{
		this.package_ = package_;
		this.source = src;
		this.target = target;
	}
}

deprecated("Use `PlacementLocation` instead")
enum LocalPackageType : PlacementLocation {
	package_ = PlacementLocation.local,
	user     = PlacementLocation.user,
	system   = PlacementLocation.system,
}

private enum LocalPackagesFilename = "local-packages.json";
private enum LocalOverridesFilename = "local-overrides.json";

/**
 * A managed location, with packages, configuration, and overrides
 *
 * There exists three standards locations, listed in `PlacementLocation`.
 * The user one is the default, with the system and local one meeting
 * different needs.
 *
 * Each location has a root, under which the following may be found:
 * - A `packages/` directory, where packages are stored (see `packagePath`);
 * - A `local-packages.json` file, with extra search paths
 *   and manually added packages (see `dub add-local`);
 * - A `local-overrides.json` file, with manually added overrides (`dub add-override`);
 *
 * Additionally, each location host a config file,
 * which is not managed by this module, but by dub itself.
 */
package struct Location {
	/// The absolute path to the root of the location
	NativePath packagePath;

	/// Configured (extra) search paths for this `Location`
	NativePath[] searchPath;

	/**
	 * List of manually registered packages at this `Location`
	 * and stored in `local-packages.json`
	 */
	Package[] localPackages;

	/// List of overrides stored at this `Location`
	PackageOverride_[] overrides;

	/**
	 * List of packages stored under `packagePath` and automatically detected
	 */
	Package[] fromPath;

	this(NativePath path) @safe pure nothrow @nogc
	{
		this.packagePath = path;
	}

	void loadOverrides(PackageManager mgr)
	{
		this.overrides = null;
		auto ovrfilepath = this.packagePath ~ LocalOverridesFilename;
		if (mgr.existsFile(ovrfilepath)) {
			logWarn("Found local override file: %s", ovrfilepath);
			logWarn(OverrideDepMsg);
			logWarn("Replace with a path-based dependency in your project or a custom cache path");
			const text = mgr.readText(ovrfilepath);
			auto json = parseJsonString(text, ovrfilepath.toNativeString());
			foreach (entry; json) {
				PackageOverride_ ovr;
				ovr.package_ = entry["name"].get!string;
				ovr.source = VersionRange.fromString(entry["version"].get!string);
				if (auto pv = "targetVersion" in entry) ovr.target = Version(pv.get!string);
				if (auto pv = "targetPath" in entry) ovr.target = NativePath(pv.get!string);
				this.overrides ~= ovr;
			}
		}
	}

	private void writeOverrides(PackageManager mgr)
	{
		Json[] newlist;
		foreach (ovr; this.overrides) {
			auto jovr = Json.emptyObject;
			jovr["name"] = ovr.package_;
			jovr["version"] = ovr.source.toString();
			ovr.target.match!(
				(NativePath path) { jovr["targetPath"] = path.toNativeString(); },
				(Version	vers) { jovr["targetVersion"] = vers.toString(); },
			);
			newlist ~= jovr;
		}
		auto path = this.packagePath;
		mgr.ensureDirectory(path);
		auto app = appender!string();
		app.writePrettyJsonString(Json(newlist));
		mgr.writeFile(path ~ LocalOverridesFilename, app.data);
	}

	private void writeLocalPackageList(PackageManager mgr)
	{
		Json[] newlist;
		foreach (p; this.searchPath) {
			auto entry = Json.emptyObject;
			entry["name"] = "*";
			entry["path"] = p.toNativeString();
			newlist ~= entry;
		}

		foreach (p; this.localPackages) {
			if (p.parentPackage) continue; // do not store sub packages
			auto entry = Json.emptyObject;
			entry["name"] = p.name;
			entry["version"] = p.version_.toString();
			entry["path"] = p.path.toNativeString();
			newlist ~= entry;
		}

		NativePath path = this.packagePath;
		mgr.ensureDirectory(path);
		auto app = appender!string();
		app.writePrettyJsonString(Json(newlist));
		mgr.writeFile(path ~ LocalPackagesFilename, app.data);
	}

	// load locally defined packages
	void scanLocalPackages(bool refresh, PackageManager manager)
	{
		NativePath list_path = this.packagePath;
		Package[] packs;
		NativePath[] paths;
		try {
			auto local_package_file = list_path ~ LocalPackagesFilename;
			if (!manager.existsFile(local_package_file)) return;

			logDiagnostic("Loading local package map at %s", local_package_file.toNativeString());
			const text = manager.readText(local_package_file);
			auto packlist = parseJsonString(
				text, local_package_file.toNativeString());
			enforce(packlist.type == Json.Type.array, LocalPackagesFilename ~ " must contain an array.");
			foreach (pentry; packlist) {
				try {
					auto name = pentry["name"].get!string;
					auto path = NativePath(pentry["path"].get!string);
					if (name == "*") {
						paths ~= path;
					} else {
						auto ver = Version(pentry["version"].get!string);

						Package pp;
						if (!refresh) {
							foreach (p; this.localPackages)
								if (p.path == path) {
									pp = p;
									break;
								}
						}

						if (!pp) {
							auto infoFile = manager.findPackageFile(path);
							if (!infoFile.empty) pp = manager.load(path, infoFile);
							else {
								logWarn("Locally registered package %s %s was not found. Please run 'dub remove-local \"%s\"'.",
										name, ver, path.toNativeString());
								// Store a dummy package
								pp = new Package(PackageRecipe(name), path);
							}
						}

						if (pp.name != name)
							logWarn("Local package at %s has different name than %s (%s)", path.toNativeString(), name, pp.name);
						pp.version_ = ver;
						manager.addPackages(packs, pp);
					}
				} catch (Exception e) {
					logWarn("Error adding local package: %s", e.msg);
				}
			}
		} catch (Exception e) {
			logDiagnostic("Loading of local package list at %s failed: %s", list_path.toNativeString(), e.msg);
		}
		this.localPackages = packs;
		this.searchPath = paths;
	}

	/**
	 * Scan this location
	 */
	void scan(PackageManager mgr, bool refresh)
	{
		// If we're asked to refresh, reload the packages from scratch
		auto existing = refresh ? null : this.fromPath;
		if (this.packagePath !is NativePath.init) {
			// For the internal location, we use `fromPath` to store packages
			// loaded by the user (e.g. the project and its sub-packages),
			// so don't clean it.
			this.fromPath = null;
		}
		foreach (path; this.searchPath)
			this.scanPackageFolder(path, mgr, existing);
		if (this.packagePath !is NativePath.init)
			this.scanPackageFolder(this.packagePath, mgr, existing);
	}

    /**
     * Scan the content of a folder (`packagePath` or in `searchPaths`),
     * and add all packages that were found to this location.
     */
	void scanPackageFolder(NativePath path, PackageManager mgr,
		Package[] existing_packages)
	{
		if (!mgr.existsDirectory(path))
			return;

		void loadInternal (NativePath pack_path, NativePath packageFile)
		{
			import std.algorithm.searching : find;

			// If the package has already been loaded, no need to re-load it.
			auto rng = existing_packages.find!(pp => pp.path == pack_path);
			if (!rng.empty)
				return mgr.addPackages(this.fromPath, rng.front);

			try {
				mgr.addPackages(this.fromPath, mgr.load(pack_path, packageFile));
			} catch (ConfigException exc) {
				// Configy error message already include the path
				logError("Invalid recipe for local package: %S", exc);
			} catch (Exception e) {
				logError("Failed to load package in %s: %s", pack_path, e.msg);
				logDiagnostic("Full error: %s", e.toString().sanitize());
			}
		}

		logDebug("iterating dir %s", path.toNativeString());
		try foreach (pdir; mgr.iterateDirectory(path)) {
			logDebug("iterating dir %s entry %s", path.toNativeString(), pdir.name);
			if (!pdir.isDirectory) continue;

			const pack_path = path ~ (pdir.name ~ "/");
			auto packageFile = mgr.findPackageFile(pack_path);

			if (isManaged(path)) {
				// Old / flat directory structure, used in non-standard path
				// Packages are stored in $ROOT/$SOMETHING/`
				if (!packageFile.empty) {
					// Deprecated flat managed directory structure
					logWarn("Package at path '%s' should be under '%s'",
							pack_path.toNativeString().color(Mode.bold),
							(pack_path ~ "$VERSION" ~ pdir.name).toNativeString().color(Mode.bold));
					logWarn("The package will no longer be detected starting from v1.42.0");
					loadInternal(pack_path, packageFile);
				} else {
					// New managed structure: $ROOT/$NAME/$VERSION/$NAME
					// This is the most common code path

					// Iterate over versions of a package
					foreach (versdir; mgr.iterateDirectory(pack_path)) {
						if (!versdir.isDirectory) continue;
						auto vers_path = pack_path ~ versdir.name ~ (pdir.name ~ "/");
						if (!mgr.existsDirectory(vers_path)) continue;
						packageFile = mgr.findPackageFile(vers_path);
						loadInternal(vers_path, packageFile);
					}
				}
			} else {
				// Unmanaged directories (dub add-path) are always stored as a
				// flat list of packages, as these are the working copies managed
				// by the user. The nested structure should not be supported,
				// even optionally, because that would lead to bogus "no package
				// file found" errors in case the internal directory structure
				// accidentally matches the $NAME/$VERSION/$NAME scheme
				if (!packageFile.empty)
					loadInternal(pack_path, packageFile);
			}
		}
		catch (Exception e)
			logDiagnostic("Failed to enumerate %s packages: %s", path.toNativeString(), e.toString());
	}

	/**
	 * Looks up already-loaded packages at a specific version
	 *
	 * Looks up a package according to this `Location`'s priority,
	 * that is, packages from the search path and local packages
	 * have the highest priority.
	 *
	 * Params:
	 *	 name = The full name of the package to look up
	 *	 ver  = The version to look up
	 *
	 * Returns:
	 *	 A `Package` if one was found, `null` if none exists.
	 */
	inout(Package) lookup(in PackageName name, in Version ver) inout {
		foreach (pkg; this.localPackages)
			if (pkg.name == name.toString() &&
				pkg.version_.matches(ver, VersionMatchMode.standard))
				return pkg;
		foreach (pkg; this.fromPath) {
			auto pvm = this.isManaged(pkg.basePackage.path) ?
				VersionMatchMode.strict : VersionMatchMode.standard;
			if (pkg.name == name.toString() && pkg.version_.matches(ver, pvm))
				return pkg;
		}
		return null;
	}

	/**
	 * Looks up a package, first in the list of loaded packages,
	 * then directly on the file system.
	 *
	 * This function allows for lazy loading of packages, without needing to
	 * first scan all the available locations (as `scan` does).
	 *
	 * Params:
	 *	 name  = The full name of the package to look up
	 *	 vers  = The version the package must match
	 *	 mgr   = The `PackageManager` to use for adding packages
	 *
	 * Returns:
	 *	 A `Package` if one was found, `null` if none exists.
	 */
	Package load (in PackageName name, Version vers, PackageManager mgr)
	{
		if (auto pkg = this.lookup(name, vers))
			return pkg;

		string versStr = vers.toString();
		const path = this.getPackagePath(name, versStr);
		if (!mgr.existsDirectory(path))
			return null;

		logDiagnostic("Lazily loading package %s:%s from %s", name.main, vers, path);
		auto p = mgr.load(path);
		enforce(
			p.version_ == vers,
			format("Package %s located in %s has a different version than its path: Got %s, expected %s",
				name, path, p.version_, vers));
		mgr.addPackages(this.fromPath, p);
		return p;
	}

	/**
	 * Get the final destination a specific package needs to be stored in.
	 *
	 * Note that there needs to be an extra level for libraries like `ae`
	 * which expects their containing folder to have an exact name and use
	 * `importPath "../"`.
	 *
	 * Hence the final format returned is `$BASE/$NAME/$VERSION/$NAME`,
	 * `$BASE` is `this.packagePath`.
	 *
	 * Params:
	 *   name = The package name - if the name is that of a subpackage,
	 *          only the path to the main package is returned, as the
	 *          subpackage path can only be known after reading the recipe.
	 *   vers = A version string. Typed as a string because git hashes
	 *          can be used with this function.
	 *
	 * Returns:
	 *   An absolute `NativePath` nested in this location.
	 */
	NativePath getPackagePath (in PackageName name, string vers)
	{
		NativePath result = this.packagePath ~ name.main.toString() ~ vers ~
			name.main.toString();
		result.endsWithSlash = true;
		return result;
	}

	/// Determines if a specific path is within a DUB managed Location.
	bool isManaged(NativePath path) const {
		return path.startsWith(this.packagePath);
	}
}

private immutable string OverrideDepMsg =
	"Overrides are deprecated as they are redundant with more fine-grained approaches";
