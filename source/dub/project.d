/**
	Representing a full project, with a root Package and several dependencies.

	Copyright: © 2012-2013 Matthias Dondorff, 2012-2016 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff, Sönke Ludwig
*/
module dub.project;

import dub.compilers.compiler;
import dub.dependency;
import dub.description;
import dub.generators.generator;
import dub.internal.utils;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.path;
import dub.package_;
import dub.packagemanager;
import dub.recipe.selection;

import configy.Read;

import std.algorithm;
import std.array;
import std.conv : to;
import std.datetime;
import std.encoding : sanitize;
import std.exception : enforce;
import std.string;

/**
	Represents a full project, a root package with its dependencies and package
	selection.

	All dependencies must be available locally so that the package dependency
	graph can be built. Use `Project.reinit` if necessary for reloading
	dependencies after more packages are available.
*/
class Project {
	private {
		PackageManager m_packageManager;
		Package m_rootPackage;
		Package[] m_dependencies;
		Package[][Package] m_dependees;
		SelectedVersions m_selections;
		string[] m_missingDependencies;
		string[string] m_overriddenConfigs;
	}

	/** Loads a project.

		Params:
			package_manager = Package manager instance to use for loading
				dependencies
			project_path = Path of the root package to load
			pack = An existing `Package` instance to use as the root package
	*/
	this(PackageManager package_manager, NativePath project_path)
	{
		Package pack;
		auto packageFile = Package.findPackageFile(project_path);
		if (packageFile.empty) {
			logWarn("There was no package description found for the application in '%s'.", project_path.toNativeString());
			pack = new Package(PackageRecipe.init, project_path);
		} else {
			pack = package_manager.getOrLoadPackage(project_path, packageFile);
		}

		this(package_manager, pack);
	}

	/// ditto
	this(PackageManager package_manager, Package pack)
	{
		m_packageManager = package_manager;
		m_rootPackage = pack;

		auto selverfile = (m_rootPackage.path ~ SelectedVersions.defaultFile).toNativeString();
		if (existsFile(selverfile)) {
			auto selected = parseConfigFileSimple!Selected(selverfile);
			enforce(!selected.isNull(), "Could not read '" ~ selverfile ~ "'");
			m_selections = new SelectedVersions(selected.get());
		} else m_selections = new SelectedVersions;

		reinit();
	}

	/** List of all resolved dependencies.

		This includes all direct and indirect dependencies of all configurations
		combined. Optional dependencies that were not chosen are not included.
	*/
	@property const(Package[]) dependencies() const { return m_dependencies; }

	/// The root package of the project.
	@property inout(Package) rootPackage() inout { return m_rootPackage; }

	/// The versions to use for all dependencies. Call reinit() after changing these.
	@property inout(SelectedVersions) selections() inout { return m_selections; }

	/// Package manager instance used by the project.
	@property inout(PackageManager) packageManager() inout { return m_packageManager; }

	/** Determines if all dependencies necessary to build have been collected.

		If this function returns `false`, it may be necessary to add more entries
		to `selections`, or to use `Dub.upgrade` to automatically select all
		missing dependencies.
	*/
	bool hasAllDependencies() const { return m_missingDependencies.length == 0; }

	/// Sorted list of missing dependencies.
	string[] missingDependencies() { return m_missingDependencies; }

	/** Allows iteration of the dependency tree in topological order
	*/
	int delegate(int delegate(ref Package)) getTopologicalPackageList(bool children_first = false, Package root_package = null, string[string] configs = null)
	{
		// ugly way to avoid code duplication since inout isn't compatible with foreach type inference
		return cast(int delegate(int delegate(ref Package)))(cast(const)this).getTopologicalPackageList(children_first, root_package, configs);
	}
	/// ditto
	int delegate(int delegate(ref const Package)) getTopologicalPackageList(bool children_first = false, in Package root_package = null, string[string] configs = null)
	const {
		const(Package) rootpack = root_package ? root_package : m_rootPackage;

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

				PackageDependency[] deps;
				if (!cfg.length) deps = p.getAllDependencies();
				else {
					auto depmap = p.getDependencies(cfg);
					deps = depmap.byKey.map!(k => PackageDependency(k, depmap[k])).array;
				}
				deps.sort!((a, b) => a.name < b.name);

				foreach (d; deps) {
					auto dependency = getDependency(d.name, true);
					assert(dependency || d.spec.optional,
						format("Non-optional dependency '%s' of '%s' not found in dependency tree!?.", d.name, p.name));
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

	/** Retrieves a particular dependency by name.

		Params:
			name = (Qualified) package name of the dependency
			is_optional = If set to true, will return `null` for unsatisfiable
				dependencies instead of throwing an exception.
	*/
	inout(Package) getDependency(string name, bool is_optional)
	inout {
		foreach(dp; m_dependencies)
			if( dp.name == name )
				return dp;
		if (!is_optional) throw new Exception("Unknown dependency: "~name);
		else return null;
	}

	/** Returns the name of the default build configuration for the specified
		target platform.

		Params:
			platform = The target build platform
			allow_non_library_configs = If set to true, will use the first
				possible configuration instead of the first "executable"
				configuration.
	*/
	string getDefaultConfiguration(in BuildPlatform platform, bool allow_non_library_configs = true)
	const {
		auto cfgs = getPackageConfigs(platform, null, allow_non_library_configs);
		return cfgs[m_rootPackage.name];
	}

	/** Overrides the configuration chosen for a particular package in the
		dependency graph.

		Setting a certain configuration here is equivalent to removing all
		but one configuration from the package.

		Params:
			package_ = The package for which to force selecting a certain
				dependency
			config = Name of the configuration to force
	*/
	void overrideConfiguration(string package_, string config)
	{
		auto p = getDependency(package_, true);
		enforce(p !is null,
			format("Package '%s', marked for configuration override, is not present in dependency graph.", package_));
		enforce(p.configurations.canFind(config),
			format("Package '%s' does not have a configuration named '%s'.", package_, config));
		m_overriddenConfigs[package_] = config;
	}

	/** Adds a test runner configuration for the root package.

		Params:
			generate_main = Whether to generate the main.d file
			base_config = Optional base configuration
			custom_main_file = Optional path to file with custom main entry point

		Returns:
			Name of the added test runner configuration, or null for base configurations with target type `none`
	*/
	string addTestRunnerConfiguration(in GeneratorSettings settings, bool generate_main = true, string base_config = "", NativePath custom_main_file = NativePath())
	{
		if (base_config.length == 0) {
			// if a custom main file was given, favor the first library configuration, so that it can be applied
			if (!custom_main_file.empty) base_config = getDefaultConfiguration(settings.platform, false);
			// else look for a "unittest" configuration
			if (!base_config.length && rootPackage.configurations.canFind("unittest")) base_config = "unittest";
			// if not found, fall back to the first "library" configuration
			if (!base_config.length) base_config = getDefaultConfiguration(settings.platform, false);
			// if still nothing found, use the first executable configuration
			if (!base_config.length) base_config = getDefaultConfiguration(settings.platform, true);
		}

		BuildSettings lbuildsettings = settings.buildSettings.dup;
		addBuildSettings(lbuildsettings, settings, base_config, null, true);

		if (lbuildsettings.targetType == TargetType.none) {
			logInfo(`Configuration '%s' has target type "none". Skipping test runner configuration.`, base_config);
			return null;
		}

		if (lbuildsettings.targetType == TargetType.executable && base_config == "unittest") {
			if (!custom_main_file.empty) logWarn("Ignoring custom main file.");
			return base_config;
		}

		if (lbuildsettings.sourceFiles.empty) {
			logInfo(`No source files found in configuration '%s'. Falling back to default configuration for test runner.`, base_config);
			if (!custom_main_file.empty) logWarn("Ignoring custom main file.");
			return getDefaultConfiguration(settings.platform);
		}

		const config = format("%s-test-%s", rootPackage.name.replace(".", "-").replace(":", "-"), base_config);
		logInfo(`Generating test runner configuration '%s' for '%s' (%s).`, config, base_config, lbuildsettings.targetType);

		BuildSettingsTemplate tcinfo = rootPackage.recipe.getConfiguration(base_config).buildSettings.dup;
		tcinfo.targetType = TargetType.executable;

		// set targetName unless specified explicitly in unittest base configuration
		if (tcinfo.targetName.empty || base_config != "unittest")
			tcinfo.targetName = config;

		auto mainfil = tcinfo.mainSourceFile;
		if (!mainfil.length) mainfil = rootPackage.recipe.buildSettings.mainSourceFile;

		string custommodname;
		if (!custom_main_file.empty) {
			import std.path;
			tcinfo.sourceFiles[""] ~= custom_main_file.relativeTo(rootPackage.path).toNativeString();
			tcinfo.importPaths[""] ~= custom_main_file.parentPath.toNativeString();
			custommodname = custom_main_file.head.name.baseName(".d");
		}

		// prepare the list of tested modules

		string[] import_modules;
		if (settings.single)
			lbuildsettings.importPaths ~= NativePath(mainfil).parentPath.toNativeString;
		bool firstTimePackage = true;
		foreach (file; lbuildsettings.sourceFiles) {
			if (file.endsWith(".d")) {
				auto fname = NativePath(file).head.name;
				NativePath msf = NativePath(mainfil);
				if (msf.absolute)
					msf = msf.relativeTo(rootPackage.path);
				if (!settings.single && NativePath(file).relativeTo(rootPackage.path) == msf) {
					logWarn("Excluding main source file %s from test.", mainfil);
					tcinfo.excludedSourceFiles[""] ~= mainfil;
					continue;
				}
				if (fname == "package.d") {
					if (firstTimePackage) {
						firstTimePackage = false;
						logDiagnostic("Excluding package.d file from test due to https://issues.dlang.org/show_bug.cgi?id=11847");
					}
					continue;
				}
				import_modules ~= dub.internal.utils.determineModuleName(lbuildsettings, NativePath(file), rootPackage.path);
			}
		}

		NativePath mainfile;
		if (settings.tempBuild)
			mainfile = getTempFile("dub_test_root", ".d");
		else {
			import dub.generators.build : computeBuildName;
			mainfile = rootPackage.path ~ format(".dub/code/%s/dub_test_root.d", computeBuildName(config, settings, import_modules));
		}

		auto escapedMainFile = mainfile.toNativeString().replace("$", "$$");
		tcinfo.sourceFiles[""] ~= escapedMainFile;
		tcinfo.mainSourceFile = escapedMainFile;
		if (!settings.tempBuild) {
			// add the directory containing dub_test_root.d to the import paths
			tcinfo.importPaths[""] ~= NativePath(escapedMainFile).parentPath.toNativeString();
		}

		if (generate_main && (settings.force || !existsFile(mainfile))) {
			import std.file : mkdirRecurse;
			mkdirRecurse(mainfile.parentPath.toNativeString());

			auto fil = openFile(mainfile, FileMode.createTrunc);
			scope(exit) fil.close();
			fil.write("module dub_test_root;\n");
			fil.write("import std.typetuple;\n");
			foreach (mod; import_modules) fil.write(format("static import %s;\n", mod));
			fil.write("alias allModules = TypeTuple!(");
			foreach (i, mod; import_modules) {
				if (i > 0) fil.write(", ");
				fil.write(mod);
			}
			fil.write(");\n");
			if (custommodname.length) {
				fil.write(format("import %s;\n", custommodname));
			} else {
				fil.write(q{
import core.runtime;

void main() {
	version (D_Coverage) {
	} else {
		import std.stdio : writeln;
		writeln("All unit tests have been run successfully.");
	}
}
shared static this() {
	version (Have_tested) {
		import tested;
		import core.runtime;
		import std.exception;
		Runtime.moduleUnitTester = () => true;
		enforce(runUnitTests!allModules(new ConsoleTestResultWriter), "Unit tests failed.");
	}
}
					});
			}
		}

		rootPackage.recipe.configurations ~= ConfigurationInfo(config, tcinfo);

		return config;
	}

	/** Performs basic validation of various aspects of the package.

		This will emit warnings to `stderr` if any discouraged names or
		dependency patterns are found.
	*/
	void validate()
	{
		// some basic package lint
		m_rootPackage.warnOnSpecialCompilerFlags();
		string nameSuggestion() {
			string ret;
			ret ~= `Please modify the "name" field in %s accordingly.`.format(m_rootPackage.recipePath.toNativeString());
			if (!m_rootPackage.recipe.buildSettings.targetName.length) {
				if (m_rootPackage.recipePath.head.name.endsWith(".sdl")) {
					ret ~= ` You can then add 'targetName "%s"' to keep the current executable name.`.format(m_rootPackage.name);
				} else {
					ret ~= ` You can then add '"targetName": "%s"' to keep the current executable name.`.format(m_rootPackage.name);
				}
			}
			return ret;
		}
		if (m_rootPackage.name != m_rootPackage.name.toLower()) {
			logWarn(`WARNING: DUB package names should always be lower case. %s`, nameSuggestion());
		} else if (!m_rootPackage.recipe.name.all!(ch => ch >= 'a' && ch <= 'z' || ch >= '0' && ch <= '9' || ch == '-' || ch == '_')) {
			logWarn(`WARNING: DUB package names may only contain alphanumeric characters, `
				~ `as well as '-' and '_'. %s`, nameSuggestion());
		}
		enforce(!m_rootPackage.name.canFind(' '), "Aborting due to the package name containing spaces.");

		foreach (d; m_rootPackage.getAllDependencies())
			if (d.spec.isExactVersion && d.spec.version_.isBranch && d.spec.repository.empty) {
				logWarn("WARNING: A deprecated branch based version specification is used "
					~ "for the dependency %s. Please use numbered versions instead. Also "
					~ "note that you can still use the %s file to override a certain "
					~ "dependency to use a branch instead.",
					d.name, SelectedVersions.defaultFile);
			}

		// search for orphan sub configurations
		void warnSubConfig(string pack, string config) {
			logWarn("The sub configuration directive \"%s\" -> \"%s\" "
				~ "references a package that is not specified as a dependency "
				~ "and will have no effect.", pack, config);
		}
		void checkSubConfig(string pack, string config) {
			auto p = getDependency(pack, true);
			if (p && !p.configurations.canFind(config)) {
				logWarn("The sub configuration directive \"%s\" -> \"%s\" "
					~ "references a configuration that does not exist.",
					pack, config);
			}
		}
		auto globalbs = m_rootPackage.getBuildSettings();
		foreach (p, c; globalbs.subConfigurations) {
			if (p !in globalbs.dependencies) warnSubConfig(p, c);
			else checkSubConfig(p, c);
		}
		foreach (c; m_rootPackage.configurations) {
			auto bs = m_rootPackage.getBuildSettings(c);
			foreach (p, subConf; bs.subConfigurations) {
				if (p !in bs.dependencies && p !in globalbs.dependencies)
					warnSubConfig(p, subConf);
				else checkSubConfig(p, subConf);
			}
		}

		// check for version specification mismatches
		bool[Package] visited;
		void validateDependenciesRec(Package pack) {
			// perform basic package linting
			pack.simpleLint();

			foreach (d; pack.getAllDependencies()) {
				auto basename = getBasePackageName(d.name);
				if (m_selections.hasSelectedVersion(basename)) {
					auto selver = m_selections.getSelectedVersion(basename);
					if (d.spec.merge(selver) == Dependency.invalid) {
						logWarn("Selected package %s %s does not match the dependency specification %s in package %s. Need to \"dub upgrade\"?",
							basename, selver, d.spec, pack.name);
					}
				}

				auto deppack = getDependency(d.name, true);
				if (deppack in visited) continue;
				visited[deppack] = true;
				if (deppack) validateDependenciesRec(deppack);
			}
		}
		validateDependenciesRec(m_rootPackage);
	}

	/// Reloads dependencies.
	void reinit()
	{
		m_dependencies = null;
		m_missingDependencies = [];
		m_packageManager.refresh(false);

		Package resolveSubPackage(Package p, string subname, bool silentFail) {
			return subname.length ? m_packageManager.getSubPackage(p, subname, silentFail) : p;
		}

		void collectDependenciesRec(Package pack, int depth = 0)
		{
			auto indent = replicate("  ", depth);
			logDebug("%sCollecting dependencies for %s", indent, pack.name);
			indent ~= "  ";

			foreach (dep; pack.getAllDependencies()) {
				Dependency vspec = dep.spec;
				Package p;

				auto basename = getBasePackageName(dep.name);
				auto subname = getSubPackageName(dep.name);

				// non-optional and optional-default dependencies (if no selections file exists)
				// need to be satisfied
				bool is_desired = !vspec.optional || m_selections.hasSelectedVersion(basename) || (vspec.default_ && m_selections.bare);

				if (dep.name == m_rootPackage.basePackage.name) {
					vspec = Dependency(m_rootPackage.version_);
					p = m_rootPackage.basePackage;
				} else if (basename == m_rootPackage.basePackage.name) {
					vspec = Dependency(m_rootPackage.version_);
					try p = m_packageManager.getSubPackage(m_rootPackage.basePackage, subname, false);
					catch (Exception e) {
						logDiagnostic("%sError getting sub package %s: %s", indent, dep.name, e.msg);
						if (is_desired) m_missingDependencies ~= dep.name;
						continue;
					}
				} else if (m_selections.hasSelectedVersion(basename)) {
					vspec = m_selections.getSelectedVersion(basename);
					if (!vspec.path.empty) {
						auto path = vspec.path;
						if (!path.absolute) path = m_rootPackage.path ~ path;
						p = m_packageManager.getOrLoadPackage(path, NativePath.init, true);
						p = resolveSubPackage(p, subname, true);
					} else if (!vspec.repository.empty) {
						p = m_packageManager.loadSCMPackage(basename, vspec.repository);
						p = resolveSubPackage(p, subname, true);
					} else {
						p = m_packageManager.getBestPackage(dep.name, vspec);
					}
				} else if (m_dependencies.canFind!(d => getBasePackageName(d.name) == basename)) {
					auto idx = m_dependencies.countUntil!(d => getBasePackageName(d.name) == basename);
					auto bp = m_dependencies[idx].basePackage;
					vspec = Dependency(bp.path);
					p = resolveSubPackage(bp, subname, false);
				} else {
					logDiagnostic("%sVersion selection for dependency %s (%s) of %s is missing.",
						indent, basename, dep.name, pack.name);
				}

				// We didn't find the package
				if (p is null)
				{
					if (!vspec.repository.empty) {
						p = m_packageManager.loadSCMPackage(basename, vspec.repository);
						resolveSubPackage(p, subname, false);
					} else if (!vspec.path.empty && is_desired) {
						NativePath path = vspec.path;
						if (!path.absolute) path = pack.path ~ path;
						logDiagnostic("%sAdding local %s in %s", indent, dep.name, path);
						p = m_packageManager.getOrLoadPackage(path, NativePath.init, true);
						if (p.parentPackage !is null) {
							logWarn("%sSub package %s must be referenced using the path to it's parent package.", indent, dep.name);
							p = p.parentPackage;
						}
						p = resolveSubPackage(p, subname, false);
						enforce(p.name == dep.name,
							format("Path based dependency %s is referenced with a wrong name: %s vs. %s",
								path.toNativeString(), dep.name, p.name));
					} else {
						logDiagnostic("%sMissing dependency %s %s of %s", indent, dep.name, vspec, pack.name);
						if (is_desired) m_missingDependencies ~= dep.name;
						continue;
					}
				}

				if (!m_dependencies.canFind(p)) {
					logDiagnostic("%sFound dependency %s %s", indent, dep.name, vspec.toString());
					m_dependencies ~= p;
					if (basename == m_rootPackage.basePackage.name)
						p.warnOnSpecialCompilerFlags();
					collectDependenciesRec(p, depth+1);
				}

				m_dependees[p] ~= pack;
				//enforce(p !is null, "Failed to resolve dependency "~dep.name~" "~vspec.toString());
			}
		}
		collectDependenciesRec(m_rootPackage);
		m_missingDependencies.sort();
	}

	/// Returns the name of the root package.
	@property string name() const { return m_rootPackage ? m_rootPackage.name : "app"; }

	/// Returns the names of all configurations of the root package.
	@property string[] configurations() const { return m_rootPackage.configurations; }

	/// Returns the names of all built-in and custom build types of the root package.
	/// The default built-in build type is the first item in the list.
	@property string[] builds() const { return builtinBuildTypes ~ m_rootPackage.customBuildTypes; }

	/// Returns a map with the configuration for all packages in the dependency tree.
	string[string] getPackageConfigs(in BuildPlatform platform, string config, bool allow_non_library = true)
	const {
		struct Vertex { string pack, config; }
		struct Edge { size_t from, to; }

		Vertex[] configs;
		Edge[] edges;
		string[][string] parents;
		parents[m_rootPackage.name] = null;
		foreach (p; getTopologicalPackageList())
			foreach (d; p.getAllDependencies())
				parents[d.name] ~= p.name;

		size_t createConfig(string pack, string config) {
			foreach (i, v; configs)
				if (v.pack == pack && v.config == config)
					return i;
			assert(pack !in m_overriddenConfigs || config == m_overriddenConfigs[pack]);
			logDebug("Add config %s %s", pack, config);
			configs ~= Vertex(pack, config);
			return configs.length-1;
		}

		bool haveConfig(string pack, string config) {
			return configs.any!(c => c.pack == pack && c.config == config);
		}

		size_t createEdge(size_t from, size_t to) {
			auto idx = edges.countUntil(Edge(from, to));
			if (idx >= 0) return idx;
			logDebug("Including %s %s -> %s %s", configs[from].pack, configs[from].config, configs[to].pack, configs[to].config);
			edges ~= Edge(from, to);
			return edges.length-1;
		}

		void removeConfig(size_t i) {
			logDebug("Eliminating config %s for %s", configs[i].config, configs[i].pack);
			auto had_dep_to_pack = new bool[configs.length];
			auto still_has_dep_to_pack = new bool[configs.length];

			edges = edges.filter!((e) {
					if (e.to == i) {
						had_dep_to_pack[e.from] = true;
						return false;
					} else if (configs[e.to].pack == configs[i].pack) {
						still_has_dep_to_pack[e.from] = true;
					}
					if (e.from == i) return false;
					return true;
				}).array;

			configs[i] = Vertex.init; // mark config as removed

			// also remove any configs that cannot be satisfied anymore
			foreach (j; 0 .. configs.length)
				if (j != i && had_dep_to_pack[j] && !still_has_dep_to_pack[j])
					removeConfig(j);
		}

		bool isReachable(string pack, string conf) {
			if (pack == configs[0].pack && configs[0].config == conf) return true;
			foreach (e; edges)
				if (configs[e.to].pack == pack && configs[e.to].config == conf)
					return true;
			return false;
			//return (pack == configs[0].pack && conf == configs[0].config) || edges.canFind!(e => configs[e.to].pack == pack && configs[e.to].config == config);
		}

		bool isReachableByAllParentPacks(size_t cidx) {
			bool[string] r;
			foreach (p; parents[configs[cidx].pack]) r[p] = false;
			foreach (e; edges) {
				if (e.to != cidx) continue;
				if (auto pp = configs[e.from].pack in r) *pp = true;
			}
			foreach (bool v; r) if (!v) return false;
			return true;
		}

		string[] allconfigs_path;

		void determineDependencyConfigs(in Package p, string c)
		{
			string[][string] depconfigs;
			foreach (d; p.getAllDependencies()) {
				auto dp = getDependency(d.name, true);
				if (!dp) continue;

				string[] cfgs;
				if (auto pc = dp.name in m_overriddenConfigs) cfgs = [*pc];
				else {
					auto subconf = p.getSubConfiguration(c, dp, platform);
					if (!subconf.empty) cfgs = [subconf];
					else cfgs = dp.getPlatformConfigurations(platform);
				}
				cfgs = cfgs.filter!(c => haveConfig(d.name, c)).array;

				// if no valid configuration was found for a dependency, don't include the
				// current configuration
				if (!cfgs.length) {
					logDebug("Skip %s %s (missing configuration for %s)", p.name, c, dp.name);
					return;
				}
				depconfigs[d.name] = cfgs;
			}

			// add this configuration to the graph
			size_t cidx = createConfig(p.name, c);
			foreach (d; p.getAllDependencies())
				foreach (sc; depconfigs.get(d.name, null))
					createEdge(cidx, createConfig(d.name, sc));
		}

		// create a graph of all possible package configurations (package, config) -> (subpackage, subconfig)
		void determineAllConfigs(in Package p)
		{
			auto idx = allconfigs_path.countUntil(p.name);
			enforce(idx < 0, format("Detected dependency cycle: %s", (allconfigs_path[idx .. $] ~ p.name).join("->")));
			allconfigs_path ~= p.name;
			scope (exit) allconfigs_path.length--;

			// first, add all dependency configurations
			foreach (d; p.getAllDependencies) {
				auto dp = getDependency(d.name, true);
				if (!dp) continue;
				determineAllConfigs(dp);
			}

			// for each configuration, determine the configurations usable for the dependencies
			if (auto pc = p.name in m_overriddenConfigs)
				determineDependencyConfigs(p, *pc);
			else
				foreach (c; p.getPlatformConfigurations(platform, p is m_rootPackage && allow_non_library))
					determineDependencyConfigs(p, c);
		}
		if (config.length) createConfig(m_rootPackage.name, config);
		determineAllConfigs(m_rootPackage);

		// successively remove configurations until only one configuration per package is left
		bool changed;
		do {
			// remove all configs that are not reachable by all parent packages
			changed = false;
			foreach (i, ref c; configs) {
				if (c == Vertex.init) continue; // ignore deleted configurations
				if (!isReachableByAllParentPacks(i)) {
					logDebug("%s %s NOT REACHABLE by all of (%s):", c.pack, c.config, parents[c.pack]);
					removeConfig(i);
					changed = true;
				}
			}

			// when all edges are cleaned up, pick one package and remove all but one config
			if (!changed) {
				foreach (p; getTopologicalPackageList()) {
					size_t cnt = 0;
					foreach (i, ref c; configs)
						if (c.pack == p.name && ++cnt > 1) {
							logDebug("NON-PRIMARY: %s %s", c.pack, c.config);
							removeConfig(i);
						}
					if (cnt > 1) {
						changed = true;
						break;
					}
				}
			}
		} while (changed);

		// print out the resulting tree
		foreach (e; edges) logDebug("    %s %s -> %s %s", configs[e.from].pack, configs[e.from].config, configs[e.to].pack, configs[e.to].config);

		// return the resulting configuration set as an AA
		string[string] ret;
		foreach (c; configs) {
			if (c == Vertex.init) continue; // ignore deleted configurations
			assert(ret.get(c.pack, c.config) == c.config, format("Conflicting configurations for %s found: %s vs. %s", c.pack, c.config, ret[c.pack]));
			logDebug("Using configuration '%s' for %s", c.config, c.pack);
			ret[c.pack] = c.config;
		}

		// check for conflicts (packages missing in the final configuration graph)
		void checkPacksRec(in Package pack) {
			auto pc = pack.name in ret;
			enforce(pc !is null, "Could not resolve configuration for package "~pack.name);
			foreach (p, dep; pack.getDependencies(*pc)) {
				auto deppack = getDependency(p, dep.optional);
				if (deppack) checkPacksRec(deppack);
			}
		}
		checkPacksRec(m_rootPackage);

		return ret;
	}

	/**
	 * Fills `dst` with values from this project.
	 *
	 * `dst` gets initialized according to the given platform and config.
	 *
	 * Params:
	 *   dst = The BuildSettings struct to fill with data.
	 *   gsettings = The generator settings to retrieve the values for.
	 *   config = Values of the given configuration will be retrieved.
	 *   root_package = If non null, use it instead of the project's real root package.
	 *   shallow = If true, collects only build settings for the main package (including inherited settings) and doesn't stop on target type none and sourceLibrary.
	 */
	void addBuildSettings(ref BuildSettings dst, in GeneratorSettings gsettings, string config, in Package root_package = null, bool shallow = false)
	const {
		import dub.internal.utils : stripDlangSpecialChars;

		auto configs = getPackageConfigs(gsettings.platform, config);

		foreach (pkg; this.getTopologicalPackageList(false, root_package, configs)) {
			auto pkg_path = pkg.path.toNativeString();
			dst.addVersions(["Have_" ~ stripDlangSpecialChars(pkg.name)]);

			assert(pkg.name in configs, "Missing configuration for "~pkg.name);
			logDebug("Gathering build settings for %s (%s)", pkg.name, configs[pkg.name]);

			auto psettings = pkg.getBuildSettings(gsettings.platform, configs[pkg.name]);
			if (psettings.targetType != TargetType.none) {
				if (shallow && pkg !is m_rootPackage)
					psettings.sourceFiles = null;
				processVars(dst, this, pkg, psettings, gsettings);
				if (!gsettings.single && psettings.importPaths.empty)
					logWarn(`Package %s (configuration "%s") defines no import paths, use {"importPaths": [...]} or the default package directory structure to fix this.`, pkg.name, configs[pkg.name]);
				if (psettings.mainSourceFile.empty && pkg is m_rootPackage && psettings.targetType == TargetType.executable)
					logWarn(`Executable configuration "%s" of package %s defines no main source file, this may cause certain build modes to fail. Add an explicit "mainSourceFile" to the package description to fix this.`, configs[pkg.name], pkg.name);
			}
			if (pkg is m_rootPackage) {
				if (!shallow) {
					enforce(psettings.targetType != TargetType.none, "Main package has target type \"none\" - stopping build.");
					enforce(psettings.targetType != TargetType.sourceLibrary, "Main package has target type \"sourceLibrary\" which generates no target - stopping build.");
				}
				dst.targetType = psettings.targetType;
				dst.targetPath = psettings.targetPath;
				dst.targetName = psettings.targetName;
				if (!psettings.workingDirectory.empty)
					dst.workingDirectory = processVars(psettings.workingDirectory, this, pkg, gsettings, true, [dst.environments, dst.buildEnvironments]);
				if (psettings.mainSourceFile.length)
					dst.mainSourceFile = processVars(psettings.mainSourceFile, this, pkg, gsettings, true, [dst.environments, dst.buildEnvironments]);
			}
		}

		// always add all version identifiers of all packages
		foreach (pkg; this.getTopologicalPackageList(false, null, configs)) {
			auto psettings = pkg.getBuildSettings(gsettings.platform, configs[pkg.name]);
			dst.addVersions(psettings.versions);
		}
	}

	/** Fills `dst` with build settings specific to the given build type.

		Params:
			dst = The `BuildSettings` instance to add the build settings to
			gsettings = Target generator settings
			build_type = Name of the build type
			for_root_package = Selects if the build settings are for the root
				package or for one of the dependencies. Unittest flags will
				only be added to the root package.
	*/
	void addBuildTypeSettings(ref BuildSettings dst, in GeneratorSettings gsettings, bool for_root_package = true)
	{
		bool usedefflags = !(dst.requirements & BuildRequirement.noDefaultFlags);
		if (usedefflags) {
			BuildSettings btsettings;
			m_rootPackage.addBuildTypeSettings(btsettings, gsettings.platform, gsettings.buildType);

			if (!for_root_package) {
				// don't propagate unittest switch to dependencies, as dependent
				// unit tests aren't run anyway and the additional code may
				// cause linking to fail on Windows (issue #640)
				btsettings.removeOptions(BuildOption.unittests);
			}

			processVars(dst, this, m_rootPackage, btsettings, gsettings);
		}
	}

	/// Outputs a build description of the project, including its dependencies.
	ProjectDescription describe(GeneratorSettings settings)
	{
		import dub.generators.targetdescription;

		// store basic build parameters
		ProjectDescription ret;
		ret.rootPackage = m_rootPackage.name;
		ret.configuration = settings.config;
		ret.buildType = settings.buildType;
		ret.compiler = settings.platform.compiler;
		ret.architecture = settings.platform.architecture;
		ret.platform = settings.platform.platform;

		// collect high level information about projects (useful for IDE display)
		auto configs = getPackageConfigs(settings.platform, settings.config);
		ret.packages ~= m_rootPackage.describe(settings.platform, settings.config);
		foreach (dep; m_dependencies)
			ret.packages ~= dep.describe(settings.platform, configs[dep.name]);

		foreach (p; getTopologicalPackageList(false, null, configs))
			ret.packages[ret.packages.countUntil!(pp => pp.name == p.name)].active = true;

		if (settings.buildType.length) {
			// collect build target information (useful for build tools)
			auto gen = new TargetDescriptionGenerator(this);
			try {
				gen.generate(settings);
				ret.targets = gen.targetDescriptions;
				ret.targetLookup = gen.targetDescriptionLookup;
			} catch (Exception e) {
				logDiagnostic("Skipping targets description: %s", e.msg);
				logDebug("Full error: %s", e.toString().sanitize);
			}
		}

		return ret;
	}

	private string[] listBuildSetting(string attributeName)(ref GeneratorSettings settings,
		string config, ProjectDescription projectDescription, Compiler compiler, bool disableEscaping)
	{
		return listBuildSetting!attributeName(settings, getPackageConfigs(settings.platform, config),
			projectDescription, compiler, disableEscaping);
	}

	private string[] listBuildSetting(string attributeName)(ref GeneratorSettings settings,
		string[string] configs, ProjectDescription projectDescription, Compiler compiler, bool disableEscaping)
	{
		if (compiler)
			return formatBuildSettingCompiler!attributeName(settings, configs, projectDescription, compiler, disableEscaping);
		else
			return formatBuildSettingPlain!attributeName(settings, configs, projectDescription);
	}

	// Output a build setting formatted for a compiler
	private string[] formatBuildSettingCompiler(string attributeName)(ref GeneratorSettings settings,
		string[string] configs, ProjectDescription projectDescription, Compiler compiler, bool disableEscaping)
	{
		import std.process : escapeShellFileName;
		import std.path : dirSeparator;

		assert(compiler);

		auto targetDescription = projectDescription.lookupTarget(projectDescription.rootPackage);
		auto buildSettings = targetDescription.buildSettings;

		string[] values;
		switch (attributeName)
		{
		case "dflags":
		case "linkerFiles":
		case "mainSourceFile":
		case "importFiles":
			values = formatBuildSettingPlain!attributeName(settings, configs, projectDescription);
			break;

		case "lflags":
		case "sourceFiles":
		case "injectSourceFiles":
		case "versions":
		case "debugVersions":
		case "importPaths":
		case "stringImportPaths":
		case "options":
			auto bs = buildSettings.dup;
			bs.dflags = null;

			// Ensure trailing slash on directory paths
			auto ensureTrailingSlash = (string path) => path.endsWith(dirSeparator) ? path : path ~ dirSeparator;
			static if (attributeName == "importPaths")
				bs.importPaths = bs.importPaths.map!(ensureTrailingSlash).array();
			else static if (attributeName == "stringImportPaths")
				bs.stringImportPaths = bs.stringImportPaths.map!(ensureTrailingSlash).array();

			compiler.prepareBuildSettings(bs, settings.platform, BuildSetting.all & ~to!BuildSetting(attributeName));
			values = bs.dflags;
			break;

		case "libs":
			auto bs = buildSettings.dup;
			bs.dflags = null;
			bs.lflags = null;
			bs.sourceFiles = null;
			bs.targetType = TargetType.none; // Force Compiler to NOT omit dependency libs when package is a library.

			compiler.prepareBuildSettings(bs, settings.platform, BuildSetting.all & ~to!BuildSetting(attributeName));

			if (bs.lflags)
				values = compiler.lflagsToDFlags( bs.lflags );
			else if (bs.sourceFiles)
				values = compiler.lflagsToDFlags( bs.sourceFiles );
			else
				values = bs.dflags;

			break;

		default: assert(0);
		}

		// Escape filenames and paths
		if(!disableEscaping)
		{
			switch (attributeName)
			{
			case "mainSourceFile":
			case "linkerFiles":
			case "injectSourceFiles":
			case "copyFiles":
			case "importFiles":
			case "stringImportFiles":
			case "sourceFiles":
			case "importPaths":
			case "stringImportPaths":
				return values.map!(escapeShellFileName).array();

			default:
				return values;
			}
		}

		return values;
	}

	// Output a build setting without formatting for any particular compiler
	private string[] formatBuildSettingPlain(string attributeName)(ref GeneratorSettings settings, string[string] configs, ProjectDescription projectDescription)
	{
		import std.path : buildNormalizedPath, dirSeparator;
		import std.range : only;

		string[] list;

		enforce(attributeName == "targetType" || projectDescription.lookupRootPackage().targetType != TargetType.none,
			"Target type is 'none'. Cannot list build settings.");

		static if (attributeName == "targetType")
			if (projectDescription.rootPackage !in projectDescription.targetLookup)
				return ["none"];

		auto targetDescription = projectDescription.lookupTarget(projectDescription.rootPackage);
		auto buildSettings = targetDescription.buildSettings;

		string[] substituteCommands(Package pack, string[] commands, CommandType type)
		{
			auto env = makeCommandEnvironmentVariables(type, pack, this, settings, buildSettings);
			return processVars(this, pack, settings, commands, false, env);
		}

		// Return any BuildSetting member attributeName as a range of strings. Don't attempt to fixup values.
		// allowEmptyString: When the value is a string (as opposed to string[]),
		//                   is empty string an actual permitted value instead of
		//                   a missing value?
		auto getRawBuildSetting(Package pack, bool allowEmptyString) {
			auto value = __traits(getMember, buildSettings, attributeName);

			static if( attributeName.endsWith("Commands") )
				return substituteCommands(pack, value, mixin("CommandType.", attributeName[0 .. $ - "Commands".length]));
			else static if( is(typeof(value) == string[]) )
				return value;
			else static if( is(typeof(value) == string) )
			{
				auto ret = only(value);

				// only() has a different return type from only(value), so we
				// have to empty the range rather than just returning only().
				if(value.empty && !allowEmptyString) {
					ret.popFront();
					assert(ret.empty);
				}

				return ret;
			}
			else static if( is(typeof(value) == string[string]) )
				return value.byKeyValue.map!(a => a.key ~ "=" ~ a.value);
			else static if( is(typeof(value) == enum) )
				return only(value);
			else static if( is(typeof(value) == Flags!BuildRequirement) )
				return only(cast(BuildRequirement) cast(int) value.values);
			else static if( is(typeof(value) == Flags!BuildOption) )
				return only(cast(BuildOption) cast(int) value.values);
			else
				static assert(false, "Type of BuildSettings."~attributeName~" is unsupported.");
		}

		// Adjust BuildSetting member attributeName as needed.
		// Returns a range of strings.
		auto getFixedBuildSetting(Package pack) {
			// Is relative path(s) to a directory?
			enum isRelativeDirectory =
				attributeName == "importPaths" || attributeName == "stringImportPaths" ||
				attributeName == "targetPath" || attributeName == "workingDirectory";

			// Is relative path(s) to a file?
			enum isRelativeFile =
				attributeName == "sourceFiles" || attributeName == "linkerFiles" ||
				attributeName == "importFiles" || attributeName == "stringImportFiles" ||
				attributeName == "copyFiles" || attributeName == "mainSourceFile" ||
				attributeName == "injectSourceFiles";

			// For these, empty string means "main project directory", not "missing value"
			enum allowEmptyString =
				attributeName == "targetPath" || attributeName == "workingDirectory";

			enum isEnumBitfield =
				attributeName == "requirements" || attributeName == "options";

			enum isEnum = attributeName == "targetType";

			auto values = getRawBuildSetting(pack, allowEmptyString);
			string fixRelativePath(string importPath) { return buildNormalizedPath(pack.path.toString(), importPath); }
			static string ensureTrailingSlash(string path) { return path.endsWith(dirSeparator) ? path : path ~ dirSeparator; }

			static if(isRelativeDirectory) {
				// Return full paths for the paths, making sure a
				// directory separator is on the end of each path.
				return values.map!(fixRelativePath).map!(ensureTrailingSlash);
			}
			else static if(isRelativeFile) {
				// Return full paths.
				return values.map!(fixRelativePath);
			}
			else static if(isEnumBitfield)
				return bitFieldNames(values.front);
			else static if (isEnum)
				return [values.front.to!string];
			else
				return values;
		}

		foreach(value; getFixedBuildSetting(m_rootPackage)) {
			list ~= value;
		}

		return list;
	}

	// The "compiler" arg is for choosing which compiler the output should be formatted for,
	// or null to imply "list" format.
	private string[] listBuildSetting(ref GeneratorSettings settings, string[string] configs,
		ProjectDescription projectDescription, string requestedData, Compiler compiler, bool disableEscaping)
	{
		// Certain data cannot be formatter for a compiler
		if (compiler)
		{
			switch (requestedData)
			{
			case "target-type":
			case "target-path":
			case "target-name":
			case "working-directory":
			case "string-import-files":
			case "copy-files":
			case "extra-dependency-files":
			case "pre-generate-commands":
			case "post-generate-commands":
			case "pre-build-commands":
			case "post-build-commands":
			case "pre-run-commands":
			case "post-run-commands":
			case "environments":
			case "build-environments":
			case "run-environments":
			case "pre-generate-environments":
			case "post-generate-environments":
			case "pre-build-environments":
			case "post-build-environments":
			case "pre-run-environments":
			case "post-run-environments":
				enforce(false, "--data="~requestedData~" can only be used with `--data-list` or `--data-list --data-0`.");
				break;

			case "requirements":
				enforce(false, "--data=requirements can only be used with `--data-list` or `--data-list --data-0`. Use --data=options instead.");
				break;

			default: break;
			}
		}

		import std.typetuple : TypeTuple;
		auto args = TypeTuple!(settings, configs, projectDescription, compiler, disableEscaping);
		switch (requestedData)
		{
		case "target-type":                return listBuildSetting!"targetType"(args);
		case "target-path":                return listBuildSetting!"targetPath"(args);
		case "target-name":                return listBuildSetting!"targetName"(args);
		case "working-directory":          return listBuildSetting!"workingDirectory"(args);
		case "main-source-file":           return listBuildSetting!"mainSourceFile"(args);
		case "dflags":                     return listBuildSetting!"dflags"(args);
		case "lflags":                     return listBuildSetting!"lflags"(args);
		case "libs":                       return listBuildSetting!"libs"(args);
		case "linker-files":               return listBuildSetting!"linkerFiles"(args);
		case "source-files":               return listBuildSetting!"sourceFiles"(args);
		case "inject-source-files":        return listBuildSetting!"injectSourceFiles"(args);
		case "copy-files":                 return listBuildSetting!"copyFiles"(args);
		case "extra-dependency-files":     return listBuildSetting!"extraDependencyFiles"(args);
		case "versions":                   return listBuildSetting!"versions"(args);
		case "debug-versions":             return listBuildSetting!"debugVersions"(args);
		case "import-paths":               return listBuildSetting!"importPaths"(args);
		case "string-import-paths":        return listBuildSetting!"stringImportPaths"(args);
		case "import-files":               return listBuildSetting!"importFiles"(args);
		case "string-import-files":        return listBuildSetting!"stringImportFiles"(args);
		case "pre-generate-commands":      return listBuildSetting!"preGenerateCommands"(args);
		case "post-generate-commands":     return listBuildSetting!"postGenerateCommands"(args);
		case "pre-build-commands":         return listBuildSetting!"preBuildCommands"(args);
		case "post-build-commands":        return listBuildSetting!"postBuildCommands"(args);
		case "pre-run-commands":           return listBuildSetting!"preRunCommands"(args);
		case "post-run-commands":          return listBuildSetting!"postRunCommands"(args);
		case "environments":               return listBuildSetting!"environments"(args);
		case "build-environments":         return listBuildSetting!"buildEnvironments"(args);
		case "run-environments":           return listBuildSetting!"runEnvironments"(args);
		case "pre-generate-environments":  return listBuildSetting!"preGenerateEnvironments"(args);
		case "post-generate-environments": return listBuildSetting!"postGenerateEnvironments"(args);
		case "pre-build-environments":     return listBuildSetting!"preBuildEnvironments"(args);
		case "post-build-environments":    return listBuildSetting!"postBuildEnvironments"(args);
		case "pre-run-environments":       return listBuildSetting!"preRunEnvironments"(args);
		case "post-run-environments":      return listBuildSetting!"postRunEnvironments"(args);
		case "requirements":               return listBuildSetting!"requirements"(args);
		case "options":                    return listBuildSetting!"options"(args);

		default:
			enforce(false, "--data="~requestedData~
				" is not a valid option. See 'dub describe --help' for accepted --data= values.");
		}

		assert(0);
	}

	/// Outputs requested data for the project, optionally including its dependencies.
	string[] listBuildSettings(GeneratorSettings settings, string[] requestedData, ListBuildSettingsFormat list_type)
	{
		import dub.compilers.utils : isLinkerFile;

		auto projectDescription = describe(settings);
		auto configs = getPackageConfigs(settings.platform, settings.config);
		PackageDescription packageDescription;
		foreach (pack; projectDescription.packages) {
			if (pack.name == projectDescription.rootPackage)
				packageDescription = pack;
		}

		if (projectDescription.rootPackage in projectDescription.targetLookup) {
			// Copy linker files from sourceFiles to linkerFiles
			auto target = projectDescription.lookupTarget(projectDescription.rootPackage);
			foreach (file; target.buildSettings.sourceFiles.filter!(f => isLinkerFile(settings.platform, f)))
				target.buildSettings.addLinkerFiles(file);

			// Remove linker files from sourceFiles
			target.buildSettings.sourceFiles =
				target.buildSettings.sourceFiles
				.filter!(a => !isLinkerFile(settings.platform, a))
				.array();
			projectDescription.lookupTarget(projectDescription.rootPackage) = target;
		}

		Compiler compiler;
		bool no_escape;
		final switch (list_type) with (ListBuildSettingsFormat) {
			case list: break;
			case listNul: no_escape = true; break;
			case commandLine: compiler = settings.compiler; break;
			case commandLineNul: compiler = settings.compiler; no_escape = true; break;

		}

		auto result = requestedData
			.map!(dataName => listBuildSetting(settings, configs, projectDescription, dataName, compiler, no_escape));

		final switch (list_type) with (ListBuildSettingsFormat) {
			case list: return result.map!(l => l.join("\n")).array();
			case listNul: return result.map!(l => l.join("\0")).array;
			case commandLine: return result.map!(l => l.join(" ")).array;
			case commandLineNul: return result.map!(l => l.join("\0")).array;
		}
	}

	/** Saves the currently selected dependency versions to disk.

		The selections will be written to a file named
		`SelectedVersions.defaultFile` ("dub.selections.json") within the
		directory of the root package. Any existing file will get overwritten.
	*/
	void saveSelections()
	{
		assert(m_selections !is null, "Cannot save selections for non-disk based project (has no selections).");
		if (m_selections.hasSelectedVersion(m_rootPackage.basePackage.name))
			m_selections.deselectVersion(m_rootPackage.basePackage.name);

		auto path = m_rootPackage.path ~ SelectedVersions.defaultFile;
		if (m_selections.dirty || !existsFile(path))
			m_selections.save(path);
	}

	deprecated bool isUpgradeCacheUpToDate()
	{
		return false;
	}

	deprecated Dependency[string] getUpgradeCache()
	{
		return null;
	}
}


/// Determines the output format used for `Project.listBuildSettings`.
enum ListBuildSettingsFormat {
	list,           /// Newline separated list entries
	listNul,        /// NUL character separated list entries (unescaped)
	commandLine,    /// Formatted for compiler command line (one data list per line)
	commandLineNul, /// NUL character separated list entries (unescaped, data lists separated by two NUL characters)
}


/// Indicates where a package has been or should be placed to.
enum PlacementLocation {
	/// Packages retrieved with 'local' will be placed in the current folder
	/// using the package name as destination.
	local,
	/// Packages with 'userWide' will be placed in a folder accessible by
	/// all of the applications from the current user.
	user,
	/// Packages retrieved with 'systemWide' will be placed in a shared folder,
	/// which can be accessed by all users of the system.
	system
}

void processVars(ref BuildSettings dst, in Project project, in Package pack,
	BuildSettings settings, in GeneratorSettings gsettings, bool include_target_settings = false)
{
	string[string] processVerEnvs(in string[string] targetEnvs, in string[string] defaultEnvs)
	{
		string[string] retEnv;
		foreach (k, v; targetEnvs)
			retEnv[k] = v;
		foreach (k, v; defaultEnvs) {
			if (k !in targetEnvs)
				retEnv[k] = v;
		}
		return processVars(project, pack, gsettings, retEnv);
	}
	dst.addEnvironments(processVerEnvs(settings.environments, gsettings.buildSettings.environments));
	dst.addBuildEnvironments(processVerEnvs(settings.buildEnvironments, gsettings.buildSettings.buildEnvironments));
	dst.addRunEnvironments(processVerEnvs(settings.runEnvironments, gsettings.buildSettings.runEnvironments));
	dst.addPreGenerateEnvironments(processVerEnvs(settings.preGenerateEnvironments, gsettings.buildSettings.preGenerateEnvironments));
	dst.addPostGenerateEnvironments(processVerEnvs(settings.postGenerateEnvironments, gsettings.buildSettings.postGenerateEnvironments));
	dst.addPreBuildEnvironments(processVerEnvs(settings.preBuildEnvironments, gsettings.buildSettings.preBuildEnvironments));
	dst.addPostBuildEnvironments(processVerEnvs(settings.postBuildEnvironments, gsettings.buildSettings.postBuildEnvironments));
	dst.addPreRunEnvironments(processVerEnvs(settings.preRunEnvironments, gsettings.buildSettings.preRunEnvironments));
	dst.addPostRunEnvironments(processVerEnvs(settings.postRunEnvironments, gsettings.buildSettings.postRunEnvironments));

	auto buildEnvs = [dst.environments, dst.buildEnvironments];

	dst.addDFlags(processVars(project, pack, gsettings, settings.dflags, false, buildEnvs));
	dst.addLFlags(processVars(project, pack, gsettings, settings.lflags, false, buildEnvs));
	dst.addLibs(processVars(project, pack, gsettings, settings.libs, false, buildEnvs));
	dst.addSourceFiles(processVars!true(project, pack, gsettings, settings.sourceFiles, true, buildEnvs));
	dst.addImportFiles(processVars(project, pack, gsettings, settings.importFiles, true, buildEnvs));
	dst.addStringImportFiles(processVars(project, pack, gsettings, settings.stringImportFiles, true, buildEnvs));
	dst.addInjectSourceFiles(processVars!true(project, pack, gsettings, settings.injectSourceFiles, true, buildEnvs));
	dst.addCopyFiles(processVars(project, pack, gsettings, settings.copyFiles, true, buildEnvs));
	dst.addExtraDependencyFiles(processVars(project, pack, gsettings, settings.extraDependencyFiles, true, buildEnvs));
	dst.addVersions(processVars(project, pack, gsettings, settings.versions, false, buildEnvs));
	dst.addDebugVersions(processVars(project, pack, gsettings, settings.debugVersions, false, buildEnvs));
	dst.addVersionFilters(processVars(project, pack, gsettings, settings.versionFilters, false, buildEnvs));
	dst.addDebugVersionFilters(processVars(project, pack, gsettings, settings.debugVersionFilters, false, buildEnvs));
	dst.addImportPaths(processVars(project, pack, gsettings, settings.importPaths, true, buildEnvs));
	dst.addStringImportPaths(processVars(project, pack, gsettings, settings.stringImportPaths, true, buildEnvs));
	dst.addRequirements(settings.requirements);
	dst.addOptions(settings.options);

	// commands are substituted in dub.generators.generator : runBuildCommands
	dst.addPreGenerateCommands(settings.preGenerateCommands);
	dst.addPostGenerateCommands(settings.postGenerateCommands);
	dst.addPreBuildCommands(settings.preBuildCommands);
	dst.addPostBuildCommands(settings.postBuildCommands);
	dst.addPreRunCommands(settings.preRunCommands);
	dst.addPostRunCommands(settings.postRunCommands);

	if (include_target_settings) {
		dst.targetType = settings.targetType;
		dst.targetPath = processVars(settings.targetPath, project, pack, gsettings, true, buildEnvs);
		dst.targetName = settings.targetName;
		if (!settings.workingDirectory.empty)
			dst.workingDirectory = processVars(settings.workingDirectory, project, pack, gsettings, true, buildEnvs);
		if (settings.mainSourceFile.length)
			dst.mainSourceFile = processVars(settings.mainSourceFile, project, pack, gsettings, true, buildEnvs);
	}
}

string[] processVars(bool glob = false)(in Project project, in Package pack, in GeneratorSettings gsettings, in string[] vars, bool are_paths = false, in string[string][] extraVers = null)
{
	auto ret = appender!(string[])();
	processVars!glob(ret, project, pack, gsettings, vars, are_paths, extraVers);
	return ret.data;
}
void processVars(bool glob = false)(ref Appender!(string[]) dst, in Project project, in Package pack, in GeneratorSettings gsettings, in string[] vars, bool are_paths = false, in string[string][] extraVers = null)
{
	static if (glob)
		alias process = processVarsWithGlob!(Project, Package);
	else
		alias process = processVars!(Project, Package);
	foreach (var; vars)
		dst.put(process(var, project, pack, gsettings, are_paths, extraVers));
}

string processVars(Project, Package)(string var, in Project project, in Package pack, in GeneratorSettings gsettings, bool is_path, in string[string][] extraVers = null)
{
	var = var.expandVars!(varName => getVariable(varName, project, pack, gsettings, extraVers));
	if (!is_path)
		return var;
	auto p = NativePath(var);
	if (!p.absolute)
		return (pack.path ~ p).toNativeString();
	else
		return p.toNativeString();
}
string[string] processVars(bool glob = false)(in Project project, in Package pack, in GeneratorSettings gsettings, in string[string] vars, in string[string][] extraVers = null)
{
	string[string] ret;
	processVars!glob(ret, project, pack, gsettings, vars, extraVers);
	return ret;
}
void processVars(bool glob = false)(ref string[string] dst, in Project project, in Package pack, in GeneratorSettings gsettings, in string[string] vars, in string[string][] extraVers)
{
	static if (glob)
		alias process = processVarsWithGlob!(Project, Package);
	else
		alias process = processVars!(Project, Package);
	foreach (k, var; vars)
		dst[k] = process(var, project, pack, gsettings, false, extraVers);
}

private string[] processVarsWithGlob(Project, Package)(string var, in Project project, in Package pack, in GeneratorSettings gsettings, bool is_path, in string[string][] extraVers)
{
	assert(is_path, "can't glob something that isn't a path");
	string res = processVars(var, project, pack, gsettings, is_path, extraVers);
	// Find the unglobbed prefix and iterate from there.
	size_t i = 0;
	size_t sepIdx = 0;
	loop: while (i < res.length) {
		switch_: switch (res[i])
		{
		case '*', '?', '[', '{': break loop;
		case '/': sepIdx = i; goto default;
		default: ++i; break switch_;
		}
	}
	if (i == res.length) //no globbing found in the path
		return [res];
	import std.path : globMatch;
	import std.file : dirEntries, SpanMode;
	return dirEntries(res[0 .. sepIdx], SpanMode.depth)
		.map!(de => de.name)
		.filter!(name => globMatch(name, res))
		.array;
}
/// Expand variables using `$VAR_NAME` or `${VAR_NAME}` syntax.
/// `$$` escapes itself and is expanded to a single `$`.
private string expandVars(alias expandVar)(string s)
{
	import std.functional : not;

	auto result = appender!string;

	static bool isVarChar(char c)
	{
		import std.ascii;
		return isAlphaNum(c) || c == '_';
	}

	while (true)
	{
		auto pos = s.indexOf('$');
		if (pos < 0)
		{
			result.put(s);
			return result.data;
		}
		result.put(s[0 .. pos]);
		s = s[pos + 1 .. $];
		enforce(s.length > 0, "Variable name expected at end of string");
		switch (s[0])
		{
			case '$':
				result.put("$");
				s = s[1 .. $];
				break;
			case '{':
				pos = s.indexOf('}');
				enforce(pos >= 0, "Could not find '}' to match '${'");
				result.put(expandVar(s[1 .. pos]));
				s = s[pos + 1 .. $];
				break;
			default:
				pos = s.representation.countUntil!(not!isVarChar);
				if (pos < 0)
					pos = s.length;
				result.put(expandVar(s[0 .. pos]));
				s = s[pos .. $];
				break;
		}
	}
}

unittest
{
	string[string] vars =
	[
		"A" : "a",
		"B" : "b",
	];

	string expandVar(string name) { auto p = name in vars; enforce(p, name); return *p; }

	assert(expandVars!expandVar("") == "");
	assert(expandVars!expandVar("x") == "x");
	assert(expandVars!expandVar("$$") == "$");
	assert(expandVars!expandVar("x$$") == "x$");
	assert(expandVars!expandVar("$$x") == "$x");
	assert(expandVars!expandVar("$$$$") == "$$");
	assert(expandVars!expandVar("x$A") == "xa");
	assert(expandVars!expandVar("x$$A") == "x$A");
	assert(expandVars!expandVar("$A$B") == "ab");
	assert(expandVars!expandVar("${A}$B") == "ab");
	assert(expandVars!expandVar("$A${B}") == "ab");
	assert(expandVars!expandVar("a${B}") == "ab");
	assert(expandVars!expandVar("${A}b") == "ab");

	import std.exception : assertThrown;
	assertThrown(expandVars!expandVar("$"));
	assertThrown(expandVars!expandVar("${}"));
	assertThrown(expandVars!expandVar("$|"));
	assertThrown(expandVars!expandVar("x$"));
	assertThrown(expandVars!expandVar("$X"));
	assertThrown(expandVars!expandVar("${"));
	assertThrown(expandVars!expandVar("${X"));

	// https://github.com/dlang/dmd/pull/9275
	assert(expandVars!expandVar("$${DUB_EXE:-dub}") == "${DUB_EXE:-dub}");
}

// Keep the following list up-to-date if adding more build settings variables.
/// List of variables that can be used in build settings
package(dub) immutable buildSettingsVars = [
	"ARCH", "PLATFORM", "PLATFORM_POSIX", "BUILD_TYPE"
];

private string getVariable(Project, Package)(string name, in Project project, in Package pack, in GeneratorSettings gsettings, in string[string][] extraVars = null)
{
	import dub.internal.utils : getDUBExePath;
	import std.process : environment, escapeShellFileName;
	import std.uni : asUpperCase;

	NativePath path;
	if (name == "PACKAGE_DIR")
		path = pack.path;
	else if (name == "ROOT_PACKAGE_DIR")
		path = project.rootPackage.path;

	if (name.endsWith("_PACKAGE_DIR")) {
		auto pname = name[0 .. $-12];
		foreach (prj; project.getTopologicalPackageList())
			if (prj.name.asUpperCase.map!(a => a == '-' ? '_' : a).equal(pname))
			{
				path = prj.path;
				break;
			}
	}

	if (!path.empty)
	{
		// no trailing slash for clean path concatenation (see #1392)
		path.endsWithSlash = false;
		return path.toNativeString();
	}

	if (name == "DUB") {
		return getDUBExePath(gsettings.platform.compilerBinary);
	}

	if (name == "ARCH") {
		foreach (a; gsettings.platform.architecture)
			return a;
		return "";
	}

	if (name == "PLATFORM") {
		import std.algorithm : filter;
		foreach (p; gsettings.platform.platform.filter!(p => p != "posix"))
			return p;
		foreach (p; gsettings.platform.platform)
			return p;
		return "";
	}

	if (name == "PLATFORM_POSIX") {
		import std.algorithm : canFind;
		if (gsettings.platform.platform.canFind("posix"))
			return "posix";
		foreach (p; gsettings.platform.platform)
			return p;
		return "";
	}

	if (name == "BUILD_TYPE") return gsettings.buildType;

	if (name == "DFLAGS" || name == "LFLAGS")
	{
		auto buildSettings = pack.getBuildSettings(gsettings.platform, gsettings.config);
		if (name == "DFLAGS")
			return join(buildSettings.dflags," ");
		else if (name == "LFLAGS")
			return join(buildSettings.lflags," ");
	}

	import std.range;
	foreach (aa; retro(extraVars))
		if (auto exvar = name in aa)
			return *exvar;

	auto envvar = environment.get(name);
	if (envvar !is null) return envvar;

	throw new Exception("Invalid variable: "~name);
}


unittest
{
	static struct MockPackage
	{
		this(string name)
		{
			this.name = name;
			version (Posix)
				path = NativePath("/pkgs/"~name);
			else version (Windows)
				path = NativePath(`C:\pkgs\`~name);
			// see 4d4017c14c, #268, and #1392 for why this all package paths end on slash internally
			path.endsWithSlash = true;
		}
		string name;
		NativePath path;
		BuildSettings getBuildSettings(in BuildPlatform platform, string config) const
		{
			return BuildSettings();
		}
	}

	static struct MockProject
	{
		MockPackage rootPackage;
		inout(MockPackage)[] getTopologicalPackageList() inout
		{
			return _dependencies;
		}
	private:
		MockPackage[] _dependencies;
	}

	MockProject proj = {
		rootPackage: MockPackage("root"),
		_dependencies: [MockPackage("dep1"), MockPackage("dep2")]
	};
	auto pack = MockPackage("test");
	GeneratorSettings gsettings;
	enum isPath = true;

	import std.path : dirSeparator;

	static NativePath woSlash(NativePath p) { p.endsWithSlash = false; return p; }
	// basic vars
	assert(processVars("Hello $PACKAGE_DIR", proj, pack, gsettings, !isPath) == "Hello "~woSlash(pack.path).toNativeString);
	assert(processVars("Hello $ROOT_PACKAGE_DIR", proj, pack, gsettings, !isPath) == "Hello "~woSlash(proj.rootPackage.path).toNativeString.chomp(dirSeparator));
	assert(processVars("Hello $DEP1_PACKAGE_DIR", proj, pack, gsettings, !isPath) == "Hello "~woSlash(proj._dependencies[0].path).toNativeString);
	// ${VAR} replacements
	assert(processVars("Hello ${PACKAGE_DIR}"~dirSeparator~"foobar", proj, pack, gsettings, !isPath) == "Hello "~(pack.path ~ "foobar").toNativeString);
	assert(processVars("Hello $PACKAGE_DIR"~dirSeparator~"foobar", proj, pack, gsettings, !isPath) == "Hello "~(pack.path ~ "foobar").toNativeString);
	// test with isPath
	assert(processVars("local", proj, pack, gsettings, isPath) == (pack.path ~ "local").toNativeString);
	assert(processVars("foo/$$ESCAPED", proj, pack, gsettings, isPath) == (pack.path ~ "foo/$ESCAPED").toNativeString);
	assert(processVars("$$ESCAPED", proj, pack, gsettings, !isPath) == "$ESCAPED");
	// test other env variables
	import std.process : environment;
	environment["MY_ENV_VAR"] = "blablabla";
	assert(processVars("$MY_ENV_VAR", proj, pack, gsettings, !isPath) == "blablabla");
	assert(processVars("${MY_ENV_VAR}suffix", proj, pack, gsettings, !isPath) == "blablablasuffix");
	assert(processVars("$MY_ENV_VAR-suffix", proj, pack, gsettings, !isPath) == "blablabla-suffix");
	assert(processVars("$MY_ENV_VAR:suffix", proj, pack, gsettings, !isPath) == "blablabla:suffix");
	assert(processVars("$MY_ENV_VAR$MY_ENV_VAR", proj, pack, gsettings, !isPath) == "blablablablablabla");
	environment.remove("MY_ENV_VAR");
}

/** Holds and stores a set of version selections for package dependencies.

	This is the runtime representation of the information contained in
	"dub.selections.json" within a package's directory.
*/
final class SelectedVersions {
	private {
		enum FileVersion = 1;
		Selected m_selections;
		bool m_dirty = false; // has changes since last save
		bool m_bare = true;
	}

	/// Default file name to use for storing selections.
	enum defaultFile = "dub.selections.json";

	/// Constructs a new empty version selection.
	public this(uint version_ = FileVersion) @safe pure nothrow @nogc
	{
		this.m_selections = Selected(version_);
	}

	/// Constructs a new non-empty version selection.
	public this(Selected data) @safe pure nothrow @nogc
	{
		this.m_selections = data;
		this.m_bare = false;
	}

	/** Constructs a new version selection from JSON data.

		The structure of the JSON document must match the contents of the
		"dub.selections.json" file.
	*/
	deprecated("Pass a `dub.recipe.selection : Selected` directly")
	this(Json data)
	{
		deserialize(data);
		m_dirty = false;
	}

	/** Constructs a new version selections from an existing JSON file.
	*/
	deprecated("JSON deserialization is deprecated")
	this(NativePath path)
	{
		auto json = jsonFromFile(path);
		deserialize(json);
		m_dirty = false;
		m_bare = false;
	}

	/// Returns a list of names for all packages that have a version selection.
	@property string[] selectedPackages() const { return m_selections.versions.keys; }

	/// Determines if any changes have been made after loading the selections from a file.
	@property bool dirty() const { return m_dirty; }

	/// Determine if this set of selections is still empty (but not `clear`ed).
	@property bool bare() const { return m_bare && !m_dirty; }

	/// Removes all selections.
	void clear()
	{
		m_selections.versions = null;
		m_dirty = true;
	}

	/// Duplicates the set of selected versions from another instance.
	void set(SelectedVersions versions)
	{
		m_selections.fileVersion = versions.m_selections.fileVersion;
		m_selections.versions = versions.m_selections.versions.dup;
		m_dirty = true;
	}

	/// Selects a certain version for a specific package.
	void selectVersion(string package_id, Version version_)
	{
		if (auto pdep = package_id in m_selections.versions) {
			if (*pdep == Dependency(version_))
				return;
		}
		m_selections.versions[package_id] = Dependency(version_);
		m_dirty = true;
	}

	/// Selects a certain path for a specific package.
	void selectVersion(string package_id, NativePath path)
	{
		if (auto pdep = package_id in m_selections.versions) {
			if (*pdep == Dependency(path))
				return;
		}
		m_selections.versions[package_id] = Dependency(path);
		m_dirty = true;
	}

	/// Selects a certain Git reference for a specific package.
	void selectVersion(string package_id, Repository repository)
	{
		const dependency = Dependency(repository);
		if (auto pdep = package_id in m_selections.versions) {
			if (*pdep == dependency)
				return;
		}
		m_selections.versions[package_id] = dependency;
		m_dirty = true;
	}

	deprecated("Move `spec` inside of the `repository` parameter and call `selectVersion`")
	void selectVersionWithRepository(string package_id, Repository repository, string spec)
	{
		this.selectVersion(package_id, Repository(repository.remote(), spec));
	}

	/// Removes the selection for a particular package.
	void deselectVersion(string package_id)
	{
		m_selections.versions.remove(package_id);
		m_dirty = true;
	}

	/// Determines if a particular package has a selection set.
	bool hasSelectedVersion(string packageId)
	const {
		return (packageId in m_selections.versions) !is null;
	}

	/** Returns the selection for a particular package.

		Note that the returned `Dependency` can either have the
		`Dependency.path` property set to a non-empty value, in which case this
		is a path based selection, or its `Dependency.version_` property is
		valid and it is a version selection.
	*/
	Dependency getSelectedVersion(string packageId)
	const {
		enforce(hasSelectedVersion(packageId));
		return m_selections.versions[packageId];
	}

	/** Stores the selections to disk.

		The target file will be written in JSON format. Usually, `defaultFile`
		should be used as the file name and the directory should be the root
		directory of the project's root package.
	*/
	void save(NativePath path)
	{
		Json json = serialize();
		auto file = openFile(path, FileMode.createTrunc);
		scope(exit) file.close();

		assert(json.type == Json.Type.object);
		assert(json.length == 2);
		assert(json["versions"].type != Json.Type.undefined);

		file.write("{\n\t\"fileVersion\": ");
		file.writeJsonString(json["fileVersion"]);
		file.write(",\n\t\"versions\": {");
		auto vers = json["versions"].get!(Json[string]);
		bool first = true;
		foreach (k; vers.byKey.array.sort()) {
			if (!first) file.write(",");
			else first = false;
			file.write("\n\t\t");
			file.writeJsonString(Json(k));
			file.write(": ");
			file.writeJsonString(vers[k]);
		}
		file.write("\n\t}\n}\n");
		m_dirty = false;
		m_bare = false;
	}

	deprecated("Use `dub.dependency : Dependency.toJson(true)`")
	static Json dependencyToJson(Dependency d)
	{
		return d.toJson(true);
	}

	deprecated("JSON deserialization is deprecated")
	static Dependency dependencyFromJson(Json j)
	{
		if (j.type == Json.Type.string)
			return Dependency(Version(j.get!string));
		else if (j.type == Json.Type.object && "path" in j)
			return Dependency(NativePath(j["path"].get!string));
		else if (j.type == Json.Type.object && "repository" in j)
			return Dependency(Repository(j["repository"].get!string,
				enforce("version" in j, "Expected \"version\" field in repository version object").get!string));
		else throw new Exception(format("Unexpected type for dependency: %s", j));
	}

	Json serialize()
	const {
		Json json = serializeToJson(m_selections);
		Json serialized = Json.emptyObject;
		serialized["fileVersion"] = m_selections.fileVersion;
		serialized["versions"] = Json.emptyObject;
		foreach (p, dep; m_selections.versions)
			serialized["versions"][p] = dep.toJson(true);
		return serialized;
	}

	deprecated("JSON deserialization is deprecated")
	private void deserialize(Json json)
	{
		const fileVersion = cast(int)json["fileVersion"];
		enforce(fileVersion == FileVersion, "Mismatched dub.selections.json version: " ~ to!string(fileVersion) ~ " vs. " ~ to!string(FileVersion));
		clear();
		m_selections.fileVersion = fileVersion;
		scope(failure) clear();
		foreach (string p, dep; json["versions"])
			m_selections.versions[p] = dependencyFromJson(dep);
	}
}
