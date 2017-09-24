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
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.inet.path;
import dub.package_;
import dub.packagemanager;
import dub.project;

import std.algorithm : map, filter, canFind, balancedParens;
import std.array : array;
import std.array;
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

	protected {
		Project m_project;
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

		TargetInfo[string] targets;
		string[string] configs = m_project.getPackageConfigs(settings.platform, settings.config);

		foreach (pack; m_project.getTopologicalPackageList(true, null, configs)) {
			BuildSettings buildsettings;
			buildsettings.processVars(m_project, pack, pack.getBuildSettings(settings.platform, configs[pack.name]), true);
			prepareGeneration(pack, m_project, settings, buildsettings);
		}

		string[] mainfiles;
		collect(settings, m_project.rootPackage, BuildSettings(), targets, configs, mainfiles, null);
		addBuildTypeSettings(targets, settings);
		foreach (ref t; targets.byValue) enforceBuildRequirements(t.buildSettings);
		auto bs = &targets[m_project.rootPackage.name].buildSettings;
		if (bs.targetType == TargetType.executable) bs.addSourceFiles(mainfiles);

		generateTargets(settings, targets);

		foreach (pack; m_project.getTopologicalPackageList(true, null, configs)) {
			BuildSettings buildsettings;
			buildsettings.processVars(m_project, pack, pack.getBuildSettings(settings.platform, configs[pack.name]), true);
			bool generate_binary = !(buildsettings.options & BuildOption.syntaxOnly);
			finalizeGeneration(pack, m_project, settings, buildsettings, Path(bs.targetPath), generate_binary);
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

	private BuildSettings collect(GeneratorSettings settings, Package pack, BuildSettings parentSettings, ref TargetInfo[string] targets, in string[string] configs, ref string[] main_files, string bin_pack, BuildSettings[string] forDependenciesSettingsMap = null)
	{
		import std.algorithm : sort;
		import dub.compilers.utils : isLinkerFile;
		import std.stdio;
		import dub.internal.utils : stripDlangSpecialChars;

		BuildSettings buildsettings, forDependenciesBuildSettings;
		bool is_target;

		void setIs_target(TargetType tt)
		{
			bool generates_binary = tt != TargetType.sourceLibrary && tt != TargetType.none;
			is_target = generates_binary || pack is m_project.rootPackage;
		}

		static auto mergeFromDependents(BuildSettings parent, ref BuildSettings child) {
			child.addVersions(parent.versions);
			child.addDebugVersions(parent.debugVersions);
			child.addOptions(BuildOptions(cast(BuildOptions)parent.options & inheritedBuildOptions));

			// special support for overriding string imports in parent packages
			// this is a candidate for deprecation, once an alternative approach
			// has been found
			if (child.stringImportPaths.length) {
				// override string import files (used for up to date checking)
				foreach (ref f; child.stringImportFiles)
					foreach (fi; parent.stringImportFiles)
						if (f != fi && Path(f).head == Path(fi).head) {
							f = fi;
						}

				// add the string import paths (used by the compiler to find the overridden files)
				child.prependStringImportPaths(parent.stringImportPaths);
			}

			return child;
		}

		auto packInTargets = pack.name in targets;
		if (packInTargets is null) {
			// determine the actual target type
			auto shallowbs = pack.getBuildSettings(settings.platform, configs[pack.name]);
			TargetType tt = shallowbs.targetType;
			if (pack is m_project.rootPackage) {
				if (tt == TargetType.autodetect || tt == TargetType.library) tt = TargetType.staticLibrary;
			} else {
				if (tt == TargetType.autodetect || tt == TargetType.library) tt = settings.combined ? TargetType.sourceLibrary : TargetType.staticLibrary;
				else if (tt == TargetType.dynamicLibrary) {
					logWarn("Dynamic libraries are not yet supported as dependencies - building as static library.");
					tt = TargetType.staticLibrary;
				}
			}
			if (tt != TargetType.none && tt != TargetType.sourceLibrary && shallowbs.sourceFiles.empty) {
				logWarn(`Configuration '%s' of package %s contains no source files. Please add {"targetType": "none"} to its package description to avoid building it.`,
					configs[pack.name], pack.name);
				tt = TargetType.none;
			}

			setIs_target(tt);
			shallowbs.targetType = tt;

			if (tt == TargetType.none) {
				// ignore any build settings for targetType none (only dependencies will be processed)
				shallowbs = BuildSettings.init;
				shallowbs.targetType = TargetType.none;
			}

			// start to build up the build settings
			processVars(buildsettings, m_project, pack, shallowbs, true);

			// remove any mainSourceFile from library builds
			if (buildsettings.targetType != TargetType.executable && buildsettings.mainSourceFile.length) {
				buildsettings.sourceFiles = buildsettings.sourceFiles.filter!(f => f != buildsettings.mainSourceFile)().array;
				main_files ~= buildsettings.mainSourceFile;
			}

			// set pic for dynamic library builds.
			if (buildsettings.targetType == TargetType.dynamicLibrary)
				buildsettings.addOptions(BuildOption.pic);

			logDiagnostic("Generate target %s (%s %s %s)", pack.name, buildsettings.targetType, buildsettings.targetPath, buildsettings.targetName);
			if (is_target)
				targets[pack.name] = TargetInfo(pack, [pack], configs[pack.name], buildsettings, null);

			forDependenciesBuildSettings = buildsettings.dup;
		}
		else {
			buildsettings = packInTargets.buildSettings;
			forDependenciesBuildSettings = buildsettings.dup;
			setIs_target(buildsettings.targetType);
		}
		mergeFromDependents(parentSettings, forDependenciesBuildSettings);

		if (auto p = pack.name in forDependenciesSettingsMap)
		{
			mergeFromDependents(forDependenciesBuildSettings, *p);
			forDependenciesBuildSettings = *p;
		}
		else
			forDependenciesSettingsMap[pack.name] = forDependenciesBuildSettings.dup;

		buildsettings.addVersions(["Have_" ~ stripDlangSpecialChars(pack.name)]);

		auto deps = pack.getDependencies(configs[pack.name]);
		foreach (depname; deps.keys.sort()) {
			auto depspec = deps[depname];
			auto dep = m_project.getDependency(depname, depspec.optional);
			if (!dep) continue;

			auto depbs = collect(settings, dep, forDependenciesBuildSettings, targets, configs, main_files, is_target ? pack.name : bin_pack, forDependenciesSettingsMap);

			if (packInTargets is null) {
				if (depbs.targetType != TargetType.sourceLibrary && depbs.targetType != TargetType.none) {
					// add a reference to the target binary and remove all source files in the dependency build settings
					depbs.sourceFiles = depbs.sourceFiles.filter!(f => f.isLinkerFile()).array;
					depbs.importFiles = null;
				}

				buildsettings.add(depbs);

				if (depbs.targetType == TargetType.executable)
					continue;

				auto pt = (is_target ? pack.name : bin_pack) in targets;
				assert(pt !is null);
				if (auto pdt = depname in targets) {
					pt.dependencies ~= depname;
					pt.linkDependencies ~= depname;
					if (depbs.targetType == TargetType.staticLibrary)
						pt.linkDependencies = pt.linkDependencies.filter!(d => !pdt.linkDependencies.canFind(d)).array ~ pdt.linkDependencies;
				} else pt.packages ~= dep;
			}
		}

		auto ret = buildsettings.dup;
		if (is_target)
			targets[pack.name].buildSettings = buildsettings;

		if (pack is m_project.rootPackage)
			foreach (targetName; forDependenciesSettingsMap.byKey())
				mergeFromDependents(forDependenciesSettingsMap[targetName], targets[targetName].buildSettings);

		return ret;
	}

	private void addBuildTypeSettings(TargetInfo[string] targets, GeneratorSettings settings)
	{
		foreach (ref t; targets) {
			t.buildSettings.add(settings.buildSettings);

			// add build type settings and convert plain DFLAGS to build options
			m_project.addBuildTypeSettings(t.buildSettings, settings.platform, settings.buildType, t.pack is m_project.rootPackage);
			settings.compiler.extractBuildOptions(t.buildSettings);

			auto tt = t.buildSettings.targetType;
			bool generates_binary = tt != TargetType.sourceLibrary && tt != TargetType.none;
			enforce (generates_binary || t.pack !is m_project.rootPackage || (t.buildSettings.options & BuildOption.syntaxOnly),
				format("Main package must have a binary target type, not %s. Cannot build.", tt));
		}
	}
}


struct GeneratorSettings {
	BuildPlatform platform;
	Compiler compiler;
	string config;
	string buildType;
	BuildSettings buildSettings;
	BuildMode buildMode = BuildMode.separate;

	bool combined; // compile all in one go instead of each dependency separately

	// only used for generator "build"
	bool run, force, direct, rdmd, tempBuild, parallelBuild;
	string[] runArgs;
	void delegate(int status, string output) compileCallback;
	void delegate(int status, string output) linkCallback;
	void delegate(int status, string output) runCallback;
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
	Runs pre-build commands and performs other required setup before project files are generated.
*/
private void prepareGeneration(in Package pack, in Project proj, in GeneratorSettings settings,
	in BuildSettings buildsettings)
{
	if (buildsettings.preGenerateCommands.length && !isRecursiveInvocation(pack.name)) {
		logInfo("Running pre-generate commands for %s...", pack.name);
		runBuildCommands(buildsettings.preGenerateCommands, pack, proj, settings, buildsettings);
	}
}

/**
	Runs post-build commands and copies required files to the binary directory.
*/
private void finalizeGeneration(in Package pack, in Project proj, in GeneratorSettings settings,
	in BuildSettings buildsettings, Path target_path, bool generate_binary)
{
	import std.path : globMatch;

	if (buildsettings.postGenerateCommands.length && !isRecursiveInvocation(pack.name)) {
		logInfo("Running post-generate commands for %s...", pack.name);
		runBuildCommands(buildsettings.postGenerateCommands, pack, proj, settings, buildsettings);
	}

	if (generate_binary) {
		if (!exists(buildsettings.targetPath))
			mkdirRecurse(buildsettings.targetPath);

		if (buildsettings.copyFiles.length) {
			void copyFolderRec(Path folder, Path dstfolder)
			{
				mkdirRecurse(dstfolder.toNativeString());
				foreach (de; iterateDirectory(folder.toNativeString())) {
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
				auto src = Path(file);
				if (!src.absolute) src = pack.path ~ src;
				auto dst = target_path ~ Path(file).head;
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
				auto src = Path(file);
				if (!src.absolute) src = pack.path ~ src;
				auto dst = target_path ~ Path(file).head;
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
			string[] globs;
			foreach (f; buildsettings.copyFiles)
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
						tryCopyDir(f);
					else
						tryCopyFile(f);
				}
			}
			if (globs.length) // Search all files for glob matches
			{
				foreach (f; dirEntries(pack.path.toNativeString(), SpanMode.breadth))
				{
					foreach (glob; globs)
					{
						if (f.name().globMatch(glob))
						{
							if (f.isDir)
								tryCopyDir(f);
							else
								tryCopyFile(f);
							break;
						}
					}
				}
			}
		}

	}
}


/** Runs a list of build commands for a particular package.

	This function sets all DUB speficic environment variables and makes sure
	that recursive dub invocations are detected and don't result in infinite
	command execution loops. The latter could otherwise happen when a command
	runs "dub describe" or similar functionality.
*/
void runBuildCommands(in string[] commands, in Package pack, in Project proj,
	in GeneratorSettings settings, in BuildSettings build_settings)
{
	import std.conv;
	import std.process;
	import dub.internal.utils;

	string[string] env = environment.toAA();
	// TODO: do more elaborate things here
	// TODO: escape/quote individual items appropriately
	env["DFLAGS"]                = join(cast(string[])build_settings.dflags, " ");
	env["LFLAGS"]                = join(cast(string[])build_settings.lflags," ");
	env["VERSIONS"]              = join(cast(string[])build_settings.versions," ");
	env["LIBS"]                  = join(cast(string[])build_settings.libs," ");
	env["IMPORT_PATHS"]          = join(cast(string[])build_settings.importPaths," ");
	env["STRING_IMPORT_PATHS"]   = join(cast(string[])build_settings.stringImportPaths," ");

	env["DC"]                    = settings.platform.compilerBinary;
	env["DC_BASE"]               = settings.platform.compiler;
	env["D_FRONTEND_VER"]        = to!string(settings.platform.frontendVersion);

	env["DUB_PLATFORM"]          = join(cast(string[])settings.platform.platform," ");
	env["DUB_ARCH"]              = join(cast(string[])settings.platform.architecture," ");

	env["DUB_TARGET_TYPE"]       = to!string(build_settings.targetType);
	env["DUB_TARGET_PATH"]       = build_settings.targetPath;
	env["DUB_TARGET_NAME"]       = build_settings.targetName;
	env["DUB_WORKING_DIRECTORY"] = build_settings.workingDirectory;
	env["DUB_MAIN_SOURCE_FILE"]  = build_settings.mainSourceFile;

	env["DUB_CONFIG"]            = settings.config;
	env["DUB_BUILD_TYPE"]        = settings.buildType;
	env["DUB_BUILD_MODE"]        = to!string(settings.buildMode);
	env["DUB_PACKAGE"]           = pack.name;
	env["DUB_PACKAGE_DIR"]       = pack.path.toNativeString();
	env["DUB_ROOT_PACKAGE"]      = proj.rootPackage.name;
	env["DUB_ROOT_PACKAGE_DIR"]  = proj.rootPackage.path.toNativeString();

	env["DUB_COMBINED"]          = settings.combined?      "TRUE" : "";
	env["DUB_RUN"]               = settings.run?           "TRUE" : "";
	env["DUB_FORCE"]             = settings.force?         "TRUE" : "";
	env["DUB_DIRECT"]            = settings.direct?        "TRUE" : "";
	env["DUB_RDMD"]              = settings.rdmd?          "TRUE" : "";
	env["DUB_TEMP_BUILD"]        = settings.tempBuild?     "TRUE" : "";
	env["DUB_PARALLEL_BUILD"]    = settings.parallelBuild? "TRUE" : "";

	env["DUB_RUN_ARGS"] = (cast(string[])settings.runArgs).map!(escapeShellFileName).join(" ");

	auto depNames = proj.dependencies.map!((a) => a.name).array();
	storeRecursiveInvokations(env, proj.rootPackage.name ~ depNames);
	runCommands(commands, env);
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

private void storeRecursiveInvokations(string[string] env, string[] packs)
{
	import std.algorithm : canFind, splitter;
	import std.range : chain;
	import std.process : environment;

    env["DUB_PACKAGES_USED"] = environment
        .get("DUB_PACKAGES_USED", "")
        .splitter(",")
        .chain(packs)
        .join(",");
}
