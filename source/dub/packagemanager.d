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

import std.algorithm : countUntil, filter, sort, canFind, remove;
import std.array;
import std.conv;
import std.digest.sha;
import std.encoding : sanitize;
import std.exception;
import std.file;
import std.string;
import std.zip;


/// The PackageManager can retrieve present packages and get / remove
/// packages.
class PackageManager {
	private {
		Repository[LocalPackageType] m_repositories;
		Path[] m_searchPath;
		Package[] m_packages;
		Package[] m_temporaryPackages;
		bool m_disableDefaultSearchPaths = false;
	}

	this(Path user_path, Path system_path, bool refresh_packages = true)
	{
		m_repositories[LocalPackageType.user] = Repository(user_path);
		m_repositories[LocalPackageType.system] = Repository(system_path);
		if (refresh_packages) refresh(true);
	}

	/** Gets/sets the list of paths to search for local packages.
	*/
	@property void searchPath(Path[] paths)
	{
		if (paths == m_searchPath) return;
		m_searchPath = paths.dup;
		refresh(false);
	}
	/// ditto
	@property const(Path)[] searchPath() const { return m_searchPath; }

	/** Disables searching DUB's predefined search paths.
	*/
	@property void disableDefaultSearchPaths(bool val)
	{
		if (val == m_disableDefaultSearchPaths) return;
		m_disableDefaultSearchPaths = val;
		refresh(true);
	}

	/** Returns the effective list of search paths, including default ones.
	*/
	@property const(Path)[] completeSearchPath()
	const {
		auto ret = appender!(Path[])();
		ret.put(m_searchPath);
		if (!m_disableDefaultSearchPaths) {
			ret.put(m_repositories[LocalPackageType.user].searchPath);
			ret.put(m_repositories[LocalPackageType.user].packagePath);
			ret.put(m_repositories[LocalPackageType.system].searchPath);
			ret.put(m_repositories[LocalPackageType.system].packagePath);
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
		if (enable_overrides) {
			foreach (tp; [LocalPackageType.user, LocalPackageType.system])
				foreach (ovr; m_repositories[tp].overrides)
					if (ovr.package_ == name && ovr.version_.matches(ver)) {
						Package pack;
						if (!ovr.targetPath.empty) pack = getPackage(name, ovr.targetPath);
						else pack = getPackage(name, ovr.targetVersion, false);
						if (pack) return pack;

						logWarn("Package override %s %s -> %s %s doesn't reference an existing package.",
							ovr.package_, ovr.version_, ovr.targetVersion, ovr.targetPath);
					}
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
		enforce(silent_fail, "Sub package "~base_package.name~":"~sub_name~" doesn't exist.");
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

	/** Determines if a specifc path is within a DUB managed package folder.

		By default, managed folders are "~/.dub/packages" and
		"/var/lib/dub/packages".
	*/
	bool isManagedPath(Path path)
	const {
		foreach (rep; m_repositories) {
			auto rpath = rep.packagePath;
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
			foreach (tp; LocalPackageType.min .. LocalPackageType.max+1)
				foreach (p; m_repositories[cast(LocalPackageType)tp].localPackages)
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
	const(PackageOverride)[] getOverrides(LocalPackageType scope_)
	const {
		return m_repositories[scope_].overrides;
	}

	/** Adds a new override for the given package.
	*/
	void addOverride(LocalPackageType scope_, string package_, Dependency version_spec, Version target)
	{
		m_repositories[scope_].overrides ~= PackageOverride(package_, version_spec, target);
		writeLocalPackageOverridesFile(scope_);
	}
	/// ditto
	void addOverride(LocalPackageType scope_, string package_, Dependency version_spec, Path target)
	{
		m_repositories[scope_].overrides ~= PackageOverride(package_, version_spec, target);
		writeLocalPackageOverridesFile(scope_);
	}

	/** Removes an existing package override.
	*/
	void removeOverride(LocalPackageType scope_, string package_, Dependency version_spec)
	{
		Repository* rep = &m_repositories[scope_];
		foreach (i, ovr; rep.overrides) {
			if (ovr.package_ != package_ || ovr.version_ != version_spec)
				continue;
			rep.overrides = rep.overrides[0 .. i] ~ rep.overrides[i+1 .. $];
			writeLocalPackageOverridesFile(scope_);
			return;
		}
		throw new Exception(format("No override exists for %s %s", package_, version_spec));
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
				auto dstFile = openFile(dst_path, FileMode.createTrunc);
				scope(exit) dstFile.close();
				dstFile.put(archive.expand(a));
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

	/// Removes the given the package.
	void remove(in Package pack, bool force_remove)
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
		logInfo("Removed package: '"~pack.name~"'");
	}

	Package addLocalPackage(Path path, string verName, LocalPackageType type)
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

		writeLocalPackageList(type);

		logInfo("Registered package: %s (version: %s)", pack.name, pack.version_);
		return pack;
	}

	void removeLocalPackage(Path path, LocalPackageType type)
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

		writeLocalPackageList(type);

		foreach(ver, name; removed)
			logInfo("Deregistered package: %s (version: %s)", name, ver);
	}

	/// For the given type add another path where packages will be looked up.
	void addSearchPath(Path path, LocalPackageType type)
	{
		m_repositories[type].searchPath ~= path;
		writeLocalPackageList(type);
	}

	/// Removes a search path from the given type.
	void removeSearchPath(Path path, LocalPackageType type)
	{
		m_repositories[type].searchPath = m_repositories[type].searchPath.filter!(p => p != path)().array();
		writeLocalPackageList(type);
	}

	void refresh(bool refresh_existing_packages)
	{
		logDiagnostic("Refreshing local packages (refresh existing: %s)...", refresh_existing_packages);

		// load locally defined packages
		void scanLocalPackages(LocalPackageType type)
		{
			Path list_path = m_repositories[type].packagePath;
			Package[] packs;
			Path[] paths;
			if (!m_disableDefaultSearchPaths) try {
				auto local_package_file = list_path ~ LocalPackagesFilename;
				logDiagnostic("Looking for local package map at %s", local_package_file.toNativeString());
				if( !existsFile(local_package_file) ) return;
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
								foreach (p; m_repositories[type].localPackages)
									if (p.path == path) {
										pp = p;
										break;
									}
							}

							if (!pp) {
								auto infoFile = Package.findPackageFile(path);
								if (!infoFile.empty) pp = Package.load(path, infoFile);
								else {
									logWarn("Locally registered package %s %s was not found. Please run \"dub remove-local %s\".",
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
			m_repositories[type].localPackages = packs;
			m_repositories[type].searchPath = paths;
		}
		scanLocalPackages(LocalPackageType.system);
		scanLocalPackages(LocalPackageType.user);

		auto old_packages = m_packages;

		// rescan the system and user package folder
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

		void loadOverrides(LocalPackageType type)
		{
			m_repositories[type].overrides = null;
			auto ovrfilepath = m_repositories[type].packagePath ~ LocalOverridesFilename;
			if (existsFile(ovrfilepath)) {
				foreach (entry; jsonFromFile(ovrfilepath)) {
					PackageOverride ovr;
					ovr.package_ = entry["name"].get!string;
					ovr.version_ = Dependency(entry["version"].get!string);
					if (auto pv = "targetVersion" in entry) ovr.targetVersion = Version(pv.get!string);
					if (auto pv = "targetPath" in entry) ovr.targetPath = Path(pv.get!string);
					m_repositories[type].overrides ~= ovr;
				}
			}
		}
		loadOverrides(LocalPackageType.user);
		loadOverrides(LocalPackageType.system);
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
			if(file.isDir && ignored_directories.canFind(Path(file.name).head.toString()))
				continue;
			else if(ignored_files.canFind(Path(file.name).head.toString()))
				continue;

			sha1.put(cast(ubyte[])Path(file.name).head.toString());
			if(file.isDir) {
				logDebug("Hashed directory name %s", Path(file.name).head);
			}
			else {
				sha1.put(openFile(Path(file.name)).readAll());
				logDebug("Hashed file contents from %s", Path(file.name).head);
			}
		}
		auto hash = sha1.finish();
		logDebug("Project hash: %s", hash);
		return hash[].dup;
	}

	private void writeLocalPackageList(LocalPackageType type)
	{
		Json[] newlist;
		foreach (p; m_repositories[type].searchPath) {
			auto entry = Json.emptyObject;
			entry["name"] = "*";
			entry["path"] = p.toNativeString();
			newlist ~= entry;
		}

		foreach (p; m_repositories[type].localPackages) {
			if (p.parentPackage) continue; // do not store sub packages
			auto entry = Json.emptyObject;
			entry["name"] = p.name;
			entry["version"] = p.version_.toString();
			entry["path"] = p.path.toNativeString();
			newlist ~= entry;
		}

		Path path = m_repositories[type].packagePath;
		if( !existsDirectory(path) ) mkdirRecurse(path.toNativeString());
		writeJsonFile(path ~ LocalPackagesFilename, Json(newlist));
	}

	private void writeLocalPackageOverridesFile(LocalPackageType type)
	{
		Json[] newlist;
		foreach (ovr; m_repositories[type].overrides) {
			auto jovr = Json.emptyObject;
			jovr["name"] = ovr.package_;
			jovr["version"] = ovr.version_.versionSpec;
			if (!ovr.targetPath.empty) jovr["targetPath"] = ovr.targetPath.toNativeString();
			else jovr["targetVersion"] = ovr.targetVersion.toString();
			newlist ~= jovr;
		}
		auto path = m_repositories[type].packagePath;
		if (!existsDirectory(path)) mkdirRecurse(path.toNativeString());
		writeJsonFile(path ~ LocalOverridesFilename, Json(newlist));
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

enum LocalPackageType {
	user,
	system
}

private enum LocalPackagesFilename = "local-packages.json";
private enum LocalOverridesFilename = "local-overrides.json";


private struct Repository {
	Path path;
	Path packagePath;
	Path[] searchPath;
	Package[] localPackages;
	PackageOverride[] overrides;

	this(Path path)
	{
		this.path = path;
		this.packagePath = path ~"packages/";
	}
}
