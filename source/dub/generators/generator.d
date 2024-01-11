/**
	Generator for project files

	Copyright: © 2012-2013 Matthias Dondorff, © 2013-2016 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.generators.generator;

import dub.compilers.compiler;
import dub.generators.cmake;
import dub.generators.build;
import dub.generators.sublimetext;
import dub.generators.visuald;
import dub.internal.utils;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.path;
import dub.internal.logging;
import dub.package_;
import dub.packagemanager;
import dub.project;

import std.algorithm : map, filter, canFind, balancedParens;
import std.array : array, appender, join;
import std.exception;
import std.file;
import std.string;


/**
	Common interface for project generators/builders.
*/
class ProjectGenerator
{
	/** Information about a single binary target.

		A binary target can either be an executable or a static/dynamic library.
		It consists of one or more packages.
	*/
	struct TargetInfo {
		/// The root package of this target
		Package pack;

		/// All packages compiled into this target
		Package[] packages;

		/// The configuration used for building the root package
		string config;

		/** Build settings used to build the target.

			The build settings include all sources of all contained packages.

			Depending on the specific generator implementation, it may be
			necessary to add any static or dynamic libraries generated for
			child targets ($(D linkDependencies)).
		*/
		BuildSettings buildSettings;

		/** List of all dependencies.

			This list includes dependencies that are not the root of a binary
			target.
		*/
		string[] dependencies;

		/** List of all binary dependencies.

			This list includes all dependencies that are the root of a binary
			target.
		*/
		string[] linkDependencies;
	}

	private struct EnvironmentVariables
	{
		string[string] environments;
		string[string] buildEnvironments;
		string[string] runEnvironments;
		string[string] preGenerateEnvironments;
		string[string] postGenerateEnvironments;
		string[string] preBuildEnvironments;
		string[string] postBuildEnvironments;
		string[string] preRunEnvironments;
		string[string] postRunEnvironments;

		this(const scope ref BuildSettings bs)
		{
			update(bs);
		}

		void update(Envs)(const scope auto ref Envs envs)
		{
			import std.algorithm: each;
			envs.environments.byKeyValue.each!(pair => environments[pair.key] = pair.value);
			envs.buildEnvironments.byKeyValue.each!(pair => buildEnvironments[pair.key] = pair.value);
			envs.runEnvironments.byKeyValue.each!(pair => runEnvironments[pair.key] = pair.value);
			envs.preGenerateEnvironments.byKeyValue.each!(pair => preGenerateEnvironments[pair.key] = pair.value);
			envs.postGenerateEnvironments.byKeyValue.each!(pair => postGenerateEnvironments[pair.key] = pair.value);
			envs.preBuildEnvironments.byKeyValue.each!(pair => preBuildEnvironments[pair.key] = pair.value);
			envs.postBuildEnvironments.byKeyValue.each!(pair => postBuildEnvironments[pair.key] = pair.value);
			envs.preRunEnvironments.byKeyValue.each!(pair => preRunEnvironments[pair.key] = pair.value);
			envs.postRunEnvironments.byKeyValue.each!(pair => postRunEnvironments[pair.key] = pair.value);
		}

		void updateBuildSettings(ref BuildSettings bs)
		{
			bs.updateEnvironments(environments);
			bs.updateBuildEnvironments(buildEnvironments);
			bs.updateRunEnvironments(runEnvironments);
			bs.updatePreGenerateEnvironments(preGenerateEnvironments);
			bs.updatePostGenerateEnvironments(postGenerateEnvironments);
			bs.updatePreBuildEnvironments(preBuildEnvironments);
			bs.updatePostBuildEnvironments(postBuildEnvironments);
			bs.updatePreRunEnvironments(preRunEnvironments);
			bs.updatePostRunEnvironments(postRunEnvironments);
		}
	}

	protected {
		Project m_project;
		NativePath m_tempTargetExecutablePath;
	}

	this(Project project)
	{
		m_project = project;
	}

	/** Performs the full generator process.
	*/
	final void generate(GeneratorSettings settings)
	{
		import dub.compilers.utils : enforceBuildRequirements;

		if (!settings.config.length) settings.config = m_project.getDefaultConfiguration(settings.platform);

		string[string] configs = m_project.getPackageConfigs(settings.platform, settings.config);
		TargetInfo[string] targets;
		EnvironmentVariables[string] envs;

		foreach (pack; m_project.getTopologicalPackageList(true, null, configs)) {
			auto config = configs[pack.name];
			auto bs = pack.getBuildSettings(settings.platform, config);
			targets[pack.name] = TargetInfo(pack, [pack], config, bs);
			envs[pack.name] = EnvironmentVariables(bs);
		}
		foreach (pack; m_project.getTopologicalPackageList(false, null, configs)) {
			auto ti = pack.name in targets;
			auto parentEnvs = ti.pack.name in envs;
			foreach (deppkgName, depInfo; pack.getDependencies(ti.config)) {
				if (auto childEnvs = deppkgName in envs) {
					childEnvs.update(ti.buildSettings);
					parentEnvs.update(childEnvs);
				}
			}
		}
		BuildSettings makeBuildSettings(in Package pack, ref BuildSettings src)
		{
			BuildSettings bs;
			if (settings.buildSettings.options & BuildOption.lowmem) bs.options |= BuildOption.lowmem;
			BuildSettings srcbs = src.dup;
			envs[pack.name].updateBuildSettings(srcbs);
			bs.processVars(m_project, pack, srcbs, settings, true);
			return bs;
		}

		foreach (pack; m_project.getTopologicalPackageList(true, null, configs)) {
			BuildSettings bs = makeBuildSettings(pack, targets[pack.name].buildSettings);
			prepareGeneration(pack, m_project, settings, bs);

			// Regenerate buildSettings.sourceFiles
			if (bs.preGenerateCommands.length) {
				auto newSettings = pack.getBuildSettings(settings.platform, configs[pack.name]);
				bs = makeBuildSettings(pack, newSettings);
			}
			targets[pack.name].buildSettings = bs;
		}
		configurePackages(m_project.rootPackage, targets, settings);

		addBuildTypeSettings(targets, settings);
		foreach (ref t; targets.byValue) enforceBuildRequirements(t.buildSettings);

		generateTargets(settings, targets);

		foreach (pack; m_project.getTopologicalPackageList(true, null, configs)) {
			auto config = configs[pack.name];
			auto pkgbs  = pack.getBuildSettings(settings.platform, config);
			BuildSettings buildsettings = makeBuildSettings(pack, pkgbs);
			bool generate_binary = !(buildsettings.options & BuildOption.syntaxOnly);
			auto bs = &targets[m_project.rootPackage.name].buildSettings;
			auto targetPath = !m_tempTargetExecutablePath.empty ? m_tempTargetExecutablePath :
							  !bs.targetPath.empty ? NativePath(bs.targetPath) :
							  NativePath(buildsettings.targetPath);

			finalizeGeneration(pack, m_project, settings, buildsettings, targetPath, generate_binary);
		}

		performPostGenerateActions(settings, targets);
	}

	/** Overridden in derived classes to implement the actual generator functionality.

		The function should go through all targets recursively. The first target
		(which is guaranteed to be there) is
		$(D targets[m_project.rootPackage.name]). The recursive descent is then
		done using the $(D TargetInfo.linkDependencies) list.

		This method is also potentially responsible for running the pre and post
		build commands, while pre and post generate commands are already taken
		care of by the $(D generate) method.

		Params:
			settings = The generator settings used for this run
			targets = A map from package name to TargetInfo that contains all
				binary targets to be built.
	*/
	protected abstract void generateTargets(GeneratorSettings settings, in TargetInfo[string] targets);

	/** Overridable method to be invoked after the generator process has finished.

		An examples of functionality placed here is to run the application that
		has just been built.
	*/
	protected void performPostGenerateActions(GeneratorSettings settings, in TargetInfo[string] targets) {}

	/** Configure `rootPackage` and all of it's dependencies.

		1. Merge versions, debugVersions, and inheritable build
		settings from dependents to their dependencies.

		2. Define version identifiers Have_dependency_xyz for all
		direct dependencies of all packages.

		3. Merge versions, debugVersions, and inheritable build settings from
		dependencies to their dependents, so that importer and importee are ABI
		compatible. This also transports all Have_dependency_xyz version
		identifiers to `rootPackage`.

		4. Merge injectSourceFiles from dependencies into their dependents.
		This is based upon binary images and will transcend direct relationships
		including shared libraries.

		5. Filter unused versions and debugVersions from all targets. The
		filters have previously been upwards inherited (3. and 4.) so that versions
		used in a dependency are also applied to all dependents.

		Note: The upwards inheritance is done at last so that siblings do not
		influence each other, also see https://github.com/dlang/dub/pull/1128.

		Note: Targets without output are integrated into their
		dependents and removed from `targets`.
	 */
	private void configurePackages(Package rootPackage, TargetInfo[string] targets, GeneratorSettings genSettings)
	{
		import std.algorithm : remove, sort;
		import std.range : repeat;

		auto roottarget = &targets[rootPackage.name];

		// 0. do shallow configuration (not including dependencies) of all packages
		TargetType determineTargetType(const ref TargetInfo ti, const ref GeneratorSettings genSettings)
		{
			TargetType tt = ti.buildSettings.targetType;
			if (ti.pack is rootPackage) {
				if (tt == TargetType.autodetect || tt == TargetType.library) tt = TargetType.staticLibrary;
			} else {
				if (tt == TargetType.autodetect || tt == TargetType.library) tt = genSettings.combined ? TargetType.sourceLibrary : TargetType.staticLibrary;
				else if (genSettings.platform.architecture.canFind("x86_omf") && tt == TargetType.dynamicLibrary) {
					// Unfortunately we cannot remove this check for OMF targets,
					// due to Optlink not producing shared libraries without a lot of user intervention.
					// For other targets, say MSVC it'll do the right thing for the most part,
					// export is still a problem as of this writing, which means static libraries cannot have linking to them removed.
					// But that is for the most part up to the developer, to get it working correctly.

					logWarn("Dynamic libraries are not yet supported as dependencies for Windows target OMF - building as static library.");
					tt = TargetType.staticLibrary;
				}
			}
			if (tt != TargetType.none && tt != TargetType.sourceLibrary && ti.buildSettings.sourceFiles.empty) {
				logWarn(`Configuration [%s] of package %s contains no source files. Please add %s to its package description to avoid building it.`,
						ti.config.color(Color.blue), ti.pack.name.color(Mode.bold), `{"targetType": "none"}`.color(Mode.bold));
				tt = TargetType.none;
			}
			return tt;
		}

		string[] mainSourceFiles;
		bool[string] hasOutput;

		foreach (ref ti; targets.byValue)
		{
			auto bs = &ti.buildSettings;
			// determine the actual target type
			bs.targetType = determineTargetType(ti, genSettings);

			switch (bs.targetType)
			{
			case TargetType.none:
				// ignore any build settings for targetType none (only dependencies will be processed)
				*bs = BuildSettings.init;
				bs.targetType = TargetType.none;
				break;

			case TargetType.executable:
				break;

			case TargetType.dynamicLibrary:
				// set -fPIC for dynamic library builds
				ti.buildSettings.addOptions(BuildOption.pic);
				goto default;

			default:
				// remove any mainSourceFile from non-executable builds
				if (bs.mainSourceFile.length) {
					bs.sourceFiles = bs.sourceFiles.remove!(f => f == bs.mainSourceFile);
					mainSourceFiles ~= bs.mainSourceFile;
				}
				break;
			}
			bool generatesBinary = bs.targetType != TargetType.sourceLibrary && bs.targetType != TargetType.none;
			hasOutput[ti.pack.name] = generatesBinary || ti.pack is rootPackage;
		}

		// add main source files to root executable
		{
			auto bs = &roottarget.buildSettings;
			if (bs.targetType == TargetType.executable || genSettings.single) bs.addSourceFiles(mainSourceFiles);
		}

		if (genSettings.filterVersions)
			foreach (ref ti; targets.byValue)
				inferVersionFilters(ti);

		// mark packages as visited (only used during upwards propagation)
		void[0][Package] visited;

		// collect all dependencies
		void collectDependencies(Package pack, ref TargetInfo ti, TargetInfo[string] targets, size_t level = 0)
		{
			// use `visited` here as pkgs cannot depend on themselves
			if (pack in visited)
				return;
			// transitive dependencies must be visited multiple times, see #1350
			immutable transitive = !hasOutput[pack.name];
			if (!transitive)
				visited[pack] = typeof(visited[pack]).init;

			auto bs = &ti.buildSettings;
			if (hasOutput[pack.name])
				logDebug("%sConfiguring target %s (%s %s %s)", ' '.repeat(2 * level), pack.name, bs.targetType, bs.targetPath, bs.targetName);
			else
				logDebug("%sConfiguring target without output %s", ' '.repeat(2 * level), pack.name);

			// get specified dependencies, e.g. vibe-d ~0.8.1
			auto deps = pack.getDependencies(targets[pack.name].config);
			logDebug("deps: %s -> %(%s, %)", pack.name, deps.byKey);
			foreach (depname; deps.keys.sort())
			{
				auto depspec = deps[depname];
				// get selected package for that dependency, e.g. vibe-d 0.8.2-beta.2
				auto deppack = m_project.getDependency(depname, depspec.optional);
				if (deppack is null) continue; // optional and not selected

				// if dependency has no output
				if (!hasOutput[depname]) {
					// add itself
					ti.packages ~= deppack;
					// and it's transitive dependencies to current target
					collectDependencies(deppack, ti, targets, level + 1);
					continue;
				}
				auto depti = &targets[depname];
				const depbs = &depti.buildSettings;
				if (depbs.targetType == TargetType.executable && ti.buildSettings.targetType != TargetType.none)
					continue;

				// add to (link) dependencies
				ti.dependencies ~= depname;
				ti.linkDependencies ~= depname;

				// recurse
				collectDependencies(deppack, *depti, targets, level + 1);

				// also recursively add all link dependencies of static *and* dynamic libraries
				// preserve topological sorting of dependencies for correct link order
				if (depbs.targetType == TargetType.staticLibrary || depbs.targetType == TargetType.dynamicLibrary)
					ti.linkDependencies = ti.linkDependencies.filter!(d => !depti.linkDependencies.canFind(d)).array ~ depti.linkDependencies;
			}

			enforce(!(ti.buildSettings.targetType == TargetType.none && ti.dependencies.empty),
				"Package with target type \"none\" must have dependencies to build.");
		}

		collectDependencies(rootPackage, *roottarget, targets);
		visited.clear();

		// 1. downwards inherits versions, debugVersions, and inheritable build settings
		static void configureDependencies(const scope ref TargetInfo ti, TargetInfo[string] targets, size_t level = 0)
		{

			// do not use `visited` here as dependencies must inherit
			// configurations from *all* of their parents
			logDebug("%sConfigure dependencies of %s, deps:%(%s, %)", ' '.repeat(2 * level), ti.pack.name, ti.dependencies);
			foreach (depname; ti.dependencies)
			{
				auto pti = &targets[depname];
				mergeFromDependent(ti.buildSettings, pti.buildSettings);
				configureDependencies(*pti, targets, level + 1);
			}
		}

		configureDependencies(*roottarget, targets);

		// 2. add Have_dependency_xyz for all direct dependencies of a target
		// (includes incorporated non-target dependencies and their dependencies)
		foreach (ref ti; targets.byValue)
		{
			import std.range : chain;
			import dub.internal.utils : stripDlangSpecialChars;

			auto bs = &ti.buildSettings;
			auto pkgnames = ti.packages.map!(p => p.name).chain(ti.dependencies);
			bs.addVersions(pkgnames.map!(pn => "Have_" ~ stripDlangSpecialChars(pn)).array);
		}

		// 3. upwards inherit full build configurations (import paths, versions, debugVersions, versionFilters, importPaths, ...)

		// We do a check for if any dependency uses final binary injection source files,
		// otherwise can ignore that bit of workload entirely
		bool skipFinalBinaryMerging = true;

		void configureDependents(ref TargetInfo ti, TargetInfo[string] targets, size_t level = 0)
		{
			// use `visited` here as pkgs cannot depend on themselves
			if (ti.pack in visited)
				return;
			visited[ti.pack] = typeof(visited[ti.pack]).init;

			logDiagnostic("%sConfiguring dependent %s, deps:%(%s, %)", ' '.repeat(2 * level), ti.pack.name, ti.dependencies);
			// embedded non-binary dependencies
			foreach (deppack; ti.packages[1 .. $])
				ti.buildSettings.add(targets[deppack.name].buildSettings);

			// binary dependencies
			foreach (depname; ti.dependencies)
			{
				auto pdepti = &targets[depname];

				configureDependents(*pdepti, targets, level + 1);
				mergeFromDependency(pdepti.buildSettings, ti.buildSettings, genSettings.platform);

				if (!pdepti.buildSettings.injectSourceFiles.empty)
					skipFinalBinaryMerging = false;
			}
		}

		configureDependents(*roottarget, targets);
		visited.clear();

		// LDC: need to pass down dflags affecting symbol visibility, especially on Windows
		if (genSettings.platform.compiler == "ldc")
		{
			const isWindows = genSettings.platform.isWindows();
			bool passDownDFlag(string flag)
			{
				if (flag.startsWith("--"))
					flag = flag[1 .. $];
				return flag.startsWith("-fvisibility=") || (isWindows &&
					(flag.startsWith("-link-defaultlib-shared") ||
					 flag.startsWith("-dllimport=")));
			}

			// all dflags from dependencies have already been added to the root project
			auto rootDFlagsToPassDown = roottarget.buildSettings.dflags.filter!passDownDFlag.array;

			if (rootDFlagsToPassDown.length)
			{
				foreach (name, ref ti; targets)
				{
					if (&ti != roottarget && ti.buildSettings.targetType != TargetType.dynamicLibrary)
					{
						import std.range : chain;
						ti.buildSettings.dflags = ti.buildSettings.dflags
							// remove all existing visibility flags first to reduce duplicates
							.filter!(f => !passDownDFlag(f))
							.chain(rootDFlagsToPassDown)
							.array;
					}
				}
			}
		}

		// 4. As an extension to configureDependents we need to copy any injectSourceFiles
		// in our dependencies (ignoring targetType)
		void configureDependentsFinalImages(ref TargetInfo ti, TargetInfo[string] targets, ref TargetInfo finalBinaryTarget, size_t level = 0)
		{
			// use `visited` here as pkgs cannot depend on themselves
			if (ti.pack in visited)
				return;
			visited[ti.pack] = typeof(visited[ti.pack]).init;

			logDiagnostic("%sConfiguring dependent %s, deps:%(%s, %) for injectSourceFiles", ' '.repeat(2 * level), ti.pack.name, ti.dependencies);

			foreach (depname; ti.dependencies)
			{
				auto pdepti = &targets[depname];

				if (!pdepti.buildSettings.injectSourceFiles.empty)
					finalBinaryTarget.buildSettings.addSourceFiles(pdepti.buildSettings.injectSourceFiles);

				configureDependentsFinalImages(*pdepti, targets, finalBinaryTarget, level + 1);
			}
		}

		if (!skipFinalBinaryMerging)
		{
			foreach (ref target; targets.byValue)
			{
				switch (target.buildSettings.targetType)
				{
					case TargetType.executable:
					case TargetType.dynamicLibrary:
					configureDependentsFinalImages(target, targets, target);

					// We need to clear visited for each target that is executable dynamicLibrary
					// due to this process needing to be recursive based upon the final binary targets.
					visited.clear();
					break;

					default:
					break;
				}
			}
		}

		// 5. Filter applicable version and debug version identifiers
		if (genSettings.filterVersions)
		{
			foreach (name, ref ti; targets)
			{
				import std.algorithm.sorting : partition;

				auto bs = &ti.buildSettings;

				auto filtered = bs.versions.partition!(v => bs.versionFilters.canFind(v));
				logDebug("Filtering out unused versions for %s: %s", name, filtered);
				bs.versions = bs.versions[0 .. $ - filtered.length];

				filtered = bs.debugVersions.partition!(v => bs.debugVersionFilters.canFind(v));
				logDebug("Filtering out unused debug versions for %s: %s", name, filtered);
				bs.debugVersions = bs.debugVersions[0 .. $ - filtered.length];
			}
		}

		// 6. override string import files in dependencies
		static void overrideStringImports(ref TargetInfo target,
			ref TargetInfo parent, TargetInfo[string] targets, string[] overrides)
		{
			// Since string import paths are inherited from dependencies in the
			// inheritance step above (step 3), it is guaranteed that all
			// following dependencies will not have string import paths either,
			// so we can skip the recursion here
			if (!target.buildSettings.stringImportPaths.length)
				return;

			// do not use visited here as string imports can be overridden by *any* parent
			//
			// special support for overriding string imports in parent packages
			// this is a candidate for deprecation, once an alternative approach
			// has been found
			bool any_override = false;

			// override string import files (used for up to date checking)
			foreach (ref f; target.buildSettings.stringImportFiles)
			{
				foreach (o; overrides)
				{
					NativePath op;
					if (f != o && NativePath(f).head == (op = NativePath(o)).head) {
						logDebug("string import %s overridden by %s", f, o);
						f = o;
						any_override = true;
					}
				}
			}

			// override string import paths by prepending to the list, in
			// case there is any overlapping file
			if (any_override)
				target.buildSettings.prependStringImportPaths(parent.buildSettings.stringImportPaths);

			// add all files to overrides for recursion
			overrides ~= target.buildSettings.stringImportFiles;

			// recursively override all dependencies with the accumulated files/paths
			foreach (depname; target.dependencies)
				overrideStringImports(targets[depname], target, targets, overrides);
		}

		// push string import paths/files down to all direct and indirect
		// dependencies, overriding their own
		foreach (depname; roottarget.dependencies)
			overrideStringImports(targets[depname], *roottarget, targets,
				roottarget.buildSettings.stringImportFiles);

		// 7. downwards inherits dependency build settings
		static void applyForcedSettings(const scope ref TargetInfo ti, TargetInfo[string] targets,
											BuildSettings[string] dependBS, size_t level = 0)
		{

			static void apply(const scope ref BuildSettings forced, ref BuildSettings child) {
				child.addDFlags(forced.dflags);
			}

			// apply to all dependencies
			foreach (depname; ti.dependencies)
			{
				BuildSettings forcedSettings;
				auto pti = &targets[depname];

				// fetch the forced dependency build settings
				if (auto matchedSettings = depname in dependBS)
					forcedSettings = *matchedSettings;
				else if (auto matchedSettings = "*" in dependBS)
					forcedSettings = *matchedSettings;

				apply(forcedSettings, pti.buildSettings);

				// recursively apply forced settings to all dependencies of his dependency
				applyForcedSettings(*pti, targets, ["*" : forcedSettings], level + 1);
			}
		}

		// apply both top level and configuration level forced dependency build settings
		void applyDependencyBuildSettings (const RecipeDependency[string] configured_dbs)
		{
			BuildSettings[string] dependencyBuildSettings;
			foreach (key, value; configured_dbs)
			{
				BuildSettings buildSettings;
				if (auto target = key in targets)
				{
					// get platform specific build settings and process dub variables (BuildSettingsTemplate => BuildSettings)
					value.settings.getPlatformSettings(buildSettings, genSettings.platform, target.pack.path);
					buildSettings.processVars(m_project, target.pack, buildSettings, genSettings, true);
					dependencyBuildSettings[key] = buildSettings;
				}
			}
			applyForcedSettings(*roottarget, targets, dependencyBuildSettings);
		}
		applyDependencyBuildSettings(rootPackage.recipe.buildSettings.dependencies);
		applyDependencyBuildSettings(rootPackage.getBuildSettings(genSettings.config).dependencies);

		// remove targets without output
		foreach (name; targets.keys)
		{
			if (!hasOutput[name])
				targets.remove(name);
		}
	}

	// infer applicable version identifiers
	private static void inferVersionFilters(ref TargetInfo ti)
	{
		import std.algorithm.searching : any;
		import std.file : timeLastModified;
		import std.path : extension;
		import std.range : chain;
		import std.regex : ctRegex, matchAll;
		import std.stdio : File;
		import std.datetime : Clock, SysTime, UTC;
		import dub.compilers.utils : isLinkerFile;
		import dub.internal.vibecompat.data.json : Json, JSONException;

		auto bs = &ti.buildSettings;

		// only infer if neither version filters are specified explicitly
		if (bs.versionFilters.length || bs.debugVersionFilters.length)
		{
			logDebug("Using specified versionFilters for %s: %s %s", ti.pack.name,
				bs.versionFilters, bs.debugVersionFilters);
			return;
		}

		// check all existing source files for version identifiers
		static immutable dexts = [".d", ".di"];
		auto srcs = chain(bs.sourceFiles, bs.importFiles, bs.stringImportFiles)
			.filter!(f => dexts.canFind(f.extension)).filter!exists;
		// try to load cached filters first
		const cacheFilePath = packageCache(NativePath(ti.buildSettings.targetPath), ti.pack)
			~ "metadata_cache.json";
		enum silent_fail = true;
		auto cache = jsonFromFile(cacheFilePath, silent_fail);
		try
		{
			auto cachedFilters = cache["versionFilters"];
			if (cachedFilters.type != Json.Type.undefined)
				cachedFilters = cachedFilters[ti.config];
			if (cachedFilters.type != Json.Type.undefined)
			{
				immutable mtime = SysTime.fromISOExtString(cachedFilters["mtime"].get!string);
				if (!srcs.any!(src => src.timeLastModified > mtime))
				{
					auto versionFilters = cachedFilters["versions"][].map!(j => j.get!string).array;
					auto debugVersionFilters = cachedFilters["debugVersions"][].map!(j => j.get!string).array;
					logDebug("Using cached versionFilters for %s: %s %s", ti.pack.name,
						versionFilters, debugVersionFilters);
					bs.addVersionFilters(versionFilters);
					bs.addDebugVersionFilters(debugVersionFilters);
					return;
				}
			}
		}
		catch (JSONException e)
		{
			logWarn("Exception during loading invalid package cache %s.\n%s",
				ti.pack.path ~ ".dub/metadata_cache.json", e);
		}

		// use ctRegex for performance reasons, only small compile time increase
		enum verRE = ctRegex!`(?:^|\s)version\s*\(\s*([^\s]*?)\s*\)`;
		enum debVerRE = ctRegex!`(?:^|\s)debug\s*\(\s*([^\s]*?)\s*\)`;

		auto versionFilters = appender!(string[]);
		auto debugVersionFilters = appender!(string[]);

		foreach (file; srcs)
		{
			foreach (line; File(file).byLine)
			{
				foreach (m; line.matchAll(verRE))
					if (!versionFilters.data.canFind(m[1]))
						versionFilters.put(m[1].idup);
				foreach (m; line.matchAll(debVerRE))
					if (!debugVersionFilters.data.canFind(m[1]))
						debugVersionFilters.put(m[1].idup);
			}
		}
		logDebug("Using inferred versionFilters for %s: %s %s", ti.pack.name,
			versionFilters.data, debugVersionFilters.data);
		bs.addVersionFilters(versionFilters.data);
		bs.addDebugVersionFilters(debugVersionFilters.data);

		auto cachedFilters = cache["versionFilters"];
		if (cachedFilters.type == Json.Type.undefined)
			cachedFilters = cache["versionFilters"] = [ti.config: Json.emptyObject];
		cachedFilters[ti.config] = [
			"mtime": Json(Clock.currTime(UTC()).toISOExtString),
			"versions": Json(versionFilters.data.map!Json.array),
			"debugVersions": Json(debugVersionFilters.data.map!Json.array),
		];
        enum create_if_missing = true;
        if (isWritableDir(cacheFilePath.parentPath, create_if_missing))
            writeJsonFile(cacheFilePath, cache);
	}

	private static void mergeFromDependent(const scope ref BuildSettings parent, ref BuildSettings child)
	{
		child.addVersions(parent.versions);
		child.addDebugVersions(parent.debugVersions);
		child.addOptions(Flags!BuildOption(parent.options & inheritedBuildOptions));
	}

	private static void mergeFromDependency(const scope ref BuildSettings child, ref BuildSettings parent, const scope ref BuildPlatform platform)
	{
		import dub.compilers.utils : isLinkerFile;

		parent.addDFlags(child.dflags);
		parent.addVersions(child.versions);
		parent.addDebugVersions(child.debugVersions);
		parent.addVersionFilters(child.versionFilters);
		parent.addDebugVersionFilters(child.debugVersionFilters);
		parent.addImportPaths(child.importPaths);
		parent.addCImportPaths(child.cImportPaths);
		parent.addStringImportPaths(child.stringImportPaths);
		parent.addInjectSourceFiles(child.injectSourceFiles);
		// linker stuff propagates up from static *and* dynamic library deps
		if (child.targetType == TargetType.staticLibrary || child.targetType == TargetType.dynamicLibrary) {
			parent.addSourceFiles(child.sourceFiles.filter!(f => isLinkerFile(platform, f)).array);
			parent.addLibs(child.libs);
			parent.addLFlags(child.lflags);
		}
	}

	// configure targets for build types such as release, or unittest-cov
	private void addBuildTypeSettings(TargetInfo[string] targets, in GeneratorSettings settings)
	{
		foreach (ref ti; targets.byValue) {
			ti.buildSettings.add(settings.buildSettings);

			// add build type settings and convert plain DFLAGS to build options
			m_project.addBuildTypeSettings(ti.buildSettings, settings, ti.pack is m_project.rootPackage);
			settings.compiler.extractBuildOptions(ti.buildSettings);

			auto tt = ti.buildSettings.targetType;
			enforce (tt != TargetType.sourceLibrary || ti.pack !is m_project.rootPackage || (ti.buildSettings.options & BuildOption.syntaxOnly),
				format("Main package must not have target type \"%s\". Cannot build.", tt));
		}
	}
}

/**
 * Compute and returns the path were artifacts are stored for a given package
 *
 * Artifacts are stored in:
 * `$DUB_HOME/cache/$PKG_NAME/$PKG_VERSION[/+$SUB_PKG_NAME]/`
 * Note that the leading `+` in the sub-package name is to avoid any ambiguity.
 *
 * Dub writes in the returned path a Json description file of the available
 * artifacts in this cache location. This Json file is read by 3rd party
 * software (e.g. Meson). Returned path should therefore not change across
 * future Dub versions.
 *
 * Build artifacts are usually stored in a sub-folder named "build",
 * as their names are based on user-supplied values.
 *
 * Params:
 *   cachePath = Base path at which the build cache is located,
 *               e.g. `$HOME/.dub/cache/`
 *	 pkg = The package. Cannot be `null`.
 */
package(dub) NativePath packageCache(NativePath cachePath, in Package pkg)
{
	import std.algorithm.searching : findSplit;

	assert(pkg !is null);
	assert(!cachePath.empty);

	// For subpackages
	if (const names = pkg.name.findSplit(":"))
		return cachePath ~ names[0] ~ pkg.version_.toString()
			~ ("+" ~ names[2]);
	// For regular packages
	return cachePath ~ pkg.name ~ pkg.version_.toString();
}

/**
 * Compute and return the directory where a target should be cached.
 *
 * Params:
 *   cachePath = Base path at which the build cache is located,
 *               e.g. `$HOME/.dub/cache/`
 *	 pkg = The package. Cannot be `null`.
 *   buildId = The build identifier of the target.
 */
package(dub) NativePath targetCacheDir(NativePath cachePath, in Package pkg, string buildId)
{
	return packageCache(cachePath, pkg) ~ "build" ~ buildId;
}

/**
 * Provides a unique (per build) identifier
 *
 * When building a package, it is important to have a unique but stable
 * identifier to differentiate builds and allow their caching.
 * This function provides such an identifier.
 * Example:
 * ```
 * library-debug-Z7qINYX4IxM8muBSlyNGrw
 * ```
 */
package(dub) string computeBuildID(in BuildSettings buildsettings, string config, GeneratorSettings settings)
{
	import std.conv : to;

	const(string[])[] hashing = [
		buildsettings.versions,
		buildsettings.debugVersions,
		buildsettings.dflags,
		buildsettings.lflags,
		buildsettings.stringImportPaths,
		buildsettings.importPaths,
		buildsettings.cImportPaths,
		settings.platform.architecture,
		[
			(cast(uint)(buildsettings.options & ~BuildOption.color)).to!string, // exclude color option from id
			settings.platform.compilerBinary,
			settings.platform.compiler,
			settings.platform.compilerVersion,
		],
	];

	return computeBuildName(config, settings, hashing);
}

struct GeneratorSettings {
	NativePath cache;
	BuildPlatform platform;
	Compiler compiler;
	string config;
	string recipeName;
	string buildType;
	BuildSettings buildSettings;
	BuildMode buildMode = BuildMode.separate;
	int targetExitStatus;
	NativePath overrideToolWorkingDirectory;

	bool combined; // compile all in one go instead of each dependency separately
	bool filterVersions;

	// only used for generator "build"
	bool run, force, rdmd, tempBuild, parallelBuild;

	/// single file dub package
	bool single;

	/// build all dependencies for static libraries
	bool buildDeep;

	string[] runArgs;
	void delegate(int status, string output) compileCallback;
	void delegate(int status, string output) linkCallback;
	void delegate(int status, string output) runCallback;

	/// Returns `overrideToolWorkingDirectory` or if that's not set, just the
	/// current working directory of the application. This may differ if dub is
	/// called with the `--root` parameter or when using DUB as a library.
	NativePath toolWorkingDirectory() const
	{
		return overrideToolWorkingDirectory is NativePath.init
			? getWorkingDirectory()
			: overrideToolWorkingDirectory;
	}
}


/**
	Determines the mode in which the compiler and linker are invoked.
*/
enum BuildMode {
	separate,                 /// Compile and link separately
	allAtOnce,                /// Perform compile and link with a single compiler invocation
	singleFile,               /// Compile each file separately
	//multipleObjects,          /// Generate an object file per module
	//multipleObjectsPerModule, /// Use the -multiobj switch to generate multiple object files per module
	//compileOnly               /// Do not invoke the linker (can be done using a post build command)
}


/**
	Creates a project generator of the given type for the specified project.
*/
ProjectGenerator createProjectGenerator(string generator_type, Project project)
{
	assert(project !is null, "Project instance needed to create a generator.");

	generator_type = generator_type.toLower();
	switch(generator_type) {
		default:
			throw new Exception("Unknown project generator: "~generator_type);
		case "build":
			logDebug("Creating build generator.");
			return new BuildGenerator(project);
		case "mono-d":
			throw new Exception("The Mono-D generator has been removed. Use Mono-D's built in DUB support instead.");
		case "visuald":
			logDebug("Creating VisualD generator.");
			return new VisualDGenerator(project);
		case "sublimetext":
			logDebug("Creating SublimeText generator.");
			return new SublimeTextGenerator(project);
		case "cmake":
			logDebug("Creating CMake generator.");
			return new CMakeGenerator(project);
	}
}


/**
	Calls delegates on files and directories in the given path that match any globs.
*/
void findFilesMatchingGlobs(in NativePath path, in string[] globList, void delegate(string file) addFile, void delegate(string dir) addDir)
{
	import std.path : globMatch;

	string[] globs;
	foreach (f; globList)
	{
		if (f.canFind("*", "?") ||
			(f.canFind("{") && f.balancedParens('{', '}')) ||
			(f.canFind("[") && f.balancedParens('[', ']')))
		{
			globs ~= f;
		}
		else
		{
			if (f.isDir)
				addDir(f);
			else
				addFile(f);
		}
	}
	if (globs.length) // Search all files for glob matches
		foreach (f; dirEntries(path.toNativeString(), SpanMode.breadth))
			foreach (glob; globs)
				if (f.name().globMatch(glob))
				{
					if (f.isDir)
						addDir(f);
					else
						addFile(f);
					break;
				}
}


/**
	Calls delegates on files in the given path that match any globs.

	If a directory matches a glob, the delegate is called on all existing files inside it recursively
	in depth-first pre-order.
*/
void findFilesMatchingGlobs(in NativePath path, in string[] globList, void delegate(string file) addFile)
{
	void addDir(string dir)
	{
		foreach (f; dirEntries(dir, SpanMode.breadth))
			addFile(f);
	}

	findFilesMatchingGlobs(path, globList, addFile, &addDir);
}


/**
	Runs pre-build commands and performs other required setup before project files are generated.
*/
private void prepareGeneration(in Package pack, in Project proj, in GeneratorSettings settings,
	in BuildSettings buildsettings)
{
	if (buildsettings.preGenerateCommands.length && !isRecursiveInvocation(pack.name)) {
		logInfo("Pre-gen", Color.light_green, "Running commands for %s", pack.name);
		runBuildCommands(CommandType.preGenerate, buildsettings.preGenerateCommands, pack, proj, settings, buildsettings);
	}
}

/**
	Runs post-build commands and copies required files to the binary directory.
*/
private void finalizeGeneration(in Package pack, in Project proj, in GeneratorSettings settings,
	in BuildSettings buildsettings, NativePath target_path, bool generate_binary)
{
	if (buildsettings.postGenerateCommands.length && !isRecursiveInvocation(pack.name)) {
		logInfo("Post-gen", Color.light_green, "Running commands for %s", pack.name);
		runBuildCommands(CommandType.postGenerate, buildsettings.postGenerateCommands, pack, proj, settings, buildsettings);
	}

	if (generate_binary) {
		if (!settings.tempBuild)
			ensureDirectory(NativePath(buildsettings.targetPath));

		if (buildsettings.copyFiles.length) {
			void copyFolderRec(NativePath folder, NativePath dstfolder)
			{
				ensureDirectory(dstfolder);
				foreach (de; iterateDirectory(folder)) {
					if (de.isDirectory) {
						copyFolderRec(folder ~ de.name, dstfolder ~ de.name);
					} else {
						try hardLinkFile(folder ~ de.name, dstfolder ~ de.name, true);
						catch (Exception e) {
							logWarn("Failed to copy file %s: %s", (folder ~ de.name).toNativeString(), e.msg);
						}
					}
				}
			}

			void tryCopyDir(string file)
			{
				auto src = NativePath(file);
				if (!src.absolute) src = pack.path ~ src;
				auto dst = target_path ~ NativePath(file).head;
				if (src == dst) {
					logDiagnostic("Skipping copy of %s (same source and destination)", file);
					return;
				}
				logDiagnostic("  %s to %s", src.toNativeString(), dst.toNativeString());
				try {
					copyFolderRec(src, dst);
				} catch(Exception e) logWarn("Failed to copy %s to %s: %s", src.toNativeString(), dst.toNativeString(), e.msg);
			}

			void tryCopyFile(string file)
			{
				auto src = NativePath(file);
				if (!src.absolute) src = pack.path ~ src;
				auto dst = target_path ~ NativePath(file).head;
				if (src == dst) {
					logDiagnostic("Skipping copy of %s (same source and destination)", file);
					return;
				}
				logDiagnostic("  %s to %s", src.toNativeString(), dst.toNativeString());
				try {
					hardLinkFile(src, dst, true);
				} catch(Exception e) logWarn("Failed to copy %s to %s: %s", src.toNativeString(), dst.toNativeString(), e.msg);
			}
			logInfo("Copying files for %s...", pack.name);
			findFilesMatchingGlobs(pack.path, buildsettings.copyFiles, &tryCopyFile, &tryCopyDir);
		}

	}
}


/** Runs a list of build commands for a particular package.

	This function sets all DUB specific environment variables and makes sure
	that recursive dub invocations are detected and don't result in infinite
	command execution loops. The latter could otherwise happen when a command
	runs "dub describe" or similar functionality.
*/
void runBuildCommands(CommandType type, in string[] commands, in Package pack, in Project proj,
	in GeneratorSettings settings, in BuildSettings build_settings, in string[string][] extraVars = null)
{
	import dub.internal.utils : runCommands;

	auto env = makeCommandEnvironmentVariables(type, pack, proj, settings, build_settings, extraVars);
	auto sub_commands = processVars(proj, pack, settings, commands, false, env);

	auto depNames = proj.dependencies.map!((a) => a.name).array();
	storeRecursiveInvokations(env, proj.rootPackage.name ~ depNames);

	runCommands(sub_commands, env.collapseEnv, pack.path().toString());
}

const(string[string])[] makeCommandEnvironmentVariables(CommandType type,
	in Package pack, in Project proj, in GeneratorSettings settings,
	in BuildSettings build_settings, in string[string][] extraVars = null)
{
	import dub.internal.utils : getDUBExePath;
	import std.conv : to, text;
	import std.process : environment, escapeShellFileName;

	string[string] env;
	// TODO: do more elaborate things here
	// TODO: escape/quote individual items appropriately
	env["VERSIONS"]              = join(build_settings.versions, " ");
	env["LIBS"]                  = join(build_settings.libs, " ");
	env["SOURCE_FILES"]          = join(build_settings.sourceFiles, " ");
	env["IMPORT_PATHS"]          = join(build_settings.importPaths, " ");
	env["C_IMPORT_PATHS"]        = join(build_settings.cImportPaths, " ");
	env["STRING_IMPORT_PATHS"]   = join(build_settings.stringImportPaths, " ");

	env["DC"]                    = settings.platform.compilerBinary;
	env["DC_BASE"]               = settings.platform.compiler;
	env["D_FRONTEND_VER"]        = to!string(settings.platform.frontendVersion);

	env["DUB_EXE"]               = getDUBExePath(settings.platform.compilerBinary).toNativeString();
	env["DUB_PLATFORM"]          = join(settings.platform.platform, " ");
	env["DUB_ARCH"]              = join(settings.platform.architecture, " ");

	env["DUB_TARGET_TYPE"]       = to!string(build_settings.targetType);
	env["DUB_TARGET_PATH"]       = build_settings.targetPath;
	env["DUB_TARGET_NAME"]       = build_settings.targetName;
	env["DUB_TARGET_EXIT_STATUS"] = settings.targetExitStatus.text;
	env["DUB_WORKING_DIRECTORY"] = build_settings.workingDirectory;
	env["DUB_MAIN_SOURCE_FILE"]  = build_settings.mainSourceFile;

	env["DUB_CONFIG"]            = settings.config;
	env["DUB_BUILD_TYPE"]        = settings.buildType;
	env["DUB_BUILD_MODE"]        = to!string(settings.buildMode);
	env["DUB_PACKAGE"]           = pack.name;
	env["DUB_PACKAGE_DIR"]       = pack.path.toNativeString();
	env["DUB_ROOT_PACKAGE"]      = proj.rootPackage.name;
	env["DUB_ROOT_PACKAGE_DIR"]  = proj.rootPackage.path.toNativeString();
	env["DUB_PACKAGE_VERSION"]   = pack.version_.toString();

	env["DUB_COMBINED"]          = settings.combined?      "TRUE" : "";
	env["DUB_RUN"]               = settings.run?           "TRUE" : "";
	env["DUB_FORCE"]             = settings.force?         "TRUE" : "";
	env["DUB_RDMD"]              = settings.rdmd?          "TRUE" : "";
	env["DUB_TEMP_BUILD"]        = settings.tempBuild?     "TRUE" : "";
	env["DUB_PARALLEL_BUILD"]    = settings.parallelBuild? "TRUE" : "";

	env["DUB_RUN_ARGS"] = (cast(string[])settings.runArgs).map!(escapeShellFileName).join(" ");

	auto cfgs = proj.getPackageConfigs(settings.platform, settings.config, true);
	auto rootPackageBuildSettings = proj.rootPackage.getBuildSettings(settings.platform, cfgs[proj.rootPackage.name]);
	env["DUB_ROOT_PACKAGE_TARGET_TYPE"] = to!string(rootPackageBuildSettings.targetType);
	env["DUB_ROOT_PACKAGE_TARGET_PATH"] = rootPackageBuildSettings.targetPath;
	env["DUB_ROOT_PACKAGE_TARGET_NAME"] = rootPackageBuildSettings.targetName;

	const(string[string])[] typeEnvVars;
	with (build_settings) final switch (type)
	{
		// pre/postGenerate don't have generateEnvironments, but reuse buildEnvironments
		case CommandType.preGenerate: typeEnvVars = [environments, buildEnvironments, preGenerateEnvironments]; break;
		case CommandType.postGenerate: typeEnvVars = [environments, buildEnvironments, postGenerateEnvironments]; break;
		case CommandType.preBuild: typeEnvVars = [environments, buildEnvironments, preBuildEnvironments]; break;
		case CommandType.postBuild: typeEnvVars = [environments, buildEnvironments, postBuildEnvironments]; break;
		case CommandType.preRun: typeEnvVars = [environments, runEnvironments, preRunEnvironments]; break;
		case CommandType.postRun: typeEnvVars = [environments, runEnvironments, postRunEnvironments]; break;
	}

	return [environment.toAA()] ~ env ~ typeEnvVars ~ extraVars;
}

string[string] collapseEnv(in string[string][] envs)
{
	string[string] ret;
	foreach (subEnv; envs)
	{
		foreach (k, v; subEnv)
			ret[k] = v;
	}
	return ret;
}

/// Type to specify where CLI commands that need to be run came from. Needed for
/// proper substitution with support for the different environments.
enum CommandType
{
	/// Defined in the preGenerateCommands setting
	preGenerate,
	/// Defined in the postGenerateCommands setting
	postGenerate,
	/// Defined in the preBuildCommands setting
	preBuild,
	/// Defined in the postBuildCommands setting
	postBuild,
	/// Defined in the preRunCommands setting
	preRun,
	/// Defined in the postRunCommands setting
	postRun
}

private bool isRecursiveInvocation(string pack)
{
	import std.algorithm : canFind, splitter;
	import std.process : environment;

	return environment
		.get("DUB_PACKAGES_USED", "")
		.splitter(",")
		.canFind(pack);
}

private void storeRecursiveInvokations(ref const(string[string])[] env, string[] packs)
{
	import std.algorithm : canFind, splitter;
	import std.range : chain;
	import std.process : environment;

	env ~= [
		"DUB_PACKAGES_USED": environment
			.get("DUB_PACKAGES_USED", "")
			.splitter(",")
			.chain(packs)
			.join(",")
	];
}

version(Posix) {
    // https://github.com/dlang/dub/issues/2238
	unittest {
		import dub.internal.vibecompat.data.json : parseJsonString;
		import dub.compilers.gdc : GDCCompiler;
		import std.algorithm : canFind;
		import std.path : absolutePath;
		import std.file : rmdirRecurse, write;

		mkdirRecurse("dubtest/preGen/source");
		write("dubtest/preGen/source/foo.d", "");
		scope(exit) rmdirRecurse("dubtest");

		auto desc = parseJsonString(`{"name": "test", "targetType": "library", "preGenerateCommands": ["touch $PACKAGE_DIR/source/bar.d"]}`);
		auto pack = new Package(desc, NativePath("dubtest/preGen".absolutePath));
		auto pman = new PackageManager(pack.path, NativePath("/tmp/foo/"), NativePath("/tmp/foo/"), false);
		auto prj = new Project(pman, pack);

		final static class TestCompiler : GDCCompiler {
			override void invoke(in BuildSettings settings, in BuildPlatform platform, void delegate(int, string) output_callback, NativePath cwd) {
				assert(false);
			}
			override void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects, void delegate(int, string) output_callback, NativePath cwd) {
				assert(false);
			}
		}

		GeneratorSettings settings;
		settings.compiler = new TestCompiler;
		settings.buildType = "debug";

		final static class TestGenerator : ProjectGenerator {
			this(Project project) {
			 	super(project);
			}

			override void generateTargets(GeneratorSettings settings, in TargetInfo[string] targets) {
                import std.conv : text;
				const sourceFiles = targets["test"].buildSettings.sourceFiles;
                assert(sourceFiles.canFind("dubtest/preGen/source/bar.d".absolutePath), sourceFiles.text);
			}
		}

		auto gen = new TestGenerator(prj);
		gen.generate(settings);
	}
}
