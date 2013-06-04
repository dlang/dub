/**
	A package manager.

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff, Sönke Ludwig
*/
module dub.dub;

import dub.compilers.compiler;
import dub.dependency;
import dub.installation;
import dub.internal.std.process;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.url;
import dub.utils;
import dub.registry;
import dub.package_;
import dub.packagemanager;
import dub.packagesupplier;
import dub.project;
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



/// The default supplier for packages, which is the registry
/// hosted by vibed.org.
PackageSupplier[] defaultPackageSuppliers()
{
	Url url = Url.parse("http://registry.vibed.org/");
	logDebug("Using dub registry url '%s'", url);
	return [new RegistryPS(url)];
}

/// The Dub class helps in getting the applications
/// dependencies up and running. An instance manages one application.
class Dub {
	private {
		PackageManager m_packageManager;
		PackageSupplier[] m_packageSuppliers;
		Path m_cwd, m_tempPath;
		Path m_userDubPath, m_systemDubPath;
		Json m_systemConfig, m_userConfig;
		Path m_projectPath;
		Project m_project;
	}

	/// Initiales the package manager for the vibe application
	/// under root.
	this(PackageSupplier[] ps = defaultPackageSuppliers())
	{
		m_cwd = Path(getcwd());

		version(Windows){
			m_systemDubPath = Path(environment.get("ProgramData")) ~ "dub/";
			m_userDubPath = Path(environment.get("APPDATA")) ~ "dub/";
			m_tempPath = Path(environment.get("TEMP"));
		} else version(Posix){
			m_systemDubPath = Path("/var/lib/dub/");
			m_userDubPath = Path(environment.get("HOME")) ~ ".dub/";
			m_tempPath = Path("/tmp");
		}
		
		m_userConfig = jsonFromFile(m_userDubPath ~ "settings.json", true);
		m_systemConfig = jsonFromFile(m_systemDubPath ~ "settings.json", true);

		m_packageSuppliers = ps;
		m_packageManager = new PackageManager(m_userDubPath, m_systemDubPath);
		updatePackageSearchPath();
	}

	/// Returns the name listed in the package.json of the current
	/// application.
	@property string projectName() const { return m_project.name; }

	@property Path projectPath() const { return m_projectPath; }

	@property string[] configurations() const { return m_project.configurations; }

	@property inout(PackageManager) packageManager() inout { return m_packageManager; }

	void loadPackageFromCwd()
	{
		loadPackage(m_cwd);
	}

	void loadPackage(Path path)
	{
		m_projectPath = path;
		updatePackageSearchPath();
		m_project = new Project(m_packageManager, m_projectPath);
	}

	string getDefaultConfiguration(BuildPlatform platform) const { return m_project.getDefaultConfiguration(platform); }

	/// Performs installation and uninstallation as necessary for
	/// the application.
	/// @param options bit combination of UpdateOptions
	bool update(UpdateOptions options) {
		Action[] actions = m_project.determineActions(m_packageSuppliers, options);
		if( actions.length == 0 ) return true;

		logInfo("The following changes could be performed:");
		bool conflictedOrFailed = false;
		foreach(Action a; actions) {
			logInfo("%s %s %s, %s", capitalize(to!string(a.type)), a.packageId, a.vers, a.location);
			if( a.type == Action.Type.conflict || a.type == Action.Type.failure ) {
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
		// foreach(Action a	   ; filter!((Action a)        => a.type == Action.Type.Uninstall)(actions))
			// uninstall(a.packageId);
		// foreach(Action a; filter!((Action a) => a.type == Action.Type.InstallUpdate)(actions))
			// install(a.packageId, a.vers);
		foreach(Action a; actions)
			if(a.type == Action.Type.uninstall){
				assert(a.pack !is null, "No package specified for uninstall.");
				uninstall(a.pack);
			}
		foreach(Action a; actions)
			if(a.type == Action.Type.install)
				install(a.packageId, a.vers, a.location);

		if (!actions.empty) m_project.reinit();
		
		Action[] newActions = m_project.determineActions(m_packageSuppliers, 0);
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
	void generateProject(string ide, GeneratorSettings settings) {
		auto generator = createProjectGenerator(ide, m_project, m_packageManager);
		generator.generateProject(settings);
	}
	
	/// Creates a zip from the application.
	void createZip(string zipFile) {
		m_project.createZip(zipFile);
	}

	/// Outputs a JSON description of the project, including its deoendencies.
	void describeProject(BuildPlatform platform, string config)
	{
		auto dst = Json.EmptyObject;
		dst.configuration = config;
		dst.compiler = platform.compiler;
		dst.architecture = platform.architecture.serializeToJson();
		dst.platform = platform.platform.serializeToJson();

		m_project.describe(dst, platform, config);
		logInfo("%s", dst.toPrettyString());
	}


	/// Gets all installed packages as a "packageId" = "version" associative array
	string[string] installedPackages() const { return m_project.installedPackagesIDs(); }

	/// Installs the package matching the dependency into the application.
	Package install(string packageId, const Dependency dep, InstallLocation location = InstallLocation.projectLocal)
	{
		Json pinfo;
		PackageSupplier supplier;
		foreach(ps; m_packageSuppliers){
			try {
				pinfo = ps.getPackageDescription(packageId, dep);
				supplier = ps;
				break;
			} catch(Exception) {}
		}
		enforce(pinfo.type != Json.Type.Undefined, "No package "~packageId~" was found matching the dependency "~dep.toString());
		string ver = pinfo["version"].get!string;

		Path install_path;
		final switch (location) {
			case InstallLocation.local: install_path = m_cwd; break;
			case InstallLocation.projectLocal: install_path = m_project.mainPackage.path ~ ".dub/packages/"; break;
			case InstallLocation.userWide: install_path = m_userDubPath ~ "packages/"; break;
			case InstallLocation.systemWide: install_path = m_systemDubPath ~ "packages/"; break;
		}

		if( auto pack = m_packageManager.getPackage(packageId, ver, install_path) ){
			logInfo("Package %s %s (%s) is already installed with the latest version, skipping upgrade.",
				packageId, ver, install_path);
			return pack;
		}

		logInfo("Downloading %s %s...", packageId, ver);

		logDebug("Acquiring package zip file");
		auto dload = m_projectPath ~ ".dub/temp/downloads";
		auto tempfname = packageId ~ "-" ~ (ver.startsWith('~') ? ver[1 .. $] : ver) ~ ".zip";
		auto tempFile = m_tempPath ~ tempfname;
		string sTempFile = tempFile.toNativeString();
		if(exists(sTempFile)) remove(sTempFile);
		supplier.retrievePackage(tempFile, packageId, dep); // Q: continue on fail?
		scope(exit) remove(sTempFile);

		logInfo("Installing %s %s...", packageId, ver);
		auto clean_package_version = ver[ver.startsWith("~") ? 1 : 0 .. $];
		Path dstpath = install_path ~ (packageId ~ "-" ~ clean_package_version);

		return m_packageManager.install(tempFile, pinfo, dstpath);
	}

	/// Uninstalls a given package from the list of installed modules.
	/// @removeFromApplication: if true, this will also remove an entry in the
	/// list of dependencies in the application's package.json
	void uninstall(in Package pack)
	{
		logInfo("Uninstalling %s in %s", pack.name, pack.path.toNativeString());
		m_packageManager.uninstall(pack);
	}

	/// @see uninstall(string, string, InstallLocation)
	enum UninstallVersionWildcard = "*";

	/// This will uninstall a given package with a specified version from the 
	/// location.
	/// It will remove at most one package, unless @param version_ is 
	/// specified as wildcard "*". 
	/// @param package_id Package to be removed
	/// @param version_ Identifying a version or a wild card. An empty string
	/// may be passed into. In this case the package will be removed from the
	/// location, if there is only one version installed. This will throw an
	/// exception, if there are multiple versions installed.
	/// Note: as wildcard string only "*" is supported.
	/// @param location_
	void uninstall(string package_id, string version_, InstallLocation location_) {
		/+enforce(!package_id.empty);
		Package[] packages;
		const bool wildcardOrEmpty = version_ == UninstallVersionWildcard || version_.empty;
		if(location_ == InstallLocation.local) {
			// Try folder named like the package_id in the cwd.
			try {
				Package pack = new Package(InstallLocation.local, Path(package_id));
				if(!wildcardOrEmpty && to!string(pack.vers) != version_) {
					logError("Installed package is of different version, uninstallation aborted.");
					logError("Installed: %s, provided %s@", pack.vers, version_);
					throw new Exception("Found package locally, but the versions don't match!");
				}
				packages ~= pack;
			} catch {/* noop */}
		} else {
			// Use package manager
			foreach(pack; m_packageManager.getPackageIterator(package_id)){
				if( pack.installLocation == location_ && (wildcardOrEmpty || pack.vers == version_ )) {
					packages ~= pack;
				}
			}
		}

		if(packages.empty) {
			logError("Cannot find package to uninstall. (id:%s, version:%s, location:%s)", package_id, version_, location_);
			return;
		}

		if(version_.empty && packages.length > 1) {
			logError("Cannot uninstall package '%s', there multiple possibilities at location '%s'.", package_id, location_);
			logError("Installed versions:");
			foreach(pack; packages) 
				logError(to!string(pack.vers()));
			throw new Exception("Failed to uninstall package.");
		}

		logTrace("Uninstalling %s packages.", packages.length);
		foreach(pack; packages) {
			try {
				uninstall(pack);
				logInfo("Uninstalled %s, version %s.", package_id, pack.vers);
			}
			catch logError("Failed to uninstall %s, version %s. Continuing with other packages (if any).", package_id, pack.vers);
		}+/
	}

	void addLocalPackage(string path, string ver, bool system)
	{
		m_packageManager.addLocalPackage(makeAbsolute(path), Version(ver), system ? LocalPackageType.system : LocalPackageType.user);
	}

	void removeLocalPackage(string path, bool system)
	{
		m_packageManager.removeLocalPackage(makeAbsolute(path), system ? LocalPackageType.system : LocalPackageType.user);
	}

	void addSearchPath(string path, bool system)
	{
		m_packageManager.addSearchPath(makeAbsolute(path), system ? LocalPackageType.system : LocalPackageType.user);
	}

	void removeSearchPath(string path, bool system)
	{
		m_packageManager.removeSearchPath(makeAbsolute(path), system ? LocalPackageType.system : LocalPackageType.user);
	}

	void createEmptyPackage(Path path)
	{
		if( !path.absolute() ) path = m_cwd ~ path;
		path.normalize();

		//Check to see if a target directory needs to be created
		if( !path.empty ){
			if( !existsFile(path) )
				createDirectory(path);
		} 

		//Make sure we do not overwrite anything accidentally
		if( existsFile(path ~ PackageJsonFilename) ||
			existsFile(path ~ "source") ||
			existsFile(path ~ "views") ||
			existsFile(path ~ "public") )
		{
			throw new Exception("The current directory is not empty.\n");
		}

		//raw strings must be unindented. 
		immutable packageJson = 
`{
	"name": "`~(path.empty ? "my-project" : path.head.toString())~`",
	"description": "An example project skeleton",
	"homepage": "http://example.org",
	"copyright": "Copyright © 2000, Your Name",
	"authors": [
		"Your Name"
	],
	"dependencies": {
	}
}
`;
		immutable appFile =
`import std.stdio;

void main()
{ 
	writeln("Edit source/app.d to start your project.");
}
`;

		//Create the common directories.
		createDirectory(path ~ "source");
		createDirectory(path ~ "views");
		createDirectory(path ~ "public");

		//Create the common files. 
		openFile(path ~ PackageJsonFilename, FileMode.Append).write(packageJson);
		openFile(path ~ "source/app.d", FileMode.Append).write(appFile);     

		//Act smug to the user. 
		logInfo("Successfully created an empty project in '"~path.toNativeString()~"'.");
	}

	void runDdox()
	{
		auto ddox_pack = m_packageManager.getBestPackage("ddox", ">=0.0.0");
		if (!ddox_pack) ddox_pack = m_packageManager.getBestPackage("ddox", "~master");
		if (!ddox_pack) {
			logInfo("DDOX is not installed, performing user wide installation.");
			ddox_pack = install("ddox", new Dependency(">=0.0.0"), InstallLocation.userWide);
		}

		version(Windows) auto ddox_exe = "ddox.exe";
		else auto ddox_exe = "ddox";

		if( !existsFile(ddox_pack.path~ddox_exe) ){
			logInfo("DDOX in %s is not built, performing build now.", ddox_pack.path.toNativeString());

			auto ddox_dub = new Dub(m_packageSuppliers);
			ddox_dub.loadPackage(ddox_pack.path);

			GeneratorSettings settings;
			settings.compilerBinary = "dmd";
			settings.config = "application";
			settings.compiler = getCompiler(settings.compilerBinary);
			settings.platform = settings.compiler.determinePlatform(settings.buildSettings, settings.compilerBinary);
			settings.buildType = "debug";
			ddox_dub.generateProject("build", settings);

			//runCommands(["cd "~ddox_pack.path.toNativeString()~" && dub build -v"]);
		}

		auto p = ddox_pack.path;
		p.endsWithSlash = true;
		auto dub_path = p.toNativeString();

		string[] commands;
		string[] filterargs = m_project.mainPackage.info.ddoxFilterArgs.dup;
		if (filterargs.empty) filterargs = ["--min-protection=Protected", "--only-documented"];
		commands ~= dub_path~"ddox filter "~filterargs.join(" ")~" docs.json";
		commands ~= dub_path~"ddox generate-html --navigation-type=ModuleTree docs.json docs";
		version(Windows) commands ~= "xcopy /S /D "~dub_path~"public\\* docs\\";
		else commands ~= "cp -r "~dub_path~"public/* docs/";
		runCommands(commands);
	}

	private void updatePackageSearchPath()
	{
		auto p = environment.get("DUBPATH");
		Path[] paths;
		version(Windows) if (p.length) paths ~= p.split(":").map!(p => Path(p))().array();
		else if (p.length) paths ~= p.split(";").map!(p => Path(p))().array();
		m_packageManager.searchPath = paths;
	}

	private Path makeAbsolute(Path p) const { return p.absolute ? p : m_cwd ~ p; }
	private Path makeAbsolute(string p) const { return makeAbsolute(Path(p)); }
}
