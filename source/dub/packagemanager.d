/**
	Management of packages on the local computer.

	Copyright: © 2012-2013 rejectedsoftware e.K.
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

import std.algorithm : countUntil, filter, sort, canFind;
import std.array;
import std.conv;
import std.digest.sha;
import std.encoding : sanitize;
import std.exception;
import std.file;
import std.string;
import std.zip;


enum JournalJsonFilename = "journal.json";
enum LocalPackagesFilename = "local-packages.json";


private struct Repository {
	Path path;
	Path packagePath;
	Path[] searchPath;
	Package[] localPackages;

	this(Path path)
	{
		this.path = path;
		this.packagePath = path ~"packages/";
	}
}

enum LocalPackageType {
	user,
	system
}

/// The PackageManager can retrieve present packages and get / remove
/// packages.
class PackageManager {
	private {
		Repository[LocalPackageType] m_repositories;
		Path[] m_searchPath;
		Package[] m_packages;
		Package[] m_temporaryPackages;
	}

	this(Path user_path, Path system_path)
	{
		m_repositories[LocalPackageType.user] = Repository(user_path);
		m_repositories[LocalPackageType.system] = Repository(system_path);
		refresh(true);
	}

	@property void searchPath(Path[] paths) { m_searchPath = paths.dup; refresh(false); }
	@property const(Path)[] searchPath() const { return m_searchPath; }

	@property const(Path)[] completeSearchPath()
	const {
		auto ret = appender!(Path[])();
		ret.put(m_searchPath);
		ret.put(m_repositories[LocalPackageType.user].searchPath);
		ret.put(m_repositories[LocalPackageType.user].packagePath);
		ret.put(m_repositories[LocalPackageType.system].searchPath);
		ret.put(m_repositories[LocalPackageType.system].packagePath);
		return ret.data;
	}

	Package getPackage(string name, Version ver)
	{
		foreach( p; getPackageIterator(name) )
			if( p.ver == ver )
				return p;
		return null;
	}

	Package getPackage(string name, string ver, Path in_path)
	{
		return getPackage(name, Version(ver), in_path);
	}
	Package getPackage(string name, Version ver, Path in_path)
	{
		foreach( p; getPackageIterator(name) )
			if (p.ver == ver && p.path.startsWith(in_path))
				return p;
		return null;
	}

	Package getPackage(string name, string ver)
	{
		foreach (ep; getPackageIterator(name)) {
			if (ep.vers == ver)
				return ep;
		}
		return null;
	}

	Package getFirstPackage(string name)
	{
		foreach (ep; getPackageIterator(name))
			return ep;
		return null;
	}

	Package getPackage(Path path)
	{
		foreach (p; getPackageIterator())
			if (!p.parentPackage && p.path == path)
				return p;
		auto pack = new Package(path);
		addPackages(m_temporaryPackages, pack);
		return pack;
	}

	Package getBestPackage(string name, string version_spec)
	{
		return getBestPackage(name, Dependency(version_spec));
	}

	Package getBestPackage(string name, Dependency version_spec)
	{
		Package ret;
		foreach( p; getPackageIterator(name) )
			if( version_spec.matches(p.ver) && (!ret || p.ver > ret.ver) )
				ret = p;
		return ret;
	}

	/** Determines if a package is managed by DUB.

		Managed packages can be upgraded and removed.
	*/
	bool isManagedPackage(Package pack)
	const {
		auto ppath = pack.basePackage.path;
		foreach (rep; m_repositories) {
			auto rpath = rep.packagePath;
			if (ppath.startsWith(rpath))
				return true;
		}
		return false;
	}

	int delegate(int delegate(ref Package)) getPackageIterator()
	{
		int iterator(int delegate(ref Package) del)
		{
			int handlePackage(Package p) {
				if (auto ret = del(p)) return ret;
				foreach (sp; p.subPackages)
					if (auto ret = del(sp))
						return ret;
				return 0;
			}

			foreach (tp; m_temporaryPackages)
				if (auto ret = handlePackage(tp)) return ret;

			// first search local packages
			foreach (tp; LocalPackageType.min .. LocalPackageType.max+1)
				foreach (p; m_repositories[cast(LocalPackageType)tp].localPackages)
					if (auto ret = handlePackage(p)) return ret;

			// and then all packages gathered from the search path
			foreach( p; m_packages )
				if( auto ret = handlePackage(p) )
					return ret;
			return 0;
		}

		return &iterator;
	}

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

	/// Extracts the package supplied as a path to it's zip file to the
	/// destination and sets a version field in the package description.
	Package storeFetchedPackage(Path zip_file_path, Json package_info, Path destination)
	{
		auto package_name = package_info.name.get!string();
		auto package_version = package_info["version"].get!string();
		auto clean_package_version = package_version[package_version.startsWith("~") ? 1 : 0 .. $];

		logDiagnostic("Placing package '%s' version '%s' to location '%s' from file '%s'", 
			package_name, package_version, destination.toNativeString(), zip_file_path.toNativeString());

		if( existsFile(destination) ){
			throw new Exception(format("%s (%s) needs to be removed from '%s' prior placement.", package_name, package_version, destination));
		}

		// open zip file
		ZipArchive archive;
		{
			logDebug("Opening file %s", zip_file_path);
			auto f = openFile(zip_file_path, FileMode.Read);
			scope(exit) f.close();
			archive = new ZipArchive(f.readAll());
		}

		logDebug("Extracting from zip.");

		// In a github zip, the actual contents are in a subfolder
		Path zip_prefix;
		outer: foreach(ArchiveMember am; archive.directory) {
			auto path = Path(am.name);
			foreach (fil; packageInfoFilenames)
				if (path.length == 2 && path.head.toString == fil) {
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
		auto journal = new Journal;
		logDiagnostic("Copying all files...");
		int countFiles = 0;
		foreach(ArchiveMember a; archive.directory) {
			auto cleanedPath = getCleanedPath(a.name);
			if(cleanedPath.empty) continue;
			auto dst_path = destination~cleanedPath;

			logDebug("Creating %s", cleanedPath);
			if( dst_path.endsWithSlash ){
				if( !existsDirectory(dst_path) )
					mkdirRecurse(dst_path.toNativeString());
				journal.add(Journal.Entry(Journal.Type.Directory, cleanedPath));
			} else {
				if( !existsDirectory(dst_path.parentPath) )
					mkdirRecurse(dst_path.parentPath.toNativeString());
				auto dstFile = openFile(dst_path, FileMode.CreateTrunc);
				scope(exit) dstFile.close();
				dstFile.put(archive.expand(a));
				journal.add(Journal.Entry(Journal.Type.RegularFile, cleanedPath));
				++countFiles;
			}
		}
		logDiagnostic("%s file(s) copied.", to!string(countFiles));

		// overwrite package.json (this one includes a version field)
		auto pack = new Package(destination);
		pack.info.version_ = package_info["version"].get!string;

		if (pack.packageInfoFile.head != defaultPackageFilename()) {
			// Storeinfo saved a default file, this could be different to the file from the zip.
			removeFile(pack.packageInfoFile);
			journal.remove(Journal.Entry(Journal.Type.RegularFile, Path(pack.packageInfoFile.head)));
			journal.add(Journal.Entry(Journal.Type.RegularFile, Path(defaultPackageFilename())));
		}
		pack.storeInfo();

		// Write journal
		logDebug("Saving retrieval action journal...");
		journal.add(Journal.Entry(Journal.Type.RegularFile, Path(JournalJsonFilename)));
		journal.save(destination ~ JournalJsonFilename);

		addPackages(m_packages, pack);

		return pack;
	}

	/// Removes the given the package.
	void remove(in Package pack)
	{
		logDebug("Remove %s, version %s, path '%s'", pack.name, pack.vers, pack.path);
		enforce(!pack.path.empty, "Cannot remove package "~pack.name~" without a path.");

		// remove package from repositories' list
		bool found = false;
		bool removeFrom(Package[] packs, in Package pack) {
			auto packPos = countUntil!("a.path == b.path")(packs, pack);
			if(packPos != -1) {
				packs = std.algorithm.remove(packs, packPos);
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

		// delete package files physically
		logDebug("Looking up journal");
		auto journalFile = pack.path~JournalJsonFilename;
		if (!existsFile(journalFile))
			throw new Exception("Removal failed, no retrieval journal found for '"~pack.name~"'. Please remove the folder '%s' manually.", pack.path.toNativeString());

		auto packagePath = pack.path;
		auto journal = new Journal(journalFile);
		logDebug("Erasing files");
		foreach( Journal.Entry e; filter!((Journal.Entry a) => a.type == Journal.Type.RegularFile)(journal.entries)) {
			logDebug("Deleting file '%s'", e.relFilename);
			auto absFile = pack.path~e.relFilename;
			if(!existsFile(absFile)) {
				logWarn("Previously retrieved file not found for removal: '%s'", absFile);
				continue;
			}

			removeFile(absFile);
		}

		logDiagnostic("Erasing directories");
		Path[] allPaths;
		foreach(Journal.Entry e; filter!((Journal.Entry a) => a.type == Journal.Type.Directory)(journal.entries))
			allPaths ~= pack.path~e.relFilename;
		sort!("a.length>b.length")(allPaths); // sort to erase deepest paths first
		foreach(Path p; allPaths) {
			logDebug("Deleting folder '%s'", p);
			if( !existsFile(p) || !isDir(p.toNativeString()) || !isEmptyDir(p) ) {
				logError("Alien files found, directory is not empty or is not a directory: '%s'", p);
				continue;
			}
			rmdir(p.toNativeString());
		}

		// Erase .dub folder, this is completely erased.
		auto dubDir = (pack.path ~ ".dub/").toNativeString();
		enforce(!existsFile(dubDir) || isDir(dubDir), ".dub should be a directory, but is a file.");
		if(existsFile(dubDir) && isDir(dubDir)) {
			logDebug(".dub directory found, removing directory including content.");
			rmdirRecurse(dubDir);
		}

		logDebug("About to delete root folder for package '%s'.", pack.path);
		if(!isEmptyDir(pack.path))
			throw new Exception("Alien files found in '"~pack.path.toNativeString()~"', needs to be deleted manually.");

		rmdir(pack.path.toNativeString());
		logInfo("Removed package: '"~pack.name~"'");
	}

	Package addLocalPackage(in Path path, string verName, LocalPackageType type)
	{
		auto pack = new Package(path);
		enforce(pack.name.length, "The package has no name, defined in: " ~ path.toString());
		if (verName.length)
			pack.ver = Version(verName);

		// don't double-add packages
		Package[]* packs = &m_repositories[type].localPackages;
		foreach (p; *packs) {
			if (p.path == path) {
				enforce(p.ver == pack.ver, "Adding the same local package twice with differing versions is not allowed.");
				logInfo("Package is already registered: %s (version: %s)", p.name, p.ver);
				return p;
			}
		}

		addPackages(*packs, pack);

		writeLocalPackageList(type);

		logInfo("Registered package: %s (version: %s)", pack.name, pack.ver);
		return pack;
	}

	void removeLocalPackage(in Path path, LocalPackageType type)
	{
		Package[]* packs = &m_repositories[type].localPackages;
		size_t[] to_remove;
		foreach( i, entry; *packs )
			if( entry.path == path )
				to_remove ~= i;
		enforce(to_remove.length > 0, "No "~type.to!string()~" package found at "~path.toNativeString());

		string[Version] removed;
		foreach_reverse( i; to_remove ) {
			removed[(*packs)[i].ver] = (*packs)[i].name;
			*packs = (*packs)[0 .. i] ~ (*packs)[i+1 .. $];
		}

		writeLocalPackageList(type);

		foreach(ver, name; removed)
			logInfo("Unregistered package: %s (version: %s)", name, ver);
	}

	Package getTemporaryPackage(Path path, Version ver)
	{
		foreach (p; m_temporaryPackages)
			if (p.path == path) {
				enforce(p.ver == ver, format("Package in %s is refrenced with two conflicting versions: %s vs %s", path.toNativeString(), p.ver, ver));
				return p;
			}
		
		auto pack = new Package(path);
		enforce(pack.name.length, "The package has no name, defined in: " ~ path.toString());
		pack.ver = ver;
		addPackages(m_temporaryPackages, pack);
		return pack;
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
		// load locally defined packages
		void scanLocalPackages(LocalPackageType type)
		{
			Path list_path = m_repositories[type].packagePath;
			Package[] packs;
			Path[] paths;
			try {
				auto local_package_file = list_path ~ LocalPackagesFilename;
				logDiagnostic("Looking for local package map at %s", local_package_file.toNativeString());
				if( !existsFile(local_package_file) ) return;
				logDiagnostic("Try to load local package map at %s", local_package_file.toNativeString());
				auto packlist = jsonFromFile(list_path ~ LocalPackagesFilename);
				enforce(packlist.type == Json.Type.array, LocalPackagesFilename~" must contain an array.");
				foreach( pentry; packlist ){
					try {
						auto name = pentry.name.get!string();
						auto path = Path(pentry.path.get!string());
						if (name == "*") {
							paths ~= path;
						} else {
							auto ver = Version(pentry["version"].get!string());

							Package pp;
							if (!refresh_existing_packages) {
								foreach (p; m_repositories[type].localPackages)
									if (p.path == path) {
										pp = p;
										break;
									}
							}

							if (!pp) {
								if (Package.isPackageAt(path)) pp = new Package(path);
								else {
									auto info = Json.emptyObject;
									info.name = name;
								}
							}

							if (pp.name != name)
								logWarn("Local package at %s has different name than %s (%s)", path.toNativeString(), name, pp.name);
							pp.ver = ver;

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
					if( !pdir.isDirectory ) continue;
					auto pack_path = path ~ pdir.name;
					if (!Package.isPackageAt(pack_path)) continue;
					Package p;
					try {
						if (!refresh_existing_packages)
							foreach (pp; old_packages)
								if (pp.path == pack_path) {
									p = pp;
									break;
								}
						if (!p) p = new Package(pack_path);
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
	}

	alias ubyte[] Hash;
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
		return hash[0..$];
	}

	private void writeLocalPackageList(LocalPackageType type)
	{
		Json[] newlist;
		foreach (p; m_repositories[type].searchPath) {
			auto entry = Json.emptyObject;
			entry.name = "*";
			entry.path = p.toNativeString();
			newlist ~= entry;
		}

		foreach (p; m_repositories[type].localPackages) {
			auto entry = Json.emptyObject;
			entry["name"] = p.name;
			entry["version"] = p.ver.toString();
			entry["path"] = p.path.toNativeString();
			newlist ~= entry;
		}

		Path path = m_repositories[type].packagePath;
		if( !existsDirectory(path) ) mkdirRecurse(path.toNativeString());
		writeJsonFile(path ~ LocalPackagesFilename, Json(newlist));
	}

	/// Adds the package and scans for subpackages.
	private void addPackages(ref Package[] dst_repos, Package pack) const {
		// Add the main package.
		dst_repos ~= pack;

		// Additionally to the internally defined subpackages, whose metadata
		// is loaded with the main package.json, load all externally defined
		// packages after the package is available with all the data.
		foreach ( sub_name, sub_path; pack.exportedPackages ) {
			auto path = pack.path ~ sub_path;
			if ( !existsFile(path) ) {
				logError("Package %s defined sub-package %s, definition file is missing: ", sub_name, path.toNativeString());
				continue;
			}
			// Add the subpackage.
			try {
				auto sub_pack = new Package(path, pack);
				// Checking the raw name here, instead of the "parent:sub" style.
				enforce(sub_pack.info.name == sub_name, "Name of package '" ~ sub_name ~ "' differs in definition in '" ~ path.toNativeString() ~ "'.");
				dst_repos ~= sub_pack;
			} catch( Exception e ){
				logError("Package '%s': Failed to load sub-package '%s' in %s, error: %s", pack.name, sub_name, path.toNativeString(), e.msg);
				logDiagnostic("Full error: %s", e.toString().sanitize());
			}
		}
	}
}


/**
	Retrieval journal for later removal, keeping track of placed files
	files.
	Example Json:
	{
		"version": 1,
		"files": {
			"file1": "typeoffile1",
			...
		}
	}
*/
private class Journal {
	private enum Version = 1;
	
	enum Type {
		RegularFile,
		Directory,
		Alien
	}
	
	struct Entry {
		this( Type t, Path f ) { type = t; relFilename = f; }
		Type type;
		Path relFilename;
	}
	
	@property const(Entry[]) entries() const { return m_entries; }
	
	this() {}
	
	/// Initializes a Journal from a json file.
	this(Path journalFile) {
		auto jsonJournal = jsonFromFile(journalFile);
		enforce(cast(int)jsonJournal["Version"] == Version, "Mismatched version: "~to!string(cast(int)jsonJournal["Version"]) ~ "vs. " ~to!string(Version));
		foreach(string file, type; jsonJournal["Files"])
			m_entries ~= Entry(to!Type(cast(string)type), Path(file));
	}

	void add(Entry e) {
		foreach(Entry ent; entries) {
			if( e.relFilename == ent.relFilename ) {
				enforce(e.type == ent.type, "Duplicate('"~to!string(e.relFilename)~"'), different types: "~to!string(e.type)~" vs. "~to!string(ent.type));
				return;
			}
		}
		m_entries ~= e;
	}

	void remove(Entry e) {
		foreach(i, Entry ent; entries) {
			if( e.relFilename == ent.relFilename ) {
				m_entries = std.algorithm.remove(m_entries, i);
				return;
			}
		}
		enforce(false, "Cannot remove entry, not available: " ~ e.relFilename.toNativeString());
	}
	
	/// Save the current state to the path.
	void save(Path path) {
		Json jsonJournal = serialize();
		auto fileJournal = openFile(path, FileMode.CreateTrunc);
		scope(exit) fileJournal.close();
		fileJournal.writePrettyJsonString(jsonJournal);
	}
	
	private Json serialize() const {
		Json[string] files;
		foreach(Entry e; m_entries)
			files[to!string(e.relFilename)] = to!string(e.type);
		Json[string] json;
		json["Version"] = Version;
		json["Files"] = files;
		return Json(json);
	}
	
	private {
		Entry[] m_entries;
	}
}
