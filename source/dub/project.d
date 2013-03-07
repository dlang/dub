/**
	Representing a full project, with a root Package and several dependencies.

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff, Sönke Ludwig
*/
module dub.project;

import dub.compilers.compiler;
import dub.dependency;
import dub.installation;
import dub.utils;
import dub.registry;
import dub.package_;
import dub.packagemanager;
import dub.packagesupplier;
import dub.generators.generator;

import vibecompat.core.file;
import vibecompat.core.log;
import vibecompat.data.json;
import vibecompat.inet.url;

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


/// Representing a full project, with a root Package and several dependencies.
class Project {
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

	@property Path binaryPath() const { return m_main.binaryPath; }

	/// Gathers information
	@property string info()
	const {
		if(!m_main)
			return "-Unrecognized application in '"~m_root.toNativeString()~"' (probably no package.json in this directory)";
		string s = "-Application identifier: " ~ m_main.name;
		s ~= "\n" ~ m_main.info();
		s ~= "\n-Installed dependencies:";
		foreach(p; m_dependencies)
			s ~= "\n" ~ p.info();
		return s;
	}

	/// Gets all installed packages as a "packageId" = "version" associative array
	@property string[string] installedPackagesIDs() const {
		string[string] pkgs;
		foreach(p; m_dependencies)
			pkgs[p.name] = p.vers;
		return pkgs;
	}

	/// List of installed Packages
	@property const(Package[]) dependencies() const { return m_dependencies; }
	
	/// Main package.
	@property const (Package) mainPackage() const { return m_main; }

	/** Allows iteration of the dependency tree in topological order
	*/
	int delegate(int delegate(ref const Package)) getTopologicalPackageList(bool children_first = false)
	const {
		int iterator(int delegate(ref const Package) del)
		{
			int ret = 0;
			bool[const(Package)] visited;
			void perform_rec(in Package p){
				if( p in visited ) return;
				visited[p] = true;

				if( !children_first ){
					ret = del(p);
					if( ret ) return;
				}

				foreach(d; p.dependencies.byKey)
					foreach(dp; m_dependencies)
						if( dp.name == d ){
							perform_rec(dp);
							if( ret ) return;
							break;
						}

				if( children_first ){
					ret = del(p);
					if( ret ) return;
				}
			}
			perform_rec(m_main);
			return ret;
		}
		return &iterator;
	}

	string getDefaultConfiguration(BuildPlatform platform)
	const {
		return m_main.getDefaultConfiguration(platform, true);
	}


	/// Writes the application's metadata to the package.json file
	/// in it's root folder.
	void writeMetadata() const {
		assert(false);
		// TODO
	}

	/// Rereads the applications state.
	void reinit() {
		scope(failure){
			logDebug("Failed to parse package.json. Assuming defaults.");
			m_main = new Package(serializeToJson(["name": ""]), InstallLocation.local, m_root);
		}

		m_dependencies = null;
		m_main = null;
		m_packageManager.refresh();

		try m_json = jsonFromFile(m_root ~ ".dub/dub.json", true);
		catch(Exception t) logDebug("Failed to read .dub/dub.json: %s", t.msg);

		if( !existsFile(m_root~PackageJsonFilename) ){
			logWarn("There was no '"~PackageJsonFilename~"' found for the application in '%s'.", m_root.toNativeString());
			auto json = Json.EmptyObject;
			json.name = "";
			m_main = new Package(json, InstallLocation.local, m_root);
			return;
		}

		m_main = new Package(InstallLocation.local, m_root);

		// TODO: compute the set of mutual dependencies first
		// (i.e. ">=0.0.1 <=0.0.5" and "<= 0.0.4" get ">=0.0.1 <=0.0.4")
		// conflicts would then also be detected.
		void collectDependenciesRec(Package pack)
		{
			logDebug("Collecting dependencies for %s", pack.name);
			foreach( name, vspec; pack.dependencies ){
				if( !vspec.path.empty ){
					Path path = vspec.path;
					if( !path.absolute ) path = pack.path ~ path;
					logDebug("Adding local %s %s", path, vspec.version_);
					m_packageManager.addLocalPackage(path, vspec.version_, LocalPackageType.temporary);
				} else {
					auto p = m_packageManager.getBestPackage(name, vspec);
					if( !m_dependencies.canFind(p) ){
						logDebug("Found dependency %s %s: %s", name, vspec.toString(), p !is null);
						if( p ){
							m_dependencies ~= p;
							collectDependenciesRec(p);
						}
					}
				}
				//enforce(p !is null, "Failed to resolve dependency "~name~" "~vspec.toString());
			}
		}
		collectDependenciesRec(m_main);
	}

	/// Returns the applications name.
	@property string name() const { return m_main ? m_main.name : "app"; }

	@property string[] configurations() const { return m_main.configurations; }

	string getPackageConfig(in Package pack, BuildPlatform platform, string config)
	const {
		if( pack is m_main ) return config;
		else {
			// TODO: check the dependees for special wishes in terms on the configuration
			return pack.getDefaultConfiguration(platform, false);
		}
	}

	/// Returns the DFLAGS
	void addBuildSettings(ref BuildSettings dst, BuildPlatform platform, string config)
	const {
		foreach(pkg; this.getTopologicalPackageList()){
			auto pkgconf = getPackageConfig(pkg, platform, config);
			auto psettings = pkg.getBuildSettings(platform, pkgconf);
			processVars(dst, pkg.path.toNativeString(), psettings);
			if( pkg is m_main ) dst.targetType = psettings.targetType;
		}

		// add version identifiers for available packages
		foreach(pack; this.dependencies)
			dst.addVersions(["Have_" ~ stripDlangSpecialChars(pack.name)]);
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
				actions ~= Action.failure(pkg, rdp.dependency, rdp.packages);
			return actions;
		}

		auto conflicts = graph.conflicted();
		if(conflicts.length > 0) {
			logDebug("Conflicts found");
			Action[] actions;
			foreach( string pkg, dbp; conflicts)
				actions ~= Action.conflict(pkg, dbp.dependency, dbp.packages);
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
				actions ~= Action.install(pkg, InstallLocation.projectLocal, d.dependency, d.packages);
			} else {
				logDebug("Required package '"~pkg~"' found with version '"~p.vers~"'");
				if( option & UpdateOptions.Reinstall ) {
					if( p.installLocation != InstallLocation.local ){
						Dependency[string] em;
						// user and system packages are not uninstalled (could be needed by other projects)
						if( p.installLocation == InstallLocation.projectLocal )
							uninstalls ~= Action.uninstall(*p, em);
						actions ~= Action.install(pkg, p.installLocation, d.dependency, d.packages);
					} else {
						logInfo("Skipping local package %s at %s", p.name, p.path.toNativeString());
					}
				}

				if( (pkg in unused) !is null )
					unused.remove(pkg);
			}
		}

		// Add uninstall actions
		foreach( pname, pkg; unused ){
			if( pkg.installLocation != InstallLocation.projectLocal )
				continue;
			logDebug("Superfluous package found: '"~pname~"', version '"~pkg.vers~"'");
			Dependency[string] em;
			uninstalls ~= Action.uninstall(pkg, em);
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

	/// Tries to add the specified dependency.
	/// If an existing dependencies is already current, this one is compared to
	///	the supplied one, in order to check if these are compatible.
	///	@return true, if the dependency was succesfully added, false if the
	///	new dependency cannot be added because of current settings.
	bool tryAddDependency(string packageId, const Dependency dependency) {
		try {
			m_main.addDependency(packageId, dependency);
			m_main.writeJson(m_root);
			return true;
		}
		catch(Exception e) {
			logError("The dependency '%s' '%s' could not be added. Try to check the package.json of your project if this is a conflict with an existing dependency.", packageId, dependency);
			return false;
		}
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
				if( p && p.installLocation != InstallLocation.local && needsUpToDateCheck(pkg) ){
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
			auto time = m_json["dub"]["lastUpdate"].opt!(Json[string]).get(packageId, Json("")).get!string;
			if( !time.length ) return true;
			return (Clock.currTime() - SysTime.fromISOExtString(time)) > dur!"days"(1);
		} catch(Exception t) return true;
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
			dstFile.writePrettyJsonString(m_json);
		} catch( Exception e ){
			logWarn("Could not write .dub/dub.json.");
		}
	}
}

/// Actions to be performed by the dub
struct Action {
	enum Type {
		install,
		uninstall,
		conflict,
		failure
	}

	immutable {
		Type type;
		string packageId;
		InstallLocation location;
		Dependency vers;
	}
	const Package pack;
	const Dependency[string] issuer;

	static Action install(string pkg, InstallLocation location, in Dependency dep, Dependency[string] context)
	{
		return Action(Type.install, pkg, location, dep, context);
	}

	static Action uninstall(Package pkg, Dependency[string] context)
	{
		return Action(Type.uninstall, pkg, context);
	}

	static Action conflict(string pkg, in Dependency dep, Dependency[string] context)
	{
		return Action(Type.conflict, pkg, InstallLocation.projectLocal, dep, context);
	}

	static Action failure(string pkg, in Dependency dep, Dependency[string] context)
	{
		return Action(Type.failure, pkg, InstallLocation.projectLocal, dep, context);
	}

	private this(Type id, string pkg, InstallLocation location, in Dependency d, Dependency[string] issue)
	{
		this.type = id;
		this.packageId = pkg;
		this.location = location;
		this.vers = new immutable(Dependency)(d);
		this.issuer = issue;
	}

	private this(Type id, Package pkg, Dependency[string] issue)
	{
		pack = pkg;
		type = id;
		packageId = pkg.name;
		vers = new immutable(Dependency)(pkg.ver);
		issuer = issue;
	}

	string toString() const {
		return to!string(type) ~ ": " ~ packageId ~ ", " ~ to!string(vers);
	}
}

enum UpdateOptions
{
	None = 0,
	JustAnnotate = 1<<0,
	Reinstall = 1<<1
};


private void processVars(ref BuildSettings dst, string project_path, BuildSettings settings)
{
	dst.addDFlags(processVars(project_path, settings.dflags));
	dst.addLFlags(processVars(project_path, settings.lflags));
	dst.addLibs(processVars(project_path, settings.libs));
	dst.addSourceFiles(processVars(project_path, settings.sourceFiles, true));
	dst.addCopyFiles(processVars(project_path, settings.copyFiles, true));
	dst.addVersions(processVars(project_path, settings.versions));
	dst.addImportPaths(processVars(project_path, settings.importPaths, true));
	dst.addStringImportPaths(processVars(project_path, settings.stringImportPaths, true));
	dst.addPreGenerateCommands(processVars(project_path, settings.preGenerateCommands));
	dst.addPostGenerateCommands(processVars(project_path, settings.postGenerateCommands));
	dst.addPreBuildCommands(processVars(project_path, settings.preBuildCommands));
	dst.addPostBuildCommands(processVars(project_path, settings.postBuildCommands));
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

private bool isIdentChar(dchar ch)
{
	return ch >= 'A' && ch <= 'Z' || ch >= 'a' && ch <= 'z' || ch >= '0' && ch <= '9' || ch == '_';
}

private string stripDlangSpecialChars(string s) 
{
	import std.array;
	import std.uni;
	auto ret = appender!string();
	foreach(ch; s)
		ret.put(isIdentChar(ch) ? ch : '_');
	return ret.data;
}
