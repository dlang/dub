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

import std.algorithm : countUntil, filter, sort, canFind, remove;
import std.array;
import std.conv;
import std.digest.sha;
import std.encoding : sanitize;
import std.exception;
import std.file;
import std.string;
import std.sumtype;
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

/// The PackageManager can retrieve present packages and get / remove
/// packages.
class PackageManager {
	private {
		Location[] m_repositories;
		NativePath[] m_searchPath;
		Package[] m_packages;
		Package[] m_temporaryPackages;
		bool m_disableDefaultSearchPaths = false;
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
		this.m_searchPath = [ path ];
		this.m_disableDefaultSearchPaths = true;
		this.refresh(true);
	}

	deprecated("Use the overload which accepts 3 `NativePath` arguments")
	this(NativePath user_path, NativePath system_path, bool refresh_packages = true)
	{
		m_repositories = [
			Location(user_path ~ "packages/"),
			Location(system_path ~ "packages/")];

		if (refresh_packages) refresh(true);
	}

	this(NativePath package_path, NativePath user_path, NativePath system_path, bool refresh_packages = true)
	{
		m_repositories = [
			Location(package_path ~ ".dub/packages/"),
			Location(user_path ~ "packages/"),
			Location(system_path ~ "packages/")];

		if (refresh_packages) refresh(true);
	}

	/** Gets/sets the list of paths to search for local packages.
	*/
	@property void searchPath(NativePath[] paths)
	{
		if (paths == m_searchPath) return;
		m_searchPath = paths.dup;
		refresh(false);
	}
	/// ditto
	@property const(NativePath)[] searchPath() const { return m_searchPath; }

	/** Disables searching DUB's predefined search paths.
	*/
	deprecated("Instantiate a PackageManager instance with the single-argument constructor: `new PackageManager(path)`")
	@property void disableDefaultSearchPaths(bool val)
	{
		if (val == m_disableDefaultSearchPaths) return;
		m_disableDefaultSearchPaths = val;
		refresh(true);
	}

	/** Returns the effective list of search paths, including default ones.
	*/
	@property const(NativePath)[] completeSearchPath()
	const {
		auto ret = appender!(const(NativePath)[])();
		ret.put(m_searchPath);
		if (!m_disableDefaultSearchPaths) {
			foreach (ref repo; m_repositories) {
				ret.put(repo.searchPath);
				ret.put(repo.packagePath);
			}
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

		refresh(false);
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

		foreach (p; getPackageIterator(name))
			if (p.version_.matches(ver, isManagedPackage(p) ? VersionMatchMode.strict : VersionMatchMode.standard))
				return p;

		return null;
	}

	/// ditto
	Package getPackage(string name, string ver, bool enable_overrides = true)
	{
		return getPackage(name, Version(ver), enable_overrides);
	}

	/// ditto
	Package getPackage(string name, Version ver, NativePath path)
	{
		foreach (p; getPackageIterator(name)) {
			auto pvm = isManagedPackage(p) ? VersionMatchMode.strict : VersionMatchMode.standard;
			if (p.version_.matches(ver, pvm) && p.path.startsWith(path))
				return p;
		}
		return null;
	}

	/// ditto
	Package getPackage(string name, string ver, NativePath path)
	{
		return getPackage(name, Version(ver), path);
	}

	/// ditto
	Package getPackage(string name, NativePath path)
	{
		foreach( p; getPackageIterator(name) )
			if (p.path.startsWith(path))
				return p;
		return null;
	}


	/** Looks up the first package matching the given name.
	*/
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

		Returns: The packages loaded from the given path
		Throws: Throws an exception if no package can be loaded
	*/
	Package getOrLoadPackage(NativePath path, NativePath recipe_path = NativePath.init, bool allow_sub_packages = false)
	{
		path.endsWithSlash = true;
		foreach (p; getPackageIterator())
			if (p.path == path && (!p.parentPackage || (allow_sub_packages && p.parentPackage.path != p.path)))
				return p;
		auto pack = Package.load(path, recipe_path);
		addPackages(m_temporaryPackages, pack);
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
            addPackages(m_temporaryPackages, pack);
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
		NativePath destination = getPackagePath(
			m_repositories[PlacementLocation.user].packagePath,
			name, repo.ref_);
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
	 * Note that there needs to be an extra level for libraries like `ae`
	 * which expects their containing folder to have an exact name and use
	 * `importPath "../"`.
	 *
	 * Hence the final format should be `$BASE/$NAME-$VERSION/$NAME`,
	 * but this function returns `$BASE/$NAME-$VERSION/`
	 */
	package(dub) static NativePath getPackagePath (NativePath base, string name, string vers)
	{
		// + has special meaning for Optlink
		string clean_vers = vers.chompPrefix("~").replace("+", "_");
		NativePath result = base ~ (name ~ "-" ~ clean_vers);
		result.endsWithSlash = true;
		return result;
	}

	/** Searches for the latest version of a package matching the given dependency.
	*/
	Package getBestPackage(string name, Dependency version_spec, bool enable_overrides = true)
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

	/// ditto
	Package getBestPackage(string name, string version_spec)
	{
		return getBestPackage(name, Dependency(version_spec));
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
		int iterator(int delegate(ref Package) del)
		{
			foreach (tp; m_temporaryPackages)
				if (auto ret = del(tp)) return ret;

			// first search local packages
			foreach (ref repo; m_repositories)
				foreach (p; repo.localPackages)
					if (auto ret = del(p)) return ret;

			// and then all packages gathered from the search path
			foreach( p; m_packages )
				if( auto ret = del(p) )
					return ret;
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
	const(PackageOverride)[] getOverrides(PlacementLocation scope_)
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
	void addOverride(PlacementLocation scope_, string package_, VersionRange source, Version target)
	{
		m_repositories[scope_].overrides ~= PackageOverride(package_, source, target);
		m_repositories[scope_].writeOverrides();
	}
	/// ditto
	void addOverride(PlacementLocation scope_, string package_, VersionRange source, NativePath target)
	{
		m_repositories[scope_].overrides ~= PackageOverride(package_, source, target);
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

	void removeOverride(PlacementLocation scope_, string package_, VersionRange src)
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

	/// Extracts the package supplied as a path to it's zip file to the
	/// destination and sets a version field in the package description.
	Package storeFetchedPackage(NativePath zip_file_path, Json package_info, NativePath destination)
	{
		import std.range : walkLength;

		auto package_name = package_info["name"].get!string;
		auto package_version = package_info["version"].get!string;

		logDebug("Placing package '%s' version '%s' to location '%s' from file '%s'",
			package_name, package_version, destination.toNativeString(), zip_file_path.toNativeString());

		if( existsFile(destination) ){
			throw new Exception(format("%s (%s) needs to be removed from '%s' prior placement.", package_name, package_version, destination));
		}

		// open zip file
		ZipArchive archive;
		{
			logDebug("Opening file %s", zip_file_path);
			auto f = openFile(zip_file_path, FileMode.read);
			scope(exit) f.close();
			archive = new ZipArchive(f.readAll());
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
				{
					auto dstFile = openFile(dst_path, FileMode.createTrunc);
					scope(exit) dstFile.close();
					dstFile.put(archive.expand(a));
				}
				setAttributes(dst_path.toNativeString(), a);
				++countFiles;
			}
		}
		logDebug("%s file(s) copied.", to!string(countFiles));

		// overwrite dub.json (this one includes a version field)
		auto pack = Package.load(destination, NativePath.init, null, package_info["version"].get!string);

		if (pack.recipePath.head != defaultPackageFilename)
			// Storeinfo saved a default file, this could be different to the file from the zip.
			removeFile(pack.recipePath);
		pack.storeInfo();
		addPackages(m_packages, pack);
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
			if(removeFrom(repo.localPackages, pack)) {
				found = true;
				break;
			}
		}
		if(!found)
			found = removeFrom(m_packages, pack);
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
		path.endsWithSlash = true;

		Package[]* packs = &m_repositories[type].localPackages;
		size_t[] to_remove;
		foreach( i, entry; *packs )
			if( entry.path == path )
				to_remove ~= i;
		enforce(to_remove.length > 0, "No "~type.to!string()~" package found at "~path.toNativeString());

		string[Version] removed;
		foreach_reverse( i; to_remove ) {
			removed[(*packs)[i].version_] = (*packs)[i].name;
			*packs = (*packs)[0 .. i] ~ (*packs)[i+1 .. $];
		}

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

	void refresh(bool refresh_existing_packages)
	{
		logDiagnostic("Refreshing local packages (refresh existing: %s)...", refresh_existing_packages);

		if (!m_disableDefaultSearchPaths)
		{
			this.m_repositories[PlacementLocation.system].scanLocalPackages(refresh_existing_packages, this);
			this.m_repositories[PlacementLocation.user].scanLocalPackages(refresh_existing_packages, this);
			this.m_repositories[PlacementLocation.local].scanLocalPackages(refresh_existing_packages, this);
		}

		auto old_packages = m_packages;

		// rescan the system and user package folder
		void scanPackageFolder(NativePath path)
		{
			if( path.existsDirectory() ){
				logDebug("iterating dir %s", path.toNativeString());
				try foreach( pdir; iterateDirectory(path) ){
					logDebug("iterating dir %s entry %s", path.toNativeString(), pdir.name);
					if (!pdir.isDirectory) continue;

					// Old / flat directory structure, used in non-standard path
					// Packages are stored in $ROOT/$SOMETHING/`
					auto pack_path = path ~ (pdir.name ~ "/");
					auto packageFile = Package.findPackageFile(pack_path);

					// New (since 2015) managed structure:
					// $ROOT/$NAME-$VERSION/$NAME
					// This is the most common code path
					if (isManagedPath(path) && packageFile.empty) {
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
						if (!refresh_existing_packages)
							foreach (pp; old_packages)
								if (pp.path == pack_path) {
									p = pp;
									break;
								}
						if (!p) p = Package.load(pack_path, packageFile);
						addPackages(m_packages, p);
					} catch( Exception e ){
						logError("Failed to load package in %s: %s", pack_path, e.msg);
						logDiagnostic("Full error: %s", e.toString().sanitize());
					}
				}
				catch(Exception e) logDiagnostic("Failed to enumerate %s packages: %s", path.toNativeString(), e.toString());
			}
		}

		m_packages = null;
		foreach (p; this.completeSearchPath)
			scanPackageFolder(p);

		if (!m_disableDefaultSearchPaths)
		{
			this.m_repositories[PlacementLocation.local].loadOverrides();
			this.m_repositories[PlacementLocation.user].loadOverrides();
			this.m_repositories[PlacementLocation.system].loadOverrides();
		}
	}

	alias Hash = ubyte[];
	/// Generates a hash value for a given package.
	/// Some files or folders are ignored during the generation (like .dub and
	/// .svn folders)
	Hash hashPackage(Package pack)
	{
		string[] ignored_directories = [".git", ".dub", ".svn"];
		// something from .dub_ignore or what?
		string[] ignored_files = [];
		SHA1 sha1;
		foreach(file; dirEntries(pack.path.toNativeString(), SpanMode.depth)) {
			if(file.isDir && ignored_directories.canFind(NativePath(file.name).head.name))
				continue;
			else if(ignored_files.canFind(NativePath(file.name).head.name))
				continue;

			sha1.put(cast(ubyte[])NativePath(file.name).head.name);
			if(file.isDir) {
				logDebug("Hashed directory name %s", NativePath(file.name).head);
			}
			else {
				sha1.put(openFile(NativePath(file.name)).readAll());
				logDebug("Hashed file contents from %s", NativePath(file.name).head);
			}
		}
		auto hash = sha1.finish();
		logDebug("Project hash: %s", hash);
		return hash[].dup;
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

struct PackageOverride {
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

/// A managed location (see `PlacementLocation`)
private struct Location {
	/// The absolute path to the root of the location
	NativePath packagePath;

	/// Configured (extra) search paths for this `Location`
	NativePath[] searchPath;

	/// List of packages at this `Location`
	Package[] localPackages;

	/// List of overrides stored at this `Location`
	PackageOverride[] overrides;

	this(NativePath path) @safe pure nothrow @nogc
	{
		this.packagePath = path;
	}

	void loadOverrides()
	{
		this.overrides = null;
		auto ovrfilepath = this.packagePath ~ LocalOverridesFilename;
		if (existsFile(ovrfilepath)) {
			foreach (entry; jsonFromFile(ovrfilepath)) {
				PackageOverride ovr;
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
	void scanLocalPackages(bool refresh_existing_packages, PackageManager manager)
	{
		NativePath list_path = this.packagePath;
		Package[] packs;
		NativePath[] paths;
		try {
			auto local_package_file = list_path ~ LocalPackagesFilename;
			logDiagnostic("Looking for local package map at %s", local_package_file.toNativeString());
			if (!existsFile(local_package_file)) return;

			logDiagnostic("Try to load local package map at %s", local_package_file.toNativeString());
			auto packlist = jsonFromFile(list_path ~ LocalPackagesFilename);
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
						if (!refresh_existing_packages) {
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
}
