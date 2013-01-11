/**
	A package manager.

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff, Sönke Ludwig
*/
module dub.dub;

import dub.dependency;
import dub.installation;
import dub.utils;
import dub.registry;
import dub.package_;
import dub.packagesupplier;

import vibe.core.file;
import vibe.core.log;
import vibe.data.json;
import vibe.inet.url;

// todo: cleanup imports.
import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.exception;
import std.file;
import std.path;
import std.string;
import std.typecons;
import std.zip;

/// Actions to be performed by the dub
private struct Action {
	enum ActionId {
		InstallUpdate,
		Uninstall,
		Conflict,
		Failure
	}

	this( ActionId id, string pkg, const Dependency d, Dependency[string] issue) {
		action = id; packageId = pkg; vers = new Dependency(d); issuer = issue;
	}
	const ActionId action;
	const string packageId;
	const Dependency vers;
	const Dependency[string] issuer;

	string toString() const {
		return to!string(action) ~ ": " ~ packageId ~ ", " ~ to!string(vers);
	}
}

/// During check to build task list, which can then be executed.
private class Application {
	private {
		Path m_root;
		Json m_json;
		Package m_main;
		Package[string] m_packages;
	}

	this(Path rootFolder) {
		m_root = rootFolder;
		m_json = Json.EmptyObject;
		reinit();
	}

	/// Gathers information
	string info() const {
		if(!m_main)
			return "-Unregocgnized application in '"~to!string(m_root)~"' (properly no package.json in this directory)";
		string s = "-Application identifier: " ~ m_main.name;
		s ~= "\n" ~ m_main.info();
		s ~= "\n-Installed modules:";
		foreach(string k, p; m_packages)
			s ~= "\n" ~ p.info();
		return s;
	}

	/// Gets all installed packages as a "packageId" = "version" associative array
	string[string] installedPackages() const {
		string[string] pkgs;
		foreach(k, p; m_packages)
			pkgs[k] = p.vers;
		return pkgs;
	}

	/// Writes the application's metadata to the package.json file
	/// in it's root folder.
	void writeMetadata() const {
		assert(false);
		// TODO
	}

	/// Rereads the applications state.
	void reinit() {
		m_packages.clear();
		m_main = null;

		try m_json = jsonFromFile(m_root ~ ".dub/dub.json");
		catch(Exception t) logDebug("Could not open .dub/dub.json: %s", t.msg);

		if(!exists(to!string(m_root~"package.json"))) {
			logWarn("There was no 'package.json' found for the application in '%s'.", m_root);
		} else {
			m_main = new Package(m_root);
			if(exists(to!string(m_root~".dub/modules"))) {
				foreach( string pkg; dirEntries(to!string(m_root ~ ".dub/modules"), SpanMode.shallow) ) {
					if( !isDir(pkg) ) continue;
					try {
						auto p = new Package( Path(pkg) );
						enforce( p.name !in m_packages, "Duplicate package: " ~ p.name );
						m_packages[p.name] = p;
					}
					catch(Throwable e) {
						logWarn("The module '%s' in '%s' was not identified as a vibe package.", Path(pkg).head, pkg);
						continue;
					}
				}
			}
		}
	}

	/// Returns the applications name.
	@property string name() const { return m_main ? m_main.name : "app"; }

	/// Returns the DFLAGS
	@property string[] getDflags(BuildPlatform platform)
	const {
		auto ret = appender!(string[])();
		if( m_main ) processVars(ret, ".", m_main.getDflags(platform));
		ret.put("-Isource");
		ret.put("-Jviews");
		foreach( string s, pkg; m_packages ){
			auto pack_path = ".dub/modules/"~pkg.name;
			void addPath(string prefix, string name){
				auto path = pack_path~"/"~name;
				if( exists(path) )
					ret.put(prefix ~ path);
			}
			processVars(ret, pack_path, pkg.getDflags(platform));
			addPath("-I", "source");
			addPath("-J", "views");
		}
		return ret.data();
	}

	/// Actions which can be performed to update the application.
	Action[] actions(PackageSupplier packageSupplier, int option) {
		scope(exit) writeDubJson();

		if(!m_main) {
			Action[] a;
			return a;
		}

		auto graph = new DependencyGraph(m_main);
		if(!gatherMissingDependencies(packageSupplier, graph)  || graph.missing().length > 0) {
			logError("The dependency graph could not be filled.");
			Action[] actions;
			foreach( string pkg, rdp; graph.missing())
				actions ~= Action(Action.ActionId.Failure, pkg, rdp.dependency, rdp.packages);
			return actions;
		}

		auto conflicts = graph.conflicted();
		if(conflicts.length > 0) {
			logDebug("Conflicts found");
			Action[] actions;
			foreach( string pkg, dbp; conflicts)
				actions ~= Action(Action.ActionId.Conflict, pkg, dbp.dependency, dbp.packages);
			return actions;
		}

		// Gather installed
		Package[string] installed;
		installed[m_main.name] = m_main;
		foreach(string pkg, ref Package p; m_packages) {
			enforce( pkg !in installed, "The package '"~pkg~"' is installed more than once." );
			installed[pkg] = p;
		}

		// To see, which could be uninstalled
		Package[string] unused = installed.dup;
		unused.remove( m_main.name );

		// Check against installed and add install actions
		Action[] actions;
		Action[] uninstalls;
		foreach( string pkg, d; graph.needed() ) {
			auto p = pkg in installed;
			// TODO: auto update to latest head revision
			if(!p || (!d.dependency.matches(p.vers) && !d.dependency.matches(Version.MASTER))) {
				if(!p) logDebug("Application not complete, required package '"~pkg~"', which was not found.");
				else logDebug("Application not complete, required package '"~pkg~"', invalid version. Required '%s', available '%s'.", d.dependency, p.vers);
				actions ~= Action(Action.ActionId.InstallUpdate, pkg, d.dependency, d.packages);
			} else {
				logDebug("Required package '"~pkg~"' found with version '"~p.vers~"'");
				if( option & UpdateOptions.Reinstall ) {
					Dependency[string] em;
					uninstalls ~= Action( Action.ActionId.Uninstall, pkg, new Dependency("==", p.vers), em);
					actions ~= Action(Action.ActionId.InstallUpdate, pkg, d.dependency, d.packages);
				}

				if( (pkg in unused) !is null )
					unused.remove(pkg);
			}
		}

		// Add uninstall actions
		foreach( string pkg, p; unused ) {
			logDebug("Superfluous package found: '"~pkg~"', version '"~p.vers~"'");
			Dependency[string] em;
			uninstalls ~= Action( Action.ActionId.Uninstall, pkg, new Dependency("==", p.vers), em);
		}

		// Ugly "uninstall" comes first
		actions = uninstalls ~ actions;

		return actions;
	}

	void createZip(string destination) {
		assert(false); // not properly implemented
		/*
		string[] ignores;
		auto ignoreFile = to!string(m_root~"dub.ignore.txt");
		if(exists(ignoreFile)){
			auto iFile = openFile(ignoreFile);
			scope(exit) iFile.close();
			while(!iFile.empty)
				ignores ~= to!string(cast(char[])iFile.readLine());
			logDebug("Using '%s' found by the application.", ignoreFile);
		}
		else {
			ignores ~= ".svn/*";
			ignores ~= ".git/*";
			ignores ~= ".hg/*";
			logDebug("The '%s' file was not found, defaulting to ignore:", ignoreFile);
		}
		ignores ~= ".dub/*"; // .dub will not be included
		foreach(string i; ignores)
			logDebug(" " ~ i);

		logDebug("Creating zip file from application: " ~ m_main.name);
		auto archive = new ZipArchive();
		foreach( string file; dirEntries(to!string(m_root), SpanMode.depth) ) {
			enforce( Path(file).startsWith(m_root) );
			auto p = Path(file);
			p = p[m_root.length..p.length];
			if(isDir(file)) continue;
			foreach(string ignore; ignores)
				if(globMatch(file, ignore))
					would work, as I see it;
					continue;
			logDebug(" Adding member: %s", p);
			ArchiveMember am = new ArchiveMember();
			am.name = to!string(p);
			auto f = openFile(file);
			scope(exit) f.close();
			am.expandedData = f.readAll();
			archive.addMember(am);
		}

		logDebug(" Writing zip: %s", destination);
		auto dst = openFile(destination, FileMode.CreateTrunc);
		scope(exit) dst.close();
		dst.write(cast(ubyte[])archive.build());
		*/
	}

	private bool gatherMissingDependencies(PackageSupplier packageSupplier, DependencyGraph graph) {
		RequestedDependency[string] missing = graph.missing();
		RequestedDependency[string] oldMissing;
		while( missing.length > 0 ) {
			if(missing.length == oldMissing.length) {
				bool different = false;
				foreach(string pkg, reqDep; missing) {
					auto o = pkg in oldMissing;
					if(o && reqDep.dependency != o.dependency) {
						different = true;
						break;
					}
				}
				if(!different) {
					logWarn("Could not resolve dependencies");
					return false;
				}
			}

			oldMissing = missing.dup;
			logTrace("There are %s packages missing.", missing.length);
			foreach(string pkg, reqDep; missing) {
				if(!reqDep.dependency.valid()) {
					logTrace("Dependency to "~pkg~" is invalid. Trying to fix by modifying others.");
					continue;
				}

				// TODO: auto update and update interval by time
				logTrace("Adding package to graph: "~pkg);
				Package p = null;

				// Try an already installed package first
				if(!needsUpToDateCheck(pkg)) {
					try {
						auto json = jsonFromFile( m_root ~ Path(".dub/modules") ~ Path(pkg) ~ "package.json");
						auto vers = Version(json["version"].get!string);
						if( reqDep.dependency.matches( vers ) )
							p = new Package(json);
						logTrace("Using already installed package with version: %s", vers);
					}
					catch(Throwable e) {
						// not yet installed, try the supplied PS
						logTrace("An installed package was not found");
					}
				}
				if(!p) {
					try {
						p = new Package(packageSupplier.packageJson(pkg, reqDep.dependency));
						logTrace("using package from registry");
						markUpToDate(pkg);
					}
					catch(Throwable e) {
						logError("Geting package metadata for %s failed, exception: %s", pkg, e.toString());
					}
				}

				if(p)
					graph.insert(p);
			}
			graph.clearUnused();
			missing = graph.missing();
		}

		return true;
	}

	private bool needsUpToDateCheck(string packageId) {
		try {
			auto time = m_json["dub"]["lastUpdate"][packageId].to!string;
			return (Clock.currTime() - SysTime.fromISOExtString(time)) > dur!"days"(1);
		}
		catch(Throwable t) {
			return true;
		}
	}

	private void markUpToDate(string packageId) {
		logTrace("markUpToDate(%s)", packageId);
		Json create(ref Json json, string object) {
			if( object !in json ) json[object] = Json.EmptyObject;
			return json[object];
		}
		create(m_json, "dub");
		create(m_json["dub"], "lastUpdate");
		m_json["dub"]["lastUpdate"][packageId] = Json( Clock.currTime().toISOExtString() );

		writeDubJson();
	}

	private void writeDubJson() {
		// don't bother to write an empty file
		if( m_json.length == 0 ) return;

		try {
			logTrace("writeDubJson");
			auto dubpath = m_root~".dub";
			if( !exists(dubpath.toNativeString()) ) mkdir(dubpath.toNativeString());
			auto dstFile = openFile((dubpath~"dub.json").toString(), FileMode.CreateTrunc);
			scope(exit) dstFile.close();
			Appender!string js;
			toPrettyJson(js, m_json);
			dstFile.write( js.data );
		} catch( Exception e ){
			logWarn("Could not write .dub/dub.json.");
		}
	}
}

/// The default supplier for packages, which is the registry
/// hosted by vibed.org.
PackageSupplier defaultPackageSupplier() {
	Url url = Url.parse("http://registry.vibed.org/");
	logDebug("Using the registry from %s", url);
	return new RegistryPS(url);
}

enum UpdateOptions
{
	None = 0,
	JustAnnotate = 1<<0,
	Reinstall = 1<<1
};

/// The Dub class helps in getting the applications
/// dependencies up and running.
class Dub {
	private {
		Path m_root;
		Application m_app;
		PackageSupplier m_packageSupplier;
	}

	/// Initiales the package manager for the vibe application
	/// under root.
	this(Path root, PackageSupplier ps = defaultPackageSupplier()) {
		enforce(root.absolute, "Specify an absolute path for the VPM");
		m_root = root;
		m_packageSupplier = ps;
		m_app = new Application(root);
	}

	/// Returns the name listed in the package.json of the current
	/// application.
	@property string packageName() const { return m_app.name; }

	/// Returns a list of flags which the application needs to be compiled
	/// properly.
	string[] getDflags(BuildPlatform platform) { return m_app.getDflags(platform); }

	/// Lists all installed modules
	void list() {
		logInfo(m_app.info());
	}

	/// Performs installation and uninstallation as necessary for
	/// the application.
	/// @param options bit combination of UpdateOptions
	bool update(UpdateOptions options) {
		Action[] actions = m_app.actions(m_packageSupplier, options);
		if( actions.length == 0 ) return true;

		logInfo("The following changes could be performed:");
		bool conflictedOrFailed = false;
		foreach(Action a; actions) {
			logInfo(capitalize( to!string( a.action ) ) ~ ": " ~ a.packageId ~ ", version %s", a.vers);
			if( a.action == Action.ActionId.Conflict || a.action == Action.ActionId.Failure ) {
				logInfo("Issued by: ");
				conflictedOrFailed = true;
				foreach(string pkg, d; a.issuer)
					logInfo(" "~pkg~": %s", d);
			}
		}

		if( conflictedOrFailed || options & UpdateOptions.JustAnnotate )
			return conflictedOrFailed;

		// Uninstall first

		// ??
		// foreach(Action a	   ; filter!((Action a)        => a.action == Action.ActionId.Uninstall)(actions))
			// uninstall(a.packageId);
		// foreach(Action a; filter!((Action a) => a.action == Action.ActionId.InstallUpdate)(actions))
			// install(a.packageId, a.vers);
		foreach(Action a; actions)
			if(a.action == Action.ActionId.Uninstall)
				uninstall(a.packageId);
		foreach(Action a; actions)
			if(a.action == Action.ActionId.InstallUpdate)
				install(a.packageId, a.vers);

		m_app.reinit();
		Action[] newActions = m_app.actions(m_packageSupplier, 0);
		if(newActions.length > 0) {
			logInfo("There are still some actions to perform:");
			foreach(Action a; newActions)
				logInfo("%s", a);
		}
		else
			logInfo("You are up to date");

		return newActions.length == 0;
	}

	/// Creates a zip from the application.
	void createZip(string zipFile) {
		m_app.createZip(zipFile);
	}

	/// Prints some information to the log.
	void info() {
		logInfo("Status for %s", m_root);
		logInfo("\n" ~ m_app.info());
	}

	/// Gets all installed packages as a "packageId" = "version" associative array
	string[string] installedPackages() const { return m_app.installedPackages(); }

	/// Installs the package matching the dependency into the application.
	/// @param addToApplication if true, this will also add an entry in the
	/// list of dependencies in the application's package.json
	void install(string packageId, const Dependency dep, bool addToApplication = false) {
		logInfo("Installing "~packageId~"...");
		auto destination = m_root ~ ".dub/modules" ~ packageId;
		if(exists(to!string(destination)))
			throw new Exception(packageId~" needs to be uninstalled prior installation.");

		// download
		ZipArchive archive;
		{
			logDebug("Aquiring package zip file");
			auto dload = m_root ~ ".dub/temp/downloads";
			if(!exists(to!string(dload)))
				mkdirRecurse(to!string(dload));
			auto tempFile = m_root ~ (".dub/temp/downloads/"~packageId~".zip");
			string sTempFile = to!string(tempFile);
			if(exists(sTempFile)) remove(sTempFile);
			m_packageSupplier.storePackage(tempFile, packageId, dep); // Q: continue on fail?
			scope(exit) remove(sTempFile);

			// unpack
			auto f = openFile(to!string(tempFile), FileMode.Read);
			scope(exit) f.close();
			ubyte[] b = new ubyte[cast(uint)f.leastSize];
			f.read(b);
			archive = new ZipArchive(b);
		}

		Path getPrefix(ZipArchive a) {
			foreach(ArchiveMember am; a.directory)
				if( Path(am.name).head == PathEntry("package.json") )
					return Path(am.name)[0 .. 1];

			// not correct zip packages HACK
			Path minPath;
			foreach(ArchiveMember am; a.directory)
				if( isPathFromZip(am.name) && (minPath == Path() || minPath.startsWith(Path(am.name))) )
					minPath = Path(am.name);

			return minPath;
		}

		logDebug("Installing from zip.");

		// In a github zip, the actual contents are in a subfolder
		auto prefixInPackage = getPrefix(archive);
		logDebug("zip root folder: %s", prefixInPackage);

		Path getCleanedPath(string fileName) {
			auto path = Path(fileName);
			if(prefixInPackage != Path() && !path.startsWith(prefixInPackage)) return Path();
			return path[prefixInPackage.length..path.length];
		}

		// install
		mkdirRecurse(to!string(destination));
		Journal journal = new Journal;
		foreach(ArchiveMember a; archive.directory) {
			if(!isPathFromZip(a.name)) continue;

			auto cleanedPath = getCleanedPath(a.name);
			if(cleanedPath.empty) continue;
			auto fileName = to!string(destination~cleanedPath);

			if( exists(fileName) && isDir(fileName) ) continue;

			logDebug("Creating %s", fileName);
			mkdirRecurse(fileName);
			auto subPath = cleanedPath;
			for(size_t i=0; i<subPath.length; ++i)
				journal.add(Journal.Entry(Journal.Type.Directory, subPath[0..i+1]));
		}

		foreach(ArchiveMember a; archive.directory) {
			if(isPathFromZip(a.name)) continue;

			auto cleanedPath = getCleanedPath(a.name);
			if(cleanedPath.empty) continue;

			auto fileName = destination~cleanedPath;

			logDebug("Creating %s", fileName.head);
			enforce(exists(to!string(fileName.parentPath)));
			auto dstFile = openFile(to!string(fileName), FileMode.CreateTrunc);
			scope(exit) dstFile.close();
			dstFile.write(archive.expand(a));
			journal.add(Journal.Entry(Journal.Type.RegularFile, cleanedPath));
		}

		{ // write package.json (this one includes a version field)
			auto pj = openFile(to!string(destination~"package.json"), FileMode.CreateTrunc);
			scope(exit) pj.close();
			pj.write(m_packageSupplier.packageJson(packageId, dep).toString());
		}

		// Write journal
		logTrace("Saving installation journal...");
		journal.add(Journal.Entry(Journal.Type.RegularFile, Path("journal.json")));
		journal.save(destination ~ "journal.json");

		if(exists( to!string(destination~"package.json")))
			logInfo(packageId ~ " has been installed with version %s", (new Package(destination)).vers);
	}

	/// Uninstalls a given package from the list of installed modules.
	/// @removeFromApplication: if true, this will also remove an entry in the
	/// list of dependencies in the application's package.json
	void uninstall(const string packageId, bool removeFromApplication = false) {
		logInfo("Uninstalling " ~ packageId);

		auto journalFile = m_root~".dub/modules"~packageId~"journal.json";
		if( !exists(to!string(journalFile)) )
			throw new Exception("Uninstall failed, no journal found for '"~packageId~"'. Please uninstall manually.");

		auto packagePath = m_root~".dub/modules"~packageId;
		auto journal = new Journal(journalFile);
		logDebug("Erasing files");
		foreach( Journal.Entry e; filter!((Journal.Entry a) => a.type == Journal.Type.RegularFile)(journal.entries)) {
			logTrace("Deleting file '%s'", e.relFilename);
			auto absFile = packagePath~e.relFilename;
			if(!exists(to!string(absFile))) {
				logWarn("Previously installed file not found for uninstalling: '%s'", absFile);
				continue;
			}

			remove(to!string(absFile));
		}

		logDebug("Erasing directories");
		Path[] allPaths;
		foreach(Journal.Entry e; filter!((Journal.Entry a) => a.type == Journal.Type.Directory)(journal.entries))
			allPaths ~= packagePath~e.relFilename;
		sort!("a.length>b.length")(allPaths); // sort to erase deepest paths first
		foreach(Path p; allPaths) {
			logTrace("Deleting folder '%s'", p);
			if( !exists(to!string(p)) || !isDir(to!string(p)) || !isEmptyDir(p) ) {
				logError("Alien files found, directory is not empty or is not a directory: '%s'", p);
				continue;
			}
			rmdir( to!string(p) );
		}

		if(!isEmptyDir(packagePath))
			throw new Exception("Alien files found in '"~to!string(packagePath)~"', manual uninstallation needed.");

		rmdir(to!string(packagePath));
		logInfo("Uninstalled package: '"~packageId~"'");
	}
}

private void processVars(ref Appender!(string[]) dst, string project_path, string[] vars)
{
	foreach( var; vars ){
		auto idx = std.string.indexOf(var, '$');
		if( idx < 0 ) dst.put(var);
		else {
			auto vres = appender!string();
			while( idx >= 0 ){
				if( idx+1 >= var.length ) break;
				if( var[idx+1] == '$' ){
					vres.put(var[0 .. idx+1]);
					var = var[idx+2 .. $];
				} else {
					vres.put(var[0 .. idx]);
					var = var[idx+1 .. $];

					size_t idx2 = 0;
					while( idx2 < var.length && isIdentChar(var[idx2]) ) idx2++;
					auto varname = var[0 .. idx2];
					var = var[idx2 .. $];

					if( varname == "PACKAGE_DIR" ) vres.put(project_path);
					else enforce(false, "Invalid variable: "~varname);
				}
				idx = std.string.indexOf(var, '$');
			}
			vres.put(var);
			dst.put(vres.data);
		}
	}
}

private bool isIdentChar(char ch)
{
	return ch >= 'A' && ch <= 'Z' || ch >= 'a' && ch <= 'z' || ch >= '0' && ch <= '9' || ch == '_';
}