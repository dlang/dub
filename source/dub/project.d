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
import dub.internal.std.process;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.url;
import dub.utils;
import dub.package_;
import dub.packagemanager;
import dub.packagesupplier;
import dub.generators.generator;


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


/// Representing a full project, with a root Package and several dependencies.
class Project {
	private {
		Path m_root;
		PackageManager m_packageManager;
		Json m_json;
		Package m_main;
		//Package[string] m_packages;
		Package[] m_dependencies;
		Package[][Package] m_dependees;
	}

	this(PackageManager package_manager, Path project_path)
	{
		m_root = project_path;
		m_packageManager = package_manager;
		m_json = Json.EmptyObject;
		reinit();
	}

	/// Gathers information
	@property string info()
	const {
		if(!m_main)
			return "-Unrecognized application in '"~m_root.toNativeString()~"' (probably no package.json in this directory)";
		string s = "-Application identifier: " ~ m_main.name;
		s ~= "\n" ~ m_main.generateInfoString();
		s ~= "\n-Installed dependencies:";
		foreach(p; m_dependencies)
			s ~= "\n" ~ p.generateInfoString();
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
	int delegate(int delegate(ref const Package)) getTopologicalPackageList(bool children_first = false, in Package root_package = null, string[string] configs = null)
	const {
		const(Package) rootpack = root_package ? root_package : m_main;
	
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

				auto cfg = configs.get(p.name, null);

				foreach (dn, dv; p.dependencies) {
					// filter out dependencies not in the current configuration set
					if (!p.hasDependency(dn, cfg)) continue;
					auto dependency = getDependency(dn, dv.optional);
					if(dependency) perform_rec(dependency);
					if( ret ) return;
				}

				if( children_first ){
					ret = del(p);
					if( ret ) return;
				}
			}
			perform_rec(rootpack);
			return ret;
		}
		
		return &iterator;
	}

	inout(Package) getDependency(string name, bool isOptional)
	inout {
		foreach(dp; m_dependencies)
			if( dp.name == name )
				return dp;
		if(!isOptional) throw new Exception("Unknown dependency: "~name);
		else return null;
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
	void reinit()
	{
		scope(failure){
			logDiagnostic("Failed to initialize project. Assuming defaults.");
			m_main = new Package(serializeToJson(["name": "unknown"]), m_root);
		}

		m_dependencies = null;
		m_main = null;
		m_packageManager.refresh(false);

		try m_json = jsonFromFile(m_root ~ ".dub/dub.json", true);
		catch(Exception t) logDiagnostic("Failed to read .dub/dub.json: %s", t.msg);

		if( !existsFile(m_root~PackageJsonFilename) ){
			logWarn("There was no '"~PackageJsonFilename~"' found for the application in '%s'.", m_root.toNativeString());
			auto json = Json.EmptyObject;
			json.name = "unknown";
			m_main = new Package(json, m_root);
			return;
		}

		m_main = m_packageManager.getPackage(m_root);
		m_main.warnOnSpecialCompilerFlags();
		if (m_main.name != m_main.name.toLower()) {
			logWarn(`DUB package names should always be lower case, please change to {"name": "%s"}. You can use {"targetName": "%s"} to keep the current executable name.`,
				m_main.name.toLower(), m_main.name);
		}

		// TODO: compute the set of mutual dependencies first
		// (i.e. ">=0.0.1 <=0.0.5" and "<= 0.0.4" get ">=0.0.1 <=0.0.4")
		// conflicts would then also be detected.
		void collectDependenciesRec(Package pack)
		{
			logDiagnostic("Collecting dependencies for %s", pack.name);
			foreach( name, vspec; pack.dependencies ){
				Package p;
				if( !vspec.path.empty ){
					Path path = vspec.path;
					if( !path.absolute ) path = pack.path ~ path;
					logDiagnostic("Adding local %s %s", path, vspec.version_);
					p = m_packageManager.addTemporaryPackage(path, vspec.version_);
				} else {
					p = m_packageManager.getBestPackage(name, vspec);
				}
				if( !m_dependencies.canFind(p) ){
					logDiagnostic("Found dependency %s %s: %s", name, vspec.toString(), p !is null);
					if( p ){
						m_dependencies ~= p;
						p.warnOnSpecialCompilerFlags();
						collectDependenciesRec(p);
					}
				}
				m_dependees[p] ~= pack;
				//enforce(p !is null, "Failed to resolve dependency "~name~" "~vspec.toString());
			}
		}
		collectDependenciesRec(m_main);
	}

	/// Returns the applications name.
	@property string name() const { return m_main ? m_main.name : "app"; }

	@property string[] configurations() const { return m_main.configurations; }

	/// Returns a map with the configuration for all packages in the dependency tree. 
	string[string] getPackageConfigs(in BuildPlatform platform, string config)
	const {
		string[string] configs;
		void determineConfigsRec(in Package p, bool use_default){
			if( p.name !in configs ){
				if( use_default ) configs[p.name] = p.getDefaultConfiguration(platform);
				else return;
			}
			auto pconf = configs[p.name];
			foreach(dn, dv; p.dependencies){
				auto dep = getDependency(dn, dv.optional);
				if( dep is null ) continue;
				auto conf = p.getSubConfiguration(pconf, dep, platform);
				if( !conf.empty ){
					if( auto pc = dn in configs ){
						enforce(*pc == conf, format("Conflicting configurations detected for %s: %s vs. %s", dn, *pc, conf));
					} else {
						configs[dn] = conf;
					}
				} else if( use_default && dn !in configs ){
					configs[dn] = dep.getDefaultConfiguration(platform);
				}
				determineConfigsRec(dep, use_default);
			}
		}

		configs[m_main.name] = config;
		determineConfigsRec(m_main, false); // first only match all explicit selections
		determineConfigsRec(m_main, true); // then fill up the rest with default configurations
		return configs;
	}

	/// Returns the DFLAGS
	void addBuildSettings(ref BuildSettings dst, in BuildPlatform platform, string config, in Package root_package = null)
	const {
		auto configs = getPackageConfigs(platform, config);

		foreach (pkg; this.getTopologicalPackageList(false, root_package, configs)) {
			dst.addVersions(["Have_" ~ stripDlangSpecialChars(pkg.name)]);

			auto psettings = pkg.getBuildSettings(platform, configs[pkg.name]);
			if (psettings.targetType != TargetType.none)
				processVars(dst, pkg.path.toNativeString(), psettings);
			if (pkg is m_main) {
				enforce(psettings.targetType != TargetType.none, "Main package has target type \"none\" - stopping build.");
				dst.targetType = psettings.targetType;
				dst.targetPath = psettings.targetPath;
				dst.targetName = psettings.targetName;
				dst.workingDirectory = psettings.workingDirectory;
			}
		}

		// always add all version identifiers of all packages
		foreach (pkg; this.getTopologicalPackageList(false, null, configs)) {
			auto psettings = pkg.getBuildSettings(platform, configs[pkg.name]);
			dst.addVersions(psettings.versions);
		}
	}

	void addBuildTypeSettings(ref BuildSettings dst, in BuildPlatform platform, string build_type)
	{
		bool usedefflags = !(dst.requirements & BuildRequirements.noDefaultFlags);
		if (usedefflags) {
			dst.addDFlags(["-w"]);
			BuildSettings btsettings;
			m_main.addBuildTypeSettings(btsettings, platform, build_type);
			processVars(dst, m_main.path.toNativeString(), btsettings);
		}
	}


	/// Actions which can be performed to update the application.
	Action[] determineActions(PackageSupplier[] packageSuppliers, int option)
	{
		scope(exit) writeDubJson();

		if(!m_main) {
			Action[] a;
			return a;
		}

		auto graph = new DependencyGraph(m_main);
		if(!gatherMissingDependencies(packageSuppliers, graph)  || graph.missing().length > 0) {
			// Check the conflicts first.
			auto conflicts = graph.conflicted();
			if(conflicts.length > 0) {
				logError("The dependency graph could not be filled, there are conflicts.");
				Action[] actions;
				foreach( string pkg, dbp; graph.conflicted())
					actions ~= Action.conflict(pkg, dbp.dependency, dbp.packages);
				// Missing dependencies could have some bogus results, therefore
				// return only the conflicts.
				return actions;
			}

			// Then check unresolved dependencies.
			logError("The dependency graph could not be filled, there are unresolved dependencies.");
			Action[] actions;
			foreach( string pkg, rdp; graph.missing())
				actions ~= Action.failure(pkg, rdp.dependency, rdp.packages);

			return actions;
		}

		// Gather installed
		Package[string] installed;
		installed[m_main.name] = m_main;
		foreach(ref Package p; m_dependencies) {
			auto pbase = p.basePackage;
			auto pexist = installed.get(pbase.name, null);
			if (pexist && pexist !is pbase){
				logError("The same package is referenced in different paths:");
				logError("  %s %s: %s", pexist.name, pexist.vers, pexist.path.toNativeString());
				logError("  %s %s: %s", pbase.name, pbase.vers, pbase.path.toNativeString());
				throw new Exception("Conflicting package multi-references.");
			}
			installed[pbase.name] = pbase;
		}

		// Check against installed and add install actions
		Action[] actions;
		foreach( string pkg, d; graph.needed() ) {
			auto basepkg = pkg.getSubPackagePath()[0];
			auto p = basepkg in installed;
			// TODO: auto update to latest head revision
			if(!p || (!d.dependency.matches(p.vers) && !d.dependency.matches(Version.MASTER))) {
				if(!p) logDiagnostic("Triggering installation of required package '"~basepkg~"', which is not installed.");
				else logDiagnostic("Triggering installation of required package '"~basepkg~"', which doesn't match the required versionh. Required '%s', available '%s'.", d.dependency, p.vers);
				actions ~= Action.install(basepkg, InstallLocation.userWide, d.dependency, d.packages);
			} else {
				logDiagnostic("Required package '"~basepkg~"' found with version '"~p.vers~"'");
				if( option & UpdateOptions.Upgrade )
					actions ~= Action.install(basepkg, InstallLocation.userWide, d.dependency, d.packages);
			}
		}

		return actions;
	}

	/// Outputs a JSON description of the project, including its deoendencies.
	void describe(ref Json dst, BuildPlatform platform, string config)
	{
		dst.mainPackage = m_main.name;

		auto configs = getPackageConfigs(platform, config);

		auto mp = Json.EmptyObject;
		m_main.describe(mp, platform, config);
		dst.packages = Json([mp]);

		foreach (dep; m_dependencies) {
			auto dp = Json.EmptyObject;
			dep.describe(dp, platform, configs[dep.name]);
			dst.packages = dst.packages.get!(Json[]) ~ dp;
		}
	}

	private bool gatherMissingDependencies(PackageSupplier[] packageSuppliers, DependencyGraph graph)
	{
		RequestedDependency[string] missing = graph.missing();
		RequestedDependency[string] oldMissing;
		while( missing.length > 0 ) {
			logDebug("Try to resolve %s", missing.keys);
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
			logDebug("There are %s packages missing.", missing.length);

			auto toLookup = missing;
			foreach(id, dep; graph.optional()) {
				enforce(id !in toLookup, "A missing dependency in the graph seems to be optional, which is an error.");
				toLookup[id] = dep;
			}

			foreach(string pkg, reqDep; toLookup) {
				if(!reqDep.dependency.valid()) {
					logDebug("Dependency to "~pkg~" is invalid. Trying to fix by modifying others.");
					continue;
				}
					
				auto ppath = pkg.split(":");

				// TODO: auto update and update interval by time
				logDebug("Adding package to graph: "~pkg);
				Package p = m_packageManager.getBestPackage(pkg, reqDep.dependency);
				if( p ) logDebug("Found installed package %s %s", pkg, p.ver);

				// Don't bother with not available optional packages.
				if( !p && reqDep.dependency.optional ) continue;
				
				// Try an already installed package first
				if( p && needsUpToDateCheck(p) ){
					logInfo("Triggering update of package %s", pkg);
					p = null;
				}

				if( !p ){
					try {
						logDiagnostic("Fechting package %s (%d suppliers registered)", pkg, packageSuppliers.length);
						foreach (ps; packageSuppliers) {
							try {
								auto sp = new Package(ps.getPackageDescription(ppath[0], reqDep.dependency));
								foreach (spn; ppath[1 .. $])
									sp = sp.getSubPackage(spn);
								p = sp;
								break;
							} catch (Exception e) {
								logDiagnostic("No metadata for %s: %s", ps.toString(), e.msg);
							}
						}
						enforce(p !is null, "Could not find package candidate for "~pkg~" "~reqDep.dependency.toString());
						markUpToDate(ppath[0]);
					}
					catch(Throwable e) {
						logError("Failed to retrieve metadata for package %s: %s", pkg, e.msg);
						logDiagnostic("Full error: %s", e.toString().sanitize());
					}
				}

				if(p)
					graph.insert(p);
			}
			graph.clearUnused();
			
			// As the dependencies are filled in starting from the outermost 
			// packages, resolving those conflicts won't happen (?).
			if(graph.conflicted().length > 0) {
				logInfo("There are conflicts in the dependency graph.");
				return false;
			}

			missing = graph.missing();
		}

		return true;
	}

	private bool needsUpToDateCheck(Package pack) {
		version (none) { // needs to be updated for the new package system (where no project local packages exist)
			try {
				auto time = m_json["dub"]["lastUpdate"].opt!(Json[string]).get(pack.name, Json("")).get!string;
				if( !time.length ) return true;
				return (Clock.currTime() - SysTime.fromISOExtString(time)) > dur!"days"(1);
			} catch(Exception t) return true;
		} else return false;
	}
		
	private void markUpToDate(string packageId) {
		logDebug("markUpToDate(%s)", packageId);
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
			logDebug("writeDubJson");
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
		return Action(Type.conflict, pkg, InstallLocation.userWide, dep, context);
	}

	static Action failure(string pkg, in Dependency dep, Dependency[string] context)
	{
		return Action(Type.failure, pkg, InstallLocation.userWide, dep, context);
	}

	private this(Type id, string pkg, InstallLocation location, in Dependency d, Dependency[string] issue)
	{
		this.type = id;
		this.packageId = pkg;
		this.location = location;
		this.vers = d;
		this.issuer = issue;
	}

	private this(Type id, Package pkg, Dependency[string] issue)
	{
		pack = pkg;
		type = id;
		packageId = pkg.name;
		vers = cast(immutable)Dependency(pkg.ver);
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
	Upgrade = 1<<1
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
	dst.addRequirements(settings.requirements);
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
				logDebug("Fixing relative path: %s ~ %s", project_path, p.toNativeString());
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
