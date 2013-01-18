/**
	Management of packages on the local computer.

	Copyright: © 2012 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Matthias Dondorff
*/
module dub.packagemanager;

import dub.dependency;
import dub.installation;
import dub.package_;
import dub.utils;

import std.algorithm : countUntil, filter, sort;
import std.conv;
import std.exception;
import std.file;
import std.zip;
import vibe.core.file;
import vibe.core.log;
import vibe.data.json;
import vibe.inet.path;
import vibe.stream.operations;


enum JournalJsonFilename = "journal.json";
enum LocalPackagesFilename = "local-packages.json";

enum LocalPackageType {
	temporary,
	user,
	system
}


class PackageManager {
	private {
		Path m_systemPackagePath;
		Path m_userPackagePath;
		Path m_projectPackagePath;
		Package[][string] m_systemPackages;
		Package[][string] m_userPackages;
		Package[string] m_projectPackages;
		Package[] m_localTemporaryPackages;
		Package[] m_localUserPackages;
		Package[] m_localSystemPackages;
	}

	this(Path system_package_path, Path user_package_path, Path project_package_path = Path())
	{
		m_systemPackagePath = system_package_path;
		m_userPackagePath = user_package_path;
		m_projectPackagePath = project_package_path;
		refresh();
	}

	@property Path projectPackagePath() const { return m_projectPackagePath; }
	@property void projectPackagePath(Path path) { m_projectPackagePath = path; refresh(); }

	Package getPackage(string name, Version ver)
	{
		foreach( p; getPackageIterator(name) )
			if( p.ver == ver )
				return p;
		return null;
	}

	Package getBestPackage(string name, string version_spec)
	{
		return getBestPackage(name, new Dependency(version_spec));
	}

	Package getBestPackage(string name, in Dependency version_spec)
	{
		Package ret;
		foreach( p; getPackageIterator(name) )
			if( version_spec.matches(p.ver) && (!ret || p.ver > ret.ver) )
				ret = p;
		return ret;
	}

	int delegate(int delegate(ref Package)) getPackageIterator()
	{
		int iterator(int delegate(ref Package) del)
		{
			// first search project local packages
			foreach( p; m_localTemporaryPackages )
				if( auto ret = del(p) ) return ret;
			foreach( p; m_projectPackages )
				if( auto ret = del(p) ) return ret;

			// then local packages
			foreach( p; m_localUserPackages )
				if( auto ret = del(p) ) return ret;

			// then local packages
			foreach( p; m_localSystemPackages )
				if( auto ret = del(p) ) return ret;

			// then user installed packages
			foreach( pl; m_userPackages )
				foreach( v; pl )
					if( auto ret = del(v) )
						return ret;

			// finally system-wide installed packages
			foreach( pl; m_systemPackages )
				foreach( v; pl )
					if( auto ret = del(v) )
						return ret;

			return 0;
		}

		return &iterator;
	}

	int delegate(int delegate(ref Package)) getPackageIterator(string name)
	{
		int iterator(int delegate(ref Package) del)
		{
			// first search project local packages
			foreach( p; m_localTemporaryPackages )
				if( p.name == name )
					if( auto ret = del(p) ) return ret;
			if( auto pp = name in m_projectPackages )
				if( auto ret = del(*pp) ) return ret;

			// then local packages
			foreach( p; m_localUserPackages )
				if( p.name == name )
					if( auto ret = del(p) ) return ret;

			// then local packages
			foreach( p; m_localSystemPackages )
				if( p.name == name )
					if( auto ret = del(p) ) return ret;

			// then user installed packages
			if( auto pp = name in m_userPackages )
				foreach( v; *pp )
					if( auto ret = del(v) )
						return ret;

			// finally system-wide installed packages
			if( auto pp = name in m_systemPackages )
				foreach( v; *pp )
					if( auto ret = del(v) )
						return ret;

			return 0;
		}

		return &iterator;
	}

	Package install(Path zip_file_path, Json package_info, InstallLocation location)
	{
		auto package_name = package_info.name.get!string();
		auto package_version = package_info["version"].get!string();

		Path destination;
		final switch( location ){
			case InstallLocation.Local: destination = Path(package_name); break;
			case InstallLocation.ProjectLocal: enforce(!m_projectPackagePath.empty, "no project path set."); destination = m_projectPackagePath ~ package_name; break;
			case InstallLocation.UserWide: destination = m_userPackagePath ~ (package_name ~ "/" ~ package_version); break;
			case InstallLocation.SystemWide: destination = m_systemPackagePath ~ (package_name ~ "/" ~ package_version); break;
		}

		if( existsFile(destination) )
			throw new Exception(package_name~" needs to be uninstalled prior installation.");

		// open zip file
		ZipArchive archive;
		{
			auto f = openFile(zip_file_path, FileMode.Read);
			scope(exit) f.close();
			archive = new ZipArchive(f.readAll());
		}

		logDebug("Installing from zip.");

		// In a github zip, the actual contents are in a subfolder
		Path zip_prefix;
		foreach(ArchiveMember am; archive.directory)
			if( Path(am.name).head == PathEntry(PackageJsonFilename) ){
				zip_prefix = Path(am.name)[0 .. 1];
				break;
			}

		if( zip_prefix.empty ){
			// not correct zip packages HACK
			Path minPath;
			foreach(ArchiveMember am; archive.directory)
				if( isPathFromZip(am.name) && (minPath == Path() || minPath.startsWith(Path(am.name))) )
					zip_prefix = Path(am.name);
		}

		logDebug("zip root folder: %s", zip_prefix);

		Path getCleanedPath(string fileName) {
			auto path = Path(fileName);
			if(zip_prefix != Path() && !path.startsWith(zip_prefix)) return Path();
			return path[zip_prefix.length..path.length];
		}

		// install
		mkdirRecurse(destination.toNativeString());
		auto journal = new Journal;
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
				dstFile.write(archive.expand(a));
				journal.add(Journal.Entry(Journal.Type.RegularFile, cleanedPath));
			}
		}

		// overwrite package.json (this one includes a version field)
		Json pi = jsonFromFile(destination~PackageJsonFilename);
		pi["version"] = package_info["version"];
		writeJsonFile(destination~PackageJsonFilename, pi);

		// Write journal
		logTrace("Saving installation journal...");
		journal.add(Journal.Entry(Journal.Type.RegularFile, Path(JournalJsonFilename)));
		journal.save(destination ~ JournalJsonFilename);

		if( existsFile(destination~PackageJsonFilename) )
			logInfo("%s has been installed with version %s", package_name, package_version);

		auto pack = new Package(location, destination);
		final switch( location ){
			case InstallLocation.Local: break;
			case InstallLocation.ProjectLocal: m_projectPackages[package_name] = pack; break;
			case InstallLocation.UserWide: m_userPackages[package_name] ~= pack; break;
			case InstallLocation.SystemWide: m_systemPackages[package_name] ~= pack; break;
		}
		return pack;
	}

	void uninstall(in Package pack)
	{
		enforce(!pack.path.empty, "Cannot uninstall package "~pack.name~" without a path.");

		// remove package from package list
		final switch(pack.installLocation){
			case InstallLocation.Local: assert(false, "Cannot uninstall locally installed package.");
			case InstallLocation.ProjectLocal:
				auto pp = pack.name in m_projectPackages;
				assert(pp !is null, "Package "~pack.name~" at "~pack.path.toNativeString()~" is not installed in project.");
				assert(*pp is pack);
				m_projectPackages.remove(pack.name);
				break;
			case InstallLocation.UserWide:
				auto pv = pack.name in m_systemPackages;
				assert(pv !is null, "Package "~pack.name~" at "~pack.path.toNativeString()~" is not installed in user repository.");
				auto idx = countUntil(*pv, pack);
				assert(idx < 0 || (*pv)[idx] is pack);
				if( idx >= 0 ) *pv = (*pv)[0 .. idx] ~ (*pv)[idx+1 .. $];
				break;
			case InstallLocation.SystemWide:
				auto pv = pack.name in m_userPackages;
				assert(pv !is null, "Package "~pack.name~" at "~pack.path.toNativeString()~" is not installed system repository.");
				auto idx = countUntil(*pv, pack);
				assert(idx < 0 || (*pv)[idx] is pack);
				if( idx >= 0 ) *pv = (*pv)[0 .. idx] ~ (*pv)[idx+1 .. $];
				break;
		}

		// delete package files physically
		auto journalFile = pack.path~JournalJsonFilename;
		if( !existsFile(journalFile) )
			throw new Exception("Uninstall failed, no journal found for '"~pack.name~"'. Please uninstall manually.");

		auto packagePath = pack.path;
		auto journal = new Journal(journalFile);
		logDebug("Erasing files");
		foreach( Journal.Entry e; filter!((Journal.Entry a) => a.type == Journal.Type.RegularFile)(journal.entries)) {
			logTrace("Deleting file '%s'", e.relFilename);
			auto absFile = pack.path~e.relFilename;
			if(!existsFile(absFile)) {
				logWarn("Previously installed file not found for uninstalling: '%s'", absFile);
				continue;
			}

			removeFile(absFile);
		}

		logDebug("Erasing directories");
		Path[] allPaths;
		foreach(Journal.Entry e; filter!((Journal.Entry a) => a.type == Journal.Type.Directory)(journal.entries))
			allPaths ~= pack.path~e.relFilename;
		sort!("a.length>b.length")(allPaths); // sort to erase deepest paths first
		foreach(Path p; allPaths) {
			logTrace("Deleting folder '%s'", p);
			if( !existsFile(p) || !isDir(p.toNativeString()) || !isEmptyDir(p) ) {
				logError("Alien files found, directory is not empty or is not a directory: '%s'", p);
				continue;
			}
			rmdir(p.toNativeString());
		}

		if(!isEmptyDir(pack.path))
			throw new Exception("Alien files found in '"~pack.path.toNativeString()~"', needs to be deleted manually.");

		rmdir(pack.path.toNativeString());
		logInfo("Uninstalled package: '"~pack.name~"'");
	}

	void addLocalPackage(in Path path, in Version ver, LocalPackageType type)
	{
		Package[]* packs = getLocalPackageList(type);
		auto info = jsonFromFile(path ~ PackageJsonFilename, false);
		string name;
		if( "name" !in info ) info["name"] = path.head.toString();
		info["version"] = ver.toString();

		// don't double-add packages
		foreach( p; *packs ){
			if( p.path == path ){
				enforce(p.ver == ver, "Adding local twice with different versions is not allowed.");
				return;
			}
		}

		*packs ~= new Package(info, InstallLocation.Local, path);

		writeLocalPackageList(type);
	}

	void removeLocalPackage(in Path path, LocalPackageType type)
	{
		Package[]* packs = getLocalPackageList(type);
		size_t[] to_remove;
		foreach( i, entry; *packs )
			if( entry.path == path )
				to_remove ~= i;
		enforce(to_remove.length > 0, "No "~type.to!string()~" package found at "~path.toNativeString());

		foreach_reverse( i; to_remove )
			*packs = (*packs)[0 .. i] ~ (*packs)[i+1 .. $];

		writeLocalPackageList(type);
	}

	void refresh()
	{
		// rescan the system and user package folder
		void scanPackageFolder(Path path, ref Package[][string] packs, InstallLocation location)
		{
			packs = null;
			if( path.existsDirectory() ){
				logDebug("iterating dir %s", path.toNativeString());
				try foreach( pdir; iterateDirectory(path) ){
					logDebug("iterating dir %s entry %s", path.toNativeString(), pdir.name);
					if( !pdir.isDirectory ) continue;
					Package[] vers;
					auto pack_path = path ~ pdir.name;
					foreach( vdir; iterateDirectory(pack_path) ){
						if( !vdir.isDirectory ) continue;
						auto ver_path = pack_path ~ vdir.name;
						if( !existsFile(ver_path ~ PackageJsonFilename) ) continue;
						try {
							auto p = new Package(location, ver_path);
							vers ~= p;
						} catch( Exception e ){
							logError("Failed to load package in %s: %s", ver_path, e.msg);
						}
					}
					packs[pdir.name] = vers;
				}
				catch(Exception e) logDebug("Failed to enumerate %s packages: %s", to!string(location), e.toString());
			}
		}
		scanPackageFolder(m_systemPackagePath, m_systemPackages, InstallLocation.SystemWide);
		scanPackageFolder(m_userPackagePath, m_userPackages, InstallLocation.UserWide);


		// rescan the project package folder
		m_projectPackages = null;
		if( !m_projectPackagePath.empty && m_projectPackagePath.existsDirectory() ){
			logDebug("iterating dir %s", m_projectPackagePath.toNativeString());
			try foreach( pdir; m_projectPackagePath.iterateDirectory() ){
				if( !pdir.isDirectory ) continue;
				auto pack_path = m_projectPackagePath ~ pdir.name;
				if( !existsFile(pack_path ~ PackageJsonFilename) ) continue;

				try {
					auto p = new Package(InstallLocation.ProjectLocal, pack_path);
					m_projectPackages[pdir.name] = p;
				} catch( Exception e ){
					logError("Failed to load package in %s: %s", pack_path, e.msg);
				}
			}
			catch(Exception e) logDebug("Failed to enumerate project packages: %s", e.toString());
		}

		// load locally defined packages
		void scanLocalPackages(Path list_path, ref Package[] packs){
			try {
				logDebug("Looking for local package map at %s", list_path.toNativeString());
				if( !existsFile(list_path ~ LocalPackagesFilename) ) return;
				logDebug("Try to load local package map at %s", list_path.toNativeString());
				auto packlist = jsonFromFile(list_path ~ LocalPackagesFilename);
				enforce(packlist.type == Json.Type.Array, LocalPackagesFilename~" must contain an array.");
				foreach( pentry; packlist ){
					try {
						auto name = pentry.name.get!string();
						auto ver = pentry["version"].get!string();
						auto path = Path(pentry.path.get!string());
						auto info = Json.EmptyObject;
						if( existsFile(path ~ PackageJsonFilename) ) info = jsonFromFile(path ~ PackageJsonFilename);
						if( "name" in info && info.name.get!string() != name )
							logWarn("Local package at %s has different name than %s (%s)", path.toNativeString(), name, info.name.get!string());
						info.name = name;
						info["version"] = ver;
						auto pp = new Package(info, InstallLocation.Local, path);
						packs ~= pp;
					} catch( Exception e ){
						logWarn("Error adding local package: %s", e.msg);
					}
				}
			} catch( Exception e ){
				logDebug("Loading of local package list at %s failed: %s", list_path.toNativeString(), e.msg);
			}
		}
		scanLocalPackages(m_systemPackagePath, m_localSystemPackages);
		scanLocalPackages(m_userPackagePath, m_localUserPackages);
	}

	private Package[]* getLocalPackageList(LocalPackageType type)
	{
		final switch(type){
			case LocalPackageType.user: return &m_localUserPackages;
			case LocalPackageType.system: return &m_localSystemPackages;
			case LocalPackageType.temporary: return &m_localTemporaryPackages;
		}
	}

	private void writeLocalPackageList(LocalPackageType type)
	{
		Package[]* packs = getLocalPackageList(type);
		Json[] newlist;
		foreach( p; *packs ){
			auto entry = Json.EmptyObject;
			entry["name"] = p.name;
			entry["version"] = p.ver.toString();
			entry["path"] = p.path.toNativeString();
			newlist ~= entry;
		}

		Path path;
		final switch(type){
			case LocalPackageType.user: path = m_userPackagePath;
			case LocalPackageType.system: path = m_systemPackagePath;
			case LocalPackageType.temporary: return;
		}
		if( !existsDirectory(path) ) mkdirRecurse(path.toNativeString());
		writeJsonFile(path ~ LocalPackagesFilename, Json(newlist));
	}
}