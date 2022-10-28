/**
	Management of packages on the local computer.

	Copyright: © 2012-2016 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Matthias Dondorff
*/
module dub.packagemanager;

import dub.dependency;
import dub.internal.utils;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.path;
import dub.internal.logging;
import dub.package_;
import dub.recipe.io;
import configy.Exceptions;
public import configy.Read : StrictMode;

import dyaml.stdsumtype;

import std.algorithm : countUntil, filter, map, sort, canFind, remove;
import std.array;
import std.conv;
import std.digest.sha;
import std.encoding : sanitize;
import std.exception;
import std.file;
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
	private {
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
		 * From v1.31 onwards, those locations are not scanned eagerly,
		 * unless one of the function requiring eager scanning does,
		 * such as `getBestPackage` - as it needs to iterate the list
		 * of available packages.
		 */
		bool m_initialized;
	}

	/**
	   Instantiate an instance with a single search path

	   This constructor is used when dub is invoked with the '--bar' CLI switch.
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
	private Package lookup (string name, Version vers) {
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
	Package getPackage(string name, Version ver, bool enable_overrides = true)
	{
		if (enable_overrides) {
			foreach (ref repo; m_repositories)
				foreach (ovr; repo.overrides)
					if (ovr.package_ == name && ovr.source.matches(ver)) {
						Package pack = ovr.target.match!(
							(NativePath path) => getOrLoadPackage(path),
							(Version	vers) => getPackage(name, vers, false),
						);
						if (pack) return pack;

						ovr.target.match!(
							(any) {
								logWarn("Package override %s %s -> '%s' doesn't reference an existing package.",
										ovr.package_, ovr.version_, any);
							},
						);
					}
		}

		return this.lookup(name, ver);
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
	Package getPackage(string name, Version ver, PlacementLocation loc)
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
		auto pack = Package.load(path, recipe_path, null, null, mode);
		addPackages(this.m_internal.fromPath, pack);
		return pack;
	}

	/** For a given SCM repository, returns the corresponding package.

		An SCM repository is provided as its remote URL, the repository is cloned
		and in the dependency speicfied commit is checked out.

		If the target directory already exists, just returns the package
		without cloning.

		Params:
			name = Package name
			dependency = Dependency that contains the repository URL and a specific commit

		Returns:
			The package loaded from the given SCM repository or null if the
			package couldn't be loaded.
	*/
	deprecated("Use the overload that accepts a `dub.dependency : Repository`")
	Package loadSCMPackage(string name, Dependency dependency)
	in { assert(!dependency.repository.empty); }
	do { return this.loadSCMPackage(name, dependency.repository); }

	/// Ditto
	Package loadSCMPackage(string name, Repository repo)
	in { assert(!repo.empty); }
	do {
		Package pack;

		final switch (repo.kind)
		{
			case repo.Kind.git:
				pack = loadGitPackage(name, repo);
		}
		if (pack !is null) {
			addPackages(this.m_internal.fromPath, pack);
		}
		return pack;
	}

	private Package loadGitPackage(string name, in Repository repo)
	{
		import dub.internal.git : cloneRepository;

		if (!repo.ref_.startsWith("~") && !repo.ref_.isGitHash) {
			return null;
		}

		string gitReference = repo.ref_.chompPrefix("~");
		NativePath destination = this.getPackagePath(PlacementLocation.user, name, repo.ref_);
		// For libraries leaking their import path
		destination ~= name;
		destination.endsWithSlash = true;

		foreach (p; getPackageIterator(name)) {
			if (p.path == destination) {
				return p;
			}
		}

		if (!cloneRepository(repo.remote, gitReference, destination.toNativeString())) {
			return null;
		}

		return Package.load(destination);
	}

	/**
	 * Get the final destination a specific package needs to be stored in.
	 *
	 * See `Location.getPackagePath`.
	 */
	package(dub) NativePath getPackagePath (PlacementLocation base, string name, string vers)
	{
		assert(this.m_repositories.length == 3, "getPackagePath called in bare mode");
		return this.m_repositories[base].getPackagePath(name, vers);
	}

	/**
	 * Searches for the latest version of a package matching the version range.
	 *
	 * This will search the local filesystem only (it doesn't connect
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
	Package getBestPackage(string name, Version vers)
	{
		return this.getBestPackage(name, VersionRange(vers, vers));
	}

	/// Ditto
	Package getBestPackage(string name, VersionRange range = VersionRange.Any)
	{
		return this.getBestPackage_(name, Dependency(range));
	}

	/// Ditto
	Package getBestPackage(string name, string range)
	{
		return this.getBestPackage(name, VersionRange.fromString(range));
	}

	/// Ditto
	deprecated("`getBestPackage` should only be used with a `Version` or `VersionRange` argument")
	Package getBestPackage(string name, Dependency version_spec, bool enable_overrides = true)
	{
		return this.getBestPackage_(name, version_spec, enable_overrides);
	}

	// TODO: Merge this into `getBestPackage(string, VersionRange)`
	private Package getBestPackage_(string name, Dependency version_spec, bool enable_overrides = true)
	{
		Package ret;
		foreach (p; getPackageIterator(name)) {
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

		In contrast to `Package.getSubPackage`, this function supports path
		based sub packages.

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
	bool isManagedPackage(Package pack)
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
		foreach (rep; m_repositories) {
			NativePath rpath = rep.packagePath;
			if (path.startsWith(rpath))
				return true;
		}
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
		m_repositories[scope_].writeOverrides();
	}
	/// ditto
	deprecated("Use the overload that accepts a `VersionRange` as 3rd argument")
	void addOverride(PlacementLocation scope_, string package_, Dependency version_spec, NativePath target)
	{
		m_repositories[scope_].overrides ~= PackageOverride(package_, version_spec, target);
		m_repositories[scope_].writeOverrides();
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
		m_repositories[scope_].writeOverrides();
	}
	// Non deprecated version that is used by `commandline`. Do not use!
	package(dub) void addOverride_(PlacementLocation scope_, string package_, VersionRange source, NativePath target)
	{
		m_repositories[scope_].overrides ~= PackageOverride_(package_, source, target);
		m_repositories[scope_].writeOverrides();
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
			(*rep).writeOverrides();
			return;
		}
		throw new Exception(format("No override exists for %s %s", package_, src));
	}

	deprecated("Use `store(NativePath source, PlacementLocation dest, string name, Version vers)`")
	Package storeFetchedPackage(NativePath zip_file_path, Json package_info, NativePath destination)
	{
		return this.store_(zip_file_path, destination, package_info["name"].get!string,
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
	Package store(NativePath src, PlacementLocation dest, string name, Version vers)
	{
		NativePath dstpath = this.getPackagePath(dest, name, vers.toString());
		if (!dstpath.existsFile())
			mkdirRecurse(dstpath.toNativeString());
		// For libraries leaking their import path
		dstpath = dstpath ~ name;

		// possibly wait for other dub instance
		import core.time : seconds;
		auto lock = lockFile(dstpath.toNativeString() ~ ".lock", 30.seconds);
		if (dstpath.existsFile()) {
			return this.getPackage(name, vers, dest);
		}
		return this.store_(src, dstpath, name, vers);
	}

	/// Backward-compatibility for deprecated overload, simplify once `storeFetchedPatch`
	/// is removed
	private Package store_(NativePath src, NativePath destination, string name, Version vers)
	{
		import std.range : walkLength;

		logDebug("Placing package '%s' version '%s' to location '%s' from file '%s'",
			name, vers, destination.toNativeString(), src.toNativeString());

		if( existsFile(destination) ){
			throw new Exception(format("%s (%s) needs to be removed from '%s' prior placement.",
				name, vers, destination));
		}

		// open zip file
		ZipArchive archive;
		{
			logDebug("Opening file %s", src);
			archive = new ZipArchive(readFile(src));
		}

		logDebug("Extracting from zip.");

		// In a github zip, the actual contents are in a subfolder
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

		static void setAttributes(string path, ArchiveMember am)
		{
			import std.datetime : DosFileTimeToSysTime;

			auto mtime = DosFileTimeToSysTime(am.time);
			setTimes(path, mtime, mtime);
			if (auto attrs = am.fileAttributes)
				std.file.setAttributes(path, attrs);
		}

		// extract & place
		mkdirRecurse(destination.toNativeString());
		logDebug("Copying all files...");
		int countFiles = 0;
		foreach(ArchiveMember a; archive.directory) {
			auto cleanedPath = getCleanedPath(a.name);
			if(cleanedPath.empty) continue;
			auto dst_path = destination ~ cleanedPath;

			logDebug("Creating %s", cleanedPath);
			if( dst_path.endsWithSlash ){
				if( !existsDirectory(dst_path) )
					mkdirRecurse(dst_path.toNativeString());
			} else {
				if( !existsDirectory(dst_path.parentPath) )
					mkdirRecurse(dst_path.parentPath.toNativeString());
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

				writeFile(dst_path, archive.expand(a));
				setAttributes(dst_path.toNativeString(), a);
symlink_exit:
				++countFiles;
			}
		}
		logDebug("%s file(s) copied.", to!string(countFiles));

		// overwrite dub.json (this one includes a version field)
		auto pack = Package.load(destination, NativePath.init, null, vers.toString());

		if (pack.recipePath.head != defaultPackageFilename)
			// Storeinfo saved a default file, this could be different to the file from the zip.
			removeFile(pack.recipePath);
		pack.storeInfo();
		addPackages(this.m_internal.localPackages, pack);
		return pack;
	}

	/// Removes the given the package.
	void remove(in Package pack)
	{
		logDebug("Remove %s, version %s, path '%s'", pack.name, pack.version_, pack.path);
		enforce(!pack.path.empty, "Cannot remove package "~pack.name~" without a path.");

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
		auto pack = Package.load(path);
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

		this.m_repositories[type].writeLocalPackageList();

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

		this.m_repositories[type].writeLocalPackageList();

		foreach(ver, name; removed)
			logInfo("Deregistered package: %s (version: %s)", name, ver);
	}

	/// For the given type add another path where packages will be looked up.
	void addSearchPath(NativePath path, PlacementLocation type)
	{
		m_repositories[type].searchPath ~= path;
		this.m_repositories[type].writeLocalPackageList();
	}

	/// Removes a search path from the given type.
	void removeSearchPath(NativePath path, PlacementLocation type)
	{
		m_repositories[type].searchPath = m_repositories[type].searchPath.filter!(p => p != path)().array();
		this.m_repositories[type].writeLocalPackageList();
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
			repository.loadOverrides();
		this.m_initialized = true;
	}

	alias Hash = ubyte[];
	/// Generates a hash digest for a given package.
	/// Some files or folders are ignored during the generation (like .dub and
	/// .svn folders)
	Hash hashPackage(Package pack)
	{
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

	/// Adds the package and scans for subpackages.
	private void addPackages(ref Package[] dst_repos, Package pack)
	const {
		// Add the main package.
		dst_repos ~= pack;

		// Additionally to the internally defined subpackages, whose metadata
		// is loaded with the main dub.json, load all externally defined
		// packages after the package is available with all the data.
		foreach (spr; pack.subPackages) {
			Package sp;

			if (spr.path.length) {
				auto p = NativePath(spr.path);
				p.normalize();
				enforce(!p.absolute, "Sub package paths must be sub paths of the parent package.");
				auto path = pack.path ~ p;
				if (!existsFile(path)) {
					logError("Package %s declared a sub-package, definition file is missing: %s", pack.name, path.toNativeString());
					continue;
				}
				sp = Package.load(path, NativePath.init, pack);
			} else sp = new Package(spr.recipe, pack.path, pack);

			// Add the subpackage.
			try {
				dst_repos ~= sp;
			} catch (Exception e) {
				logError("Package '%s': Failed to load sub-package %s: %s", pack.name,
					spr.path.length ? spr.path : spr.recipe.name, e.msg);
				logDiagnostic("Full error: %s", e.toString().sanitize());
			}
		}
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
private struct Location {
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

	void loadOverrides()
	{
		this.overrides = null;
		auto ovrfilepath = this.packagePath ~ LocalOverridesFilename;
		if (existsFile(ovrfilepath)) {
			logWarn("Found local override file: %s", ovrfilepath);
			logWarn(OverrideDepMsg);
			logWarn("Replace with a path-based dependency in your project or a custom cache path");
			foreach (entry; jsonFromFile(ovrfilepath)) {
				PackageOverride_ ovr;
				ovr.package_ = entry["name"].get!string;
				ovr.source = VersionRange.fromString(entry["version"].get!string);
				if (auto pv = "targetVersion" in entry) ovr.target = Version(pv.get!string);
				if (auto pv = "targetPath" in entry) ovr.target = NativePath(pv.get!string);
				this.overrides ~= ovr;
			}
		}
	}

	private void writeOverrides()
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
		if (!existsDirectory(path)) mkdirRecurse(path.toNativeString());
		writeJsonFile(path ~ LocalOverridesFilename, Json(newlist));
	}

	private void writeLocalPackageList()
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
		if( !existsDirectory(path) ) mkdirRecurse(path.toNativeString());
		writeJsonFile(path ~ LocalPackagesFilename, Json(newlist));
	}

	// load locally defined packages
	void scanLocalPackages(bool refresh, PackageManager manager)
	{
		NativePath list_path = this.packagePath;
		Package[] packs;
		NativePath[] paths;
		try {
			auto local_package_file = list_path ~ LocalPackagesFilename;
			if (!existsFile(local_package_file)) return;

			logDiagnostic("Loading local package map at %s", local_package_file.toNativeString());
			auto packlist = jsonFromFile(local_package_file);
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
							auto infoFile = Package.findPackageFile(path);
							if (!infoFile.empty) pp = Package.load(path, infoFile);
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
			// loaded by the user (e.g. the project and its subpackages),
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
		if (!path.existsDirectory())
			return;

		logDebug("iterating dir %s", path.toNativeString());
		try foreach (pdir; iterateDirectory(path)) {
			logDebug("iterating dir %s entry %s", path.toNativeString(), pdir.name);
			if (!pdir.isDirectory) continue;

			// Old / flat directory structure, used in non-standard path
			// Packages are stored in $ROOT/$SOMETHING/`
			auto pack_path = path ~ (pdir.name ~ "/");
			auto packageFile = Package.findPackageFile(pack_path);

			// New (since 2015) managed structure:
			// $ROOT/$NAME-$VERSION/$NAME
			// This is the most common code path
			if (mgr.isManagedPath(path) && packageFile.empty) {
				foreach (subdir; iterateDirectory(path ~ (pdir.name ~ "/")))
					if (subdir.isDirectory && pdir.name.startsWith(subdir.name)) {
						pack_path ~= subdir.name ~ "/";
						packageFile = Package.findPackageFile(pack_path);
						break;
					}
			}

			if (packageFile.empty) continue;
			Package p;
			try {
				foreach (pp; existing_packages)
					if (pp.path == pack_path) {
						p = pp;
						break;
					}
				if (!p) p = Package.load(pack_path, packageFile);
				mgr.addPackages(this.fromPath, p);
			} catch (ConfigException exc) {
				// Confiy error message already include the path
				logError("Invalid recipe for local package: %S", exc);
			} catch (Exception e) {
				logError("Failed to load package in %s: %s", pack_path, e.msg);
				logDiagnostic("Full error: %s", e.toString().sanitize());
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
	private inout(Package) lookup(string name, Version ver) inout {
		foreach (pkg; this.localPackages)
			if (pkg.name == name && pkg.version_.matches(ver, VersionMatchMode.strict))
				return pkg;
		foreach (pkg; this.fromPath)
			if (pkg.name == name && pkg.version_.matches(ver, VersionMatchMode.strict))
				return pkg;
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
	private Package load (string name, Version vers, PackageManager mgr)
	{
		if (auto pkg = this.lookup(name, vers))
			return pkg;

		string versStr = vers.toString();
		const lookupName = getBasePackageName(name);
		const path = this.getPackagePath(lookupName, versStr) ~ (lookupName ~ "/");
		if (!path.existsDirectory())
			return null;

		logDiagnostic("Lazily loading package %s:%s from %s", lookupName, vers, path);
		auto p = Package.load(path);
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
	 * Hence the final format should be `$BASE/$NAME-$VERSION/$NAME`,
	 * but this function returns `$BASE/$NAME-$VERSION/`
	 * `$BASE` is `this.packagePath`.
	 */
	private NativePath getPackagePath (string name, string vers)
	{
		// + has special meaning for Optlink
		string clean_vers = vers.chompPrefix("~").replace("+", "_");
		NativePath result = this.packagePath ~ (name ~ "-" ~ clean_vers);
		result.endsWithSlash = true;
		return result;
	}
}

private immutable string OverrideDepMsg =
	"Overrides are deprecated as they are redundant with more fine-grained approaches";
