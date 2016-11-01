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
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.path;
import dub.package_;

import std.algorithm : countUntil, filter, sort, canFind, remove, all;
import std.array;
import std.conv;
import std.encoding : sanitize;
import std.exception;
import std.file;
import std.range : only, isInputRange;
import std.string;
import std.zip;


/// The PackageManager can retrieve present packages and get / remove
/// packages.
class PackageManager {
	private {
		Repository[Path] m_repos;
		Path[LocalPackageType] m_defaultPaths; // only to support deprecated API
		Path[] m_searchPath;
		Package[] m_packages;
		Package[] m_temporaryPackages;
		bool m_disableRepoSearchPaths = false;
	}

	deprecated this(Path user_path, Path system_path, bool refresh_packages = true)
	{
		m_defaultPaths[LocalPackageType.user] = user_path;
		m_defaultPaths[LocalPackageType.system] = system_path;
		this(only(user_path, system_path), refresh_packages);
	}

	this(R)(R repo_paths, bool refresh_packages = true)
	if (isInputRange!R && is(typeof(Repository(repo_paths.front))))
	in { assert(repo_paths.all!(p => p.absolute )); }
	body
	{
		foreach (path; repo_paths)
		{
			path.normalize();
			m_repos[path] = Repository(path);
		}
		if (refresh_packages) refresh(true);
	}

	/** Gets/sets the list of paths to search for local packages.
	*/
	@property void searchPath(const(Path)[] paths)
	{
		if (paths == m_searchPath) return;
		m_searchPath = paths.dup;
		refresh(false);
	}
	/// ditto
	@property const(Path)[] searchPath() const { return m_searchPath; }

	deprecated alias disableDefaultSearchPaths = disableRepoSearchPaths;

	/** Disables searching DUB's predefined search paths.
	*/
	@property void disableRepoSearchPaths(bool val)
	{
		if (val == m_disableRepoSearchPaths) return;
		m_disableRepoSearchPaths = val;
		refresh(true);
	}

	/** Returns the effective list of search paths, including default ones.
	*/
	@property const(Path)[] completeSearchPath()
	const {
		auto ret = appender!(Path[])();
		ret.put(cast(Path[])m_searchPath); // work around Phobos 17251
		if (!m_disableRepoSearchPaths) {
			foreach (repo; m_repos) {
				ret.put(cast(Path[])repo.searchPath);
				ret.put(cast(Path)repo.packagePath);
			}
		}
		return ret.data;
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
		if (enable_overrides)
			foreach (repo; m_repos)
				foreach (ovr; repo.overrides)
					if (ovr.package_ == name && ovr.version_.matches(ver)) {
						Package pack;
						if (!ovr.targetPath.empty) pack = getOrLoadPackage(ovr.targetPath);
						else pack = getPackage(name, ovr.targetVersion, false);
						if (pack) return pack;

						logWarn("Package override %s %s -> %s %s doesn't reference an existing package.",
							ovr.package_, ovr.version_, ovr.targetVersion, ovr.targetPath);
					}

		foreach (p; getPackageIterator(name))
			if (p.version_ == ver)
				return p;

		return null;
	}

	/// ditto
	Package getPackage(string name, string ver, bool enable_overrides = true)
	{
		return getPackage(name, Version(ver), enable_overrides);
	}

	/// ditto
	Package getPackage(string name, Version ver, Path path)
	{
		auto ret = getPackage(name, path);
		if (!ret || ret.version_ != ver) return null;
		return ret;
	}

	/// ditto
	Package getPackage(string name, string ver, Path path)
	{
		return getPackage(name, Version(ver), path);
	}

	/// ditto
	Package getPackage(string name, Path path)
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

	/** For a given package path, returns the corresponding package.

		If the package is already loaded, a reference is returned. Otherwise
		the package gets loaded and cached for the next call to this function.

		Params:
			path = Path to the root directory of the package
			recipe_path = Optional path to the recipe file of the package
			allow_sub_packages = Also return a sub package if it resides in the given folder

		Returns: The packages loaded from the given path
		Throws: Throws an exception if no package can be loaded
	*/
	Package getOrLoadPackage(Path path, Path recipe_path = Path.init, bool allow_sub_packages = false)
	{
		path.endsWithSlash = true;
		foreach (p; getPackageIterator())
			if (p.path == path && (!p.parentPackage || (allow_sub_packages && p.parentPackage.path != p.path)))
				return p;
		auto pack = Package.load(path, recipe_path);
		addPackages(m_temporaryPackages, pack);
		return pack;
	}


	/** Searches for the latest version of a package matching the given dependency.
	*/
	Package getBestPackage(string name, Dependency version_spec, bool enable_overrides = true)
	{
		Package ret;
		foreach (p; getPackageIterator(name))
			if (version_spec.matches(p.version_) && (!ret || p.version_ > ret.version_))
				ret = p;

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

		In contrast to `Package.getInternalSubPackage`, this function supports path
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

		Passing allowSubDirs = true will cause only the roots of the managed
		folders to be matched
	*/
	bool isManagedPath(Path path, bool allowSubDirs = true)
	const
	in { assert(path.absolute); }
	body
	{
		path.normalize();
		if (allowSubDirs) {
			foreach (rep; m_repos) {
				Path rpath = rep.packagePath;
				if (path.startsWith(rpath))
					return true;
			}
			return false;
		}
		else
			return !!(path in m_repos);
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
			foreach (ref repo; m_repos) // TODO: is ref necessary here?
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
	deprecated const(PackageOverride)[] getOverrides(LocalPackageType scope_)
	{
		return getOverrides(m_defaultPaths[scope_]);
	}
	/// ditto
	const(PackageOverride)[] getOverrides(Path repoPath)
	in { assert(repoPath.absolute); }
	body
	{
		repoPath.normalize();
		return m_repos[repoPath].getOverrides();
	}

	/** Adds a new override for the given package.
	*/
	deprecated void addOverride(LocalPackageType scope_, string package_, Dependency version_spec, Version target)
	{
		addOverride(m_defaultPaths[scope_], package_, version_spec, target);
	}
	/// ditto
	deprecated void addOverride(LocalPackageType scope_, string package_, Dependency version_spec, Path target)
	{
		addOverride(m_defaultPaths[scope_], package_, version_spec, target);
	}
	/// ditto
	void addOverride(Path repoPath, string package_, Dependency version_spec, Version target)
	in { assert(repoPath.absolute); }
	body
	{
		repoPath.normalize();
		m_repos[repoPath].addOverride(package_, version_spec, target);
	}
	/// ditto
	void addOverride(Path repoPath, string package_, Dependency version_spec, Path target)
	in { assert(repoPath.absolute); }
	body
	{
		repoPath.normalize();
		m_repos[repoPath].addOverride(package_, version_spec, target);
	}

	/** Removes an existing package override.
	*/
	deprecated void removeOverride(LocalPackageType scope_, string package_, Dependency version_spec)
	{
		removeOverride(m_defaultPaths[scope_], package_, version_spec);
	}
	/// ditto
	void removeOverride(Path repoPath, string package_, Dependency version_spec)
	in { assert(repoPath.absolute); }
	body
	{
		repoPath.normalize();
		m_repos[repoPath].removeOverride(package_, version_spec);
	}

	/// Extracts the package supplied as a path to it's zip file to the
	/// destination and sets a version field in the package description.
	Package storeFetchedPackage(Path zip_file_path, Json package_info, Path destination)
	{
		auto package_name = package_info["name"].get!string;
		auto package_version = package_info["version"].get!string;
		auto clean_package_version = package_version[package_version.startsWith("~") ? 1 : 0 .. $];

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
		Path zip_prefix;
		outer: foreach(ArchiveMember am; archive.directory) {
			auto path = Path(am.name);
			foreach (fil; packageInfoFiles)
				if (path.length == 2 && path.head.toString == fil.filename) {
					zip_prefix = path[0 .. $-1];
					break outer;
				}
		}

		logDebug("zip root folder: %s", zip_prefix);

		Path getCleanedPath(string fileName) {
			auto path = Path(fileName);
			if(zip_prefix != Path() && !path.startsWith(zip_prefix)) return Path();
			return path[zip_prefix.length..path.length];
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
			auto dst_path = destination~cleanedPath;

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
		auto pack = Package.load(destination, Path.init, null, package_info["version"].get!string);

		if (pack.recipePath.head != defaultPackageFilename)
			// Storeinfo saved a default file, this could be different to the file from the zip.
			removeFile(pack.recipePath);
		pack.storeInfo();
		addPackages(m_packages, pack);
		return pack;
	}

	/// Removes the given package.
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
		foreach(repo; m_repos) {
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
		logInfo("Removed package: '"~pack.name~"'");
	}

	/// Compatibility overload. Use the version without a `force_remove` argument instead.
	void remove(in Package pack, bool force_remove)
	{
		remove(pack);
	}

	deprecated Package addLocalPackage(Path path, string verName, LocalPackageType type)
	{
		return addLocalPackage(path, verName, m_defaultPaths[type]);
	}
	Package addLocalPackage(Path path, string verName, Path repoPath)
	in { assert(repoPath.absolute); }
	body
{
		repoPath.normalize();
		return m_repos[repoPath].addLocalPackage(path, verName);
	}

	deprecated void removeLocalPackage(Path path, LocalPackageType type)
	{
		removeLocalPackage(path, m_defaultPaths[type]);
	}
	void removeLocalPackage(Path path, Path repoPath)
	in { assert(repoPath.absolute); }
	body
	{
		repoPath.normalize();
		m_repos[repoPath].removeLocalPackage(path);
	}

	/// For the given type add another path where packages will be looked up.
	deprecated void addSearchPath(Path path, LocalPackageType type)
	{
		addSearchPath(path, m_defaultPaths[type]);
	}
	/// ditto
	void addSearchPath(Path path, Path repoPath)
	in { assert(repoPath.absolute); }
	body
	{
		repoPath.normalize();
		m_repos[repoPath].addSearchPath(path);
	}

	/// Removes a search path from the given type.
	deprecated void removeSearchPath(Path path, LocalPackageType type)
	{
		removeSearchPath(path, m_defaultPaths[type]);
	}
	/// ditto
	void removeSearchPath(Path path, Path repoPath)
	in { assert(repoPath.absolute); }
	body
	{
		repoPath.normalize();
		m_repos[repoPath].removeSearchPath(path);
	}

	void refresh(bool refresh_existing_packages)
	{
		logDiagnostic("Refreshing local packages (refresh existing: %s)...", refresh_existing_packages);

		// load locally defined packages
		if (!m_disableRepoSearchPaths)
			over_repos: foreach (ref repo; m_repos)
			{
				Path list_path = repo.packagePath;
				Package[] packs;
				Path[] paths;
				try {
					auto local_package_file = list_path ~ LocalPackagesFilename;
					logDiagnostic("Looking for local package map at %s", local_package_file.toNativeString());
					if( !existsFile(local_package_file) ) continue over_repos;
					logDiagnostic("Try to load local package map at %s", local_package_file.toNativeString());
					auto packlist = jsonFromFile(list_path ~ LocalPackagesFilename);
					enforce(packlist.type == Json.Type.array, LocalPackagesFilename~" must contain an array.");
					foreach( pentry; packlist ){
						try {
							auto name = pentry["name"].get!string;
							auto path = Path(pentry["path"].get!string);
							if (name == "*") {
								paths ~= path;
							} else {
								auto ver = Version(pentry["version"].get!string);

								Package pp;
								if (!refresh_existing_packages) {
									foreach (p; repo.localPackages)
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
										auto info = Json.emptyObject;
										info["name"] = name;
										pp = new Package(info, path);
									}
								}

								if (pp.name != name)
									logWarn("Local package at %s has different name than %s (%s)", path.toNativeString(), name, pp.name);
								pp.version_ = ver;

								addPackages(packs, pp);
							}
						} catch( Exception e ){
							logWarn("Error adding local package: %s", e.msg);
						}
					}
				} catch( Exception e ){
					logDiagnostic("Loading of local package list at %s failed: %s", list_path.toNativeString(), e.msg);
				}
				repo.localPackages = packs;
				repo.searchPath = paths;
			}

		auto old_packages = m_packages;

		// rescan a given package folder
		void scanPackageFolder(Path path)
		{
			if( path.existsDirectory() ){
				logDebug("iterating dir %s", path.toNativeString());
				try foreach( pdir; iterateDirectory(path) ){
					logDebug("iterating dir %s entry %s", path.toNativeString(), pdir.name);
					if (!pdir.isDirectory) continue;

					auto pack_path = path ~ (pdir.name ~ "/");

					auto packageFile = Package.findPackageFile(pack_path);

					if (isManagedPath(path) && packageFile.empty) {
						// Search for a single directory within this directory which happen to be a prefix of pdir
						// This is to support new folder structure installed over the ancient one.
						foreach (subdir; iterateDirectory(path ~ (pdir.name ~ "/")))
							if (subdir.isDirectory && pdir.name.startsWith(subdir.name)) {// eg: package vibe-d will be in "vibe-d-x.y.z/vibe-d"
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

		foreach (ref repo; m_repos)
		{
			repo.overrides = null;
			auto ovrfilepath = repo.packagePath ~ LocalOverridesFilename;
			if (existsFile(ovrfilepath)) {
				foreach (entry; jsonFromFile(ovrfilepath)) {
					PackageOverride ovr;
					ovr.package_ = entry["name"].get!string;
					ovr.version_ = Dependency(entry["version"].get!string);
					if (auto pv = "targetVersion" in entry) ovr.targetVersion = Version(pv.get!string);
					if (auto pv = "targetPath" in entry) ovr.targetPath = Path(pv.get!string);
					repo.overrides ~= ovr;
				}
			}
		}
	}

	deprecated alias Hash = ubyte[];
	/// Generates a hash value for a given package.
	/// Some files or folders are ignored during the generation (like .dub and
	/// .svn folders)
	deprecated static ubyte[] hashPackage(Package pack)
	{
		return pack.hash();
	}
}

struct PackageOverride {
	string package_;
	Dependency version_;
	Version targetVersion;
	Path targetPath;

	this(string package_, Dependency version_, Version target_version)
	{
		this.package_ = package_;
		this.version_ = version_;
		this.targetVersion = target_version;
	}

	this(string package_, Dependency version_, Path target_path)
	{
		this.package_ = package_;
		this.version_ = version_;
		this.targetPath = target_path;
	}
}

deprecated enum LocalPackageType {
	user,
	system
}

private enum LocalPackagesFilename = "local-packages.json";
private enum LocalOverridesFilename = "local-overrides.json";


private struct Repository {
	Path packagePath;
	Path[] searchPath;
	Package[] localPackages;
	PackageOverride[] overrides;

	this(Path path)
	{
		this.packagePath = path;
	}

	void writeLocalPackageOverridesFile()
	{
		Json[] newlist;
		foreach (ovr; overrides) {
			auto jovr = Json.emptyObject;
			jovr["name"] = ovr.package_;
			jovr["version"] = ovr.version_.versionSpec;
			if (!ovr.targetPath.empty) jovr["targetPath"] = ovr.targetPath.toNativeString();
			else jovr["targetVersion"] = ovr.targetVersion.toString();
			newlist ~= jovr;
		}
		if (!existsDirectory(packagePath)) mkdirRecurse(packagePath.toNativeString());
		writeJsonFile(packagePath ~ LocalOverridesFilename, Json(newlist));
	}

	void writeLocalPackageList()
	{
		Json[] newlist;
		foreach (p; searchPath) {
			auto entry = Json.emptyObject;
			entry["name"] = "*";
			entry["path"] = p.toNativeString();
			newlist ~= entry;
		}

		foreach (p; localPackages) {
			if (p.parentPackage) continue; // do not store sub packages
			auto entry = Json.emptyObject;
			entry["name"] = p.name;
			entry["version"] = p.version_.toString();
			entry["path"] = p.path.toNativeString();
			newlist ~= entry;
		}

		if( !existsDirectory(packagePath) ) mkdirRecurse(packagePath.toNativeString());
		writeJsonFile(packagePath ~ LocalPackagesFilename, Json(newlist));
	}

	Package addLocalPackage(Path path, string verName)
	{
		path.endsWithSlash = true;
		auto pack = Package.load(path);
		enforce(pack.name.length, "The package has no name, defined in: " ~ path.toString());
		if (verName.length)
			pack.version_ = Version(verName);

		// don't double-add packages
		foreach (p; localPackages) {
			if (p.path == path) {
				enforce(p.version_ == pack.version_, "Adding the same local package twice with differing versions is not allowed.");
				logInfo("Package is already registered: %s (version: %s)", p.name, p.version_);
				return p;
			}
		}

		addPackages(localPackages, pack);

		writeLocalPackageList();

		logInfo("Registered package: %s (version: %s)", pack.name, pack.version_);
		return pack;
	}

	void removeLocalPackage(Path path)
	{
		path.endsWithSlash = true;

		size_t[] to_remove;
		foreach (i, entry; localPackages)
			if (entry.path == path)
				to_remove ~= i;
		enforce(to_remove.length > 0, "No package found at "~path.toNativeString());

		string[Version] removed;
		foreach_reverse( i; to_remove ) {
			removed[localPackages[i].version_] = localPackages[i].name;
			localPackages = localPackages[0 .. i] ~ localPackages[i+1 .. $];
		}

		writeLocalPackageList();

		foreach(ver, name; removed)
			logInfo("Deregistered package: %s (version: %s)", name, ver);
	}

	/// Add another path where packages will be looked up.
	void addSearchPath(Path path)
	{
		searchPath ~= path;
		writeLocalPackageList();
	}

	/// Removes a search path.
	void removeSearchPath(Path path)
	{
		searchPath = searchPath.filter!(p => p != path)().array();
		writeLocalPackageList();
	}

	/** Returns a list of all package overrides.
	*/
	const(PackageOverride)[] getOverrides()
	const {
		return overrides;
	}

	/** Adds a new override for the given package.
	*/
	void addOverride(T)(string package_, Dependency version_spec, T target)
	if (is(T : Version) || is(T : Path))
	{
		overrides ~= PackageOverride(package_, version_spec, target);
		writeLocalPackageOverridesFile();
	}

	/** Removes an existing package override.
	*/
	void removeOverride(string package_, Dependency version_spec)
	{
		foreach (i, ovr; overrides) {
			if (ovr.package_ != package_ || ovr.version_ != version_spec)
				continue;
			overrides = overrides[0 .. i] ~ overrides[i+1 .. $];
			writeLocalPackageOverridesFile();
			return;
		}
		throw new Exception(format("No override exists for %s %s", package_, version_spec));
	}
}

/// Adds the package and scans for subpackages.
private void addPackages(ref Package[] dst_repos, Package pack)
{
	// Add the main package.
	dst_repos ~= pack;

	// Additionally to the internally defined subpackages, whose metadata
	// is loaded with the main dub.json, load all externally defined
	// packages after the package is available with all the data.
	foreach (spr; pack.subPackages) {
		Package sp;

		if (spr.path.length) {
			auto p = Path(spr.path);
			p.normalize();
			enforce(!p.absolute, "Sub package paths must be sub paths of the parent package.");
			auto path = pack.path ~ p;
			if (!existsFile(path)) {
				logError("Package %s declared a sub-package, definition file is missing: %s", pack.name, path.toNativeString());
				continue;
			}
			sp = Package.load(path, Path.init, pack);
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

