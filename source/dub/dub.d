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
import dub.packagemanager;
import dub.packagesupplier;
import dub.generators.generator;

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
import std.string;
import std.typecons;
import std.zip;
import stdx.process;


/// Actions to be performed by the dub
private struct Action {
	enum ActionId {
		InstallUpdate,
		Uninstall,
		Conflict,
		Failure
	}

	immutable {
		ActionId action;
		string packageId;
		Dependency vers;
	}
	const Package pack;
	const Dependency[string] issuer;

	this(ActionId id, string pkg, in Dependency d, Dependency[string] issue)
	{
		action = id;
		packageId = pkg;
		vers = new immutable(Dependency)(d);
		issuer = issue;
	}

	this(ActionId id, Package pkg, Dependency[string] issue)
	{
		pack = pkg;
		action = id;
		packageId = pkg.name;
		vers = new immutable(Dependency)("==", pkg.vers);
		issuer = issue;
	}

	string toString() const {
		return to!string(action) ~ ": " ~ packageId ~ ", " ~ to!string(vers);
	}
}

/// During check to build task list, which can then be executed.
private class Application {
	private {
		Path m_root;
		PackageManager m_packageManager;
		Json m_json;
		Package m_main;
		//Package[string] m_packages;
		Package[] m_dependencies;
	}

	this(PackageManager package_manager, Path project_path)
	{
		m_root = project_path;
		m_packageManager = package_manager;
		m_json = Json.EmptyObject;
		reinit();
	}

	@property Path binaryPath() const { auto p = m_main.binaryPath; return p.length ? Path(p) : Path("./"); }

	string getDefaultConfiguration(BuildPlatform platform)
	const {
		string ret;
		foreach( p; m_dependencies ){
			auto c = p.getDefaultConfiguration(platform);
			if( c.length ) ret = c;
		}
		auto c = m_main.getDefaultConfiguration(platform);
		if( c ) ret = c;
		return ret;
	}

	/// Gathers information
	string info() const {
		if(!m_main)
			return "-Unregocgnized application in '"~to!string(m_root)~"' (properly no package.json in this directory)";
		string s = "-Application identifier: " ~ m_main.name;
		s ~= "\n" ~ m_main.info();
		s ~= "\n-Installed dependencies:";
		foreach(p; m_dependencies)
			s ~= "\n" ~ p.info();
		return s;
	}

	/// Gets all installed packages as a "packageId" = "version" associative array
	string[string] installedPackagesIDs() const {
		string[string] pkgs;
		foreach(p; m_dependencies)
			pkgs[p.name] = p.vers;
		return pkgs;
	}

	const(Package[]) installedPackages() const {
		return m_dependencies;
	}
	
	const (Package) mainPackage() const {
		return m_main;
	}
	
	/// Writes the application's metadata to the package.json file
	/// in it's root folder.
	void writeMetadata() const {
		assert(false);
		// TODO
	}

	/// Rereads the applications state.
	void reinit() {
		m_dependencies = null;
		m_main = null;
		m_packageManager.refresh();

		try m_json = jsonFromFile(m_root ~ ".dub/dub.json", true);
		catch(Exception t) logDebug("Failed to read .dub/dub.json: %s", t.msg);

		if( !existsFile(m_root~PackageJsonFilename) ){
			logWarn("There was no '"~PackageJsonFilename~"' found for the application in '%s'.", m_root.toNativeString());
			return;
		}

		m_main = new Package(InstallLocation.Local, m_root);

		// TODO: compute the set of mutual dependencies first
		// (i.e. ">=0.0.1 <=0.0.5" and "<= 0.0.4" get ">=0.0.1 <=0.0.4")
		// conflicts would then also be detected.
		void collectDependenciesRec(Package pack)
		{
			logDebug("Collecting dependencies for %s", pack.name);
			foreach( ldef; pack.localPackageDefs ){
				Path path = ldef.path;
				if( !path.absolute ) path = pack.path ~ path;
				logDebug("Adding local %s %s", path, ldef.version_);
				m_packageManager.addLocalPackage(path, ldef.version_, LocalPackageType.temporary);
			}

			foreach( name, vspec; pack.dependencies ){
				auto p = m_packageManager.getBestPackage(name, vspec);
				if( !m_dependencies.canFind(p) ){
					logDebug("Found dependency %s %s: %s", name, vspec.toString(), p !is null);
					if( p ){
						m_dependencies ~= p;
						collectDependenciesRec(p);
					}
				}
				//enforce(p !is null, "Failed to resolve dependency "~name~" "~vspec.toString());
			}
		}
		collectDependenciesRec(m_main);
	}

	/// Returns the applications name.
	@property string name() const { return m_main ? m_main.name : "app"; }

	@property string[] configurations()
	const {
		string[] ret;
		if( m_main ) ret = m_main.configurations;
		foreach( p; m_dependencies ){
			auto cfgs = p.configurations;
			foreach( c; cfgs )
				if( !ret.canFind(c) ) ret ~= c;
		}
		return ret;
	}

	/// Returns the DFLAGS
	BuildSettings getBuildSettings(BuildPlatform platform, string config)
	const {
		BuildSettings ret;

		void addImportPath(string path, bool src)
		{
			if( !exists(path) ) return;
			if( src ) ret.addImportDirs([path]);
			else ret.addStringImportDirs([path]);
		}

		if( m_main ) processVars(ret, ".", m_main.getBuildSettings(platform, config));
		addImportPath("source", true);
		addImportPath("views", false);

		foreach( pkg; m_dependencies ){
			processVars(ret, pkg.path.toNativeString(), pkg.getBuildSettings(platform, config));
			addImportPath((pkg.path ~ "source").toNativeString(), true);
			addImportPath((pkg.path ~ "views").toNativeString(), false);
		}

		return ret;
	}

	/// Actions which can be performed to update the application.
	Action[] determineActions(PackageSupplier packageSupplier, int option) {
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
		foreach(ref Package p; m_dependencies) {
			if( auto ppo = p.name in installed ){
				logError("The same package is referenced in different paths:");
				logError("  %s %s: %s", ppo.name, ppo.vers, ppo.path.toNativeString());
				logError("  %s %s: %s", p.name, p.vers, p.path.toNativeString());
				throw new Exception("Conflicting package multi-references.");
			}
			installed[p.name] = p;
		}

		// To see, which could be uninstalled
		Package[string] unused = installed.dup;
		unused.remove(m_main.name);

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
					if( p.installLocation != InstallLocation.Local ){
						Dependency[string] em;
						if( p.installLocation == InstallLocation.ProjectLocal )
							uninstalls ~= Action(Action.ActionId.Uninstall, *p, em);
						actions ~= Action(Action.ActionId.InstallUpdate, pkg, d.dependency, d.packages);
					} else {
						logInfo("Skipping local package %s at %s", p.name, p.path.toNativeString());
					}
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
			logTrace("Try to resolve %s", missing.keys);
			if( missing.keys == oldMissing.keys ){ // FIXME: should actually compare the complete AA here
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
				Package p = m_packageManager.getBestPackage(pkg, reqDep.dependency);
				if( p ) logTrace("Found installed package %s %s", pkg, p.ver);
				
				// Try an already installed package first
				if( p && p.installLocation != InstallLocation.Local && needsUpToDateCheck(pkg) ){
					logInfo("Triggering update of package %s", pkg);
					p = null;
				}

				if( !p ){
					try {
						logDebug("using package from registry");
						p = new Package(packageSupplier.packageJson(pkg, reqDep.dependency));
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
			auto time = m_json["lastUpdate"].opt!(Json[string]).get(packageId, Json("")).get!string;
			if( !time.length ) return true;
			return (Clock.currTime() - SysTime.fromISOExtString(time)) > dur!"days"(1);
		} catch(Exception t) return true;
	}
		
	void markUpToDate(string packageId) {
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
/// dependencies up and running. An instance manages one application.
class Dub {
	private {
		Path m_cwd, m_tempPath;
		Path m_root;
		PackageSupplier m_packageSupplier;
		Path m_userDubPath, m_systemDubPath;
		Json m_systemConfig, m_userConfig;
		PackageManager m_packageManager;
		Application m_app;
	}

	/// Initiales the package manager for the vibe application
	/// under root.
	this(PackageSupplier ps = defaultPackageSupplier())
	{
		m_cwd = Path(getcwd());

		version(Windows){
			m_systemDubPath = Path(environment.get("ProgramData")) ~ "dub/";
			m_userDubPath = Path(environment.get("APPDATA")) ~ "dub/";
			m_tempPath = Path(environment.get("TEMP"));
		} else version(Posix){
			m_systemDubPath = Path("/etc/dub/");
			m_userDubPath = Path(environment.get("HOME")) ~ ".dub/";
			m_tempPath = Path("/tmp");
		}
		
		m_userConfig = jsonFromFile(m_userDubPath ~ "settings.json", true);
		m_systemConfig = jsonFromFile(m_systemDubPath ~ "settings.json", true);

		m_packageSupplier = ps;
		m_packageManager = new PackageManager(m_systemDubPath ~ "packages/", m_userDubPath ~ "packages/");
	}

	/// Returns the name listed in the package.json of the current
	/// application.
	@property string projectName() const { return m_app.name; }

	@property Path projectPath() const { return m_root; }

	@property string[] configurations() const { return m_app.configurations; }

	@property inout(PackageManager) packageManager() inout { return m_packageManager; }

	@property Path binaryPath() const { return m_app.binaryPath; }

	void loadPackageFromCwd()
	{
		m_root = m_cwd;
		m_packageManager.projectPackagePath = m_root ~ ".dub/packages/";
		m_app = new Application(m_packageManager, m_root);
	}

	/// Returns a list of flags which the application needs to be compiled
	/// properly.
	BuildSettings getBuildSettings(BuildPlatform platform, string config) { return m_app.getBuildSettings(platform, config); }

	string getDefaultConfiguration(BuildPlatform platform) const { return m_app.getDefaultConfiguration(platform); }

	/// Lists all installed modules
	void list() {
		logInfo(m_app.info());
	}

	/// Performs installation and uninstallation as necessary for
	/// the application.
	/// @param options bit combination of UpdateOptions
	bool update(UpdateOptions options) {
		Action[] actions = m_app.determineActions(m_packageSupplier, options);
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
			if(a.action == Action.ActionId.Uninstall){
				assert(a.pack !is null, "No package specified for uninstall.");
				uninstall(a.pack);
			}
		foreach(Action a; actions)
			if(a.action == Action.ActionId.InstallUpdate)
				install(a.packageId, a.vers);

		m_app.reinit();
		Action[] newActions = m_app.determineActions(m_packageSupplier, 0);
		if(newActions.length > 0) {
			logInfo("There are still some actions to perform:");
			foreach(Action a; newActions)
				logInfo("%s", a);
		}
		else
			logInfo("You are up to date");

		return newActions.length == 0;
	}

	/// Generate project files for a specified IDE.
	/// Any existing project files will be overridden.
	void generateProject(string ide) {
		auto generator = createProjectGenerator(ide, m_app, m_packageManager);
		if(generator is null ) {
			logError("Unsupported IDE, there is no generator available for '"~ide~"'");
			throw new Exception("Unsupported IDE, there is no generator available for '"~ide~"'");
		}
		
		// Q: update before generating?
		
		generator.generateProject();
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
	string[string] installedPackages() const { return m_app.installedPackagesIDs(); }

	/// Installs the package matching the dependency into the application.
	/// @param addToApplication if true, this will also add an entry in the
	/// list of dependencies in the application's package.json
	void install(string packageId, const Dependency dep, InstallLocation location = InstallLocation.ProjectLocal)
	{
		auto pinfo = m_packageSupplier.packageJson(packageId, dep);
		string ver = pinfo["version"].get!string;

		logInfo("Installing %s %s...", packageId, ver);

		logDebug("Aquiring package zip file");
		auto dload = m_root ~ ".dub/temp/downloads";
		auto tempFile = m_tempPath ~ ("dub-download-"~packageId~"-"~ver~".zip");
		string sTempFile = to!string(tempFile);
		if(exists(sTempFile)) remove(sTempFile);
		m_packageSupplier.storePackage(tempFile, packageId, dep); // Q: continue on fail?
		scope(exit) remove(sTempFile);

		m_packageManager.install(tempFile, pinfo, location);
	}

	/// Uninstalls a given package from the list of installed modules.
	/// @removeFromApplication: if true, this will also remove an entry in the
	/// list of dependencies in the application's package.json
	void uninstall(in Package pack)
	{
		logInfo("Uninstalling %s in %s", pack.name, pack.path.toNativeString());

		m_packageManager.uninstall(pack);
	}

	void addLocalPackage(string path, string ver, bool system)
	{
		auto abs_path = Path(path);
		if( !abs_path.absolute ) abs_path = m_cwd ~ abs_path;
		m_packageManager.addLocalPackage(abs_path, Version(ver), system ? LocalPackageType.system : LocalPackageType.user);
	}

	void removeLocalPackage(string path, bool system)
	{
		auto abs_path = Path(path);
		if( !abs_path.absolute ) abs_path = m_cwd ~ abs_path;
		m_packageManager.removeLocalPackage(abs_path, system ? LocalPackageType.system : LocalPackageType.user);
	}
}

private void processVars(ref BuildSettings dst, string project_path, BuildSettings settings)
{
	dst.addDFlags(processVars(project_path, settings.dflags));
	dst.addLFlags(processVars(project_path, settings.lflags));
	dst.addLibs(processVars(project_path, settings.libs));
	dst.addFiles(processVars(project_path, settings.files, true));
	dst.addCopyFiles(processVars(project_path, settings.copyFiles, true));
	dst.addVersions(processVars(project_path, settings.versions));
	dst.addImportDirs(processVars(project_path, settings.importPaths, true));
	dst.addStringImportDirs(processVars(project_path, settings.stringImportPaths, true));
}

private string[] processVars(string project_path, string[] vars, bool are_paths = false)
{
	auto ret = appender!(string[])();
	processVars(ret, project_path, vars, are_paths);
	return ret.data;

}
private void processVars(ref Appender!(string[]) dst, string project_path, string[] vars, bool are_paths = false)
{
	foreach( var; vars ){
		auto idx = std.string.indexOf(var, '$');
		if( idx >= 0 ){
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
			var = vres.data;
		}
		if( are_paths ){
			auto p = Path(var);
			if( !p.absolute ){
				logTrace("Fixing relative path: %s ~ %s", project_path, p.toNativeString());
				p = Path(project_path) ~ p;
			}
			dst.put(p.toNativeString());
		} else dst.put(var);
	}
}

private bool isIdentChar(char ch)
{
	return ch >= 'A' && ch <= 'Z' || ch >= 'a' && ch <= 'z' || ch >= '0' && ch <= '9' || ch == '_';
}