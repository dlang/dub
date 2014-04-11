/**
	Generator for project files
	
	Copyright: © 2012-2013 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.generators.generator;

import dub.compilers.compiler;
import dub.generators.build;
import dub.generators.visuald;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.inet.path;
import dub.package_;
import dub.packagemanager;
import dub.project;

import std.algorithm : map, filter, canFind;
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
	struct TargetInfo {
		Package pack;
		Package[] packages;
		string config;
		BuildSettings buildSettings;
		string[] dependencies;
		string[] linkDependencies;
	}

	protected {
		Project m_project;
	}

	this(Project project)
	{
		m_project = project;
	}

	void generate(GeneratorSettings settings)
	{
		if (!settings.config.length) settings.config = m_project.getDefaultConfiguration(settings.platform);

		TargetInfo[string] targets;
		string[string] configs = m_project.getPackageConfigs(settings.platform, settings.config);

		foreach (pack; m_project.getTopologicalPackageList(true, null, configs)) {
			auto buildsettings = pack.getBuildSettings(settings.platform, configs[pack.name]);
			prepareGeneration(pack.name, buildsettings);
		}

		string[] mainfiles;
		collect(settings, m_project.rootPackage, targets, configs, mainfiles, null);
		downwardsInheritSettings(m_project.rootPackage.name, targets, targets[m_project.rootPackage.name].buildSettings);
		auto bs = &targets[m_project.rootPackage.name].buildSettings;
		if (bs.targetType == TargetType.executable) bs.addSourceFiles(mainfiles);

		generateTargets(settings, targets);

		foreach (pack; m_project.getTopologicalPackageList(true, null, configs)) {
			auto buildsettings = pack.getBuildSettings(settings.platform, configs[pack.name]);
			bool generate_binary = !(buildsettings.options & BuildOptions.syntaxOnly);
			finalizeGeneration(pack.name, buildsettings, generate_binary);
		}
	}

	abstract void generateTargets(GeneratorSettings settings, in TargetInfo[string] targets);

	private BuildSettings collect(GeneratorSettings settings, Package pack, ref TargetInfo[string] targets, in string[string] configs, ref string[] main_files, string bin_pack)
	{
		if (auto pt = pack.name in targets) return pt.buildSettings;

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
			logWarn(`Package %s contains no source files. Please add {"targetType": "none"} to it's package description to avoid building it.`,
				pack.name);
			tt = TargetType.none;
		}


		shallowbs.targetType = tt;
		bool generates_binary = tt != TargetType.sourceLibrary && tt != TargetType.none;

		enforce (generates_binary || pack !is m_project.rootPackage,
			format("Main package must have a binary target type, not %s. Cannot build.", tt));

		if (tt == TargetType.none) {
			// ignore any build settings for targetType none (only dependencies will be processed)
			shallowbs = BuildSettings.init;
		}

		// start to build up the build settings
		BuildSettings buildsettings = settings.buildSettings.dup;
		processVars(buildsettings, pack.path.toNativeString(), shallowbs, true);

		// remove any mainSourceFile from library builds
		if (buildsettings.targetType != TargetType.executable && buildsettings.mainSourceFile.length) {
			buildsettings.sourceFiles = buildsettings.sourceFiles.filter!(f => f != buildsettings.mainSourceFile)().array;
			main_files ~= buildsettings.mainSourceFile;
		}

		logDiagnostic("Generate target %s (%s %s %s)", pack.name, buildsettings.targetType, buildsettings.targetPath, buildsettings.targetName);
		if (generates_binary)
			targets[pack.name] = TargetInfo(pack, [pack], configs[pack.name], buildsettings, null);

		foreach (depname, depspec; pack.dependencies) {
			if (!pack.hasDependency(depname, configs[pack.name])) continue;
			auto dep = m_project.getDependency(depname, depspec.optional);
			if (!dep) continue;

			auto depbs = collect(settings, dep, targets, configs, main_files, generates_binary ? pack.name : bin_pack);

			if (depbs.targetType != TargetType.sourceLibrary && depbs.targetType != TargetType.none) {
				// add a reference to the target binary and remove all source files in the dependency build settings
				depbs.sourceFiles = depbs.sourceFiles.filter!(f => f.isLinkerFile()).array;
				depbs.importFiles = null;
			}

			buildsettings.add(depbs);

			auto pt = (generates_binary ? pack.name : bin_pack) in targets;
			assert(pt !is null);
			if (auto pdt = depname in targets) {
				pt.dependencies ~= depname;
				pt.linkDependencies ~= depname;
				if (depbs.targetType == TargetType.staticLibrary)
					pt.linkDependencies = pt.linkDependencies.filter!(d => !pdt.linkDependencies.canFind(d)).array ~ pdt.linkDependencies;
			} else pt.packages ~= dep;
		}

		if (generates_binary) {
			// add build type settings and convert plain DFLAGS to build options
			m_project.addBuildTypeSettings(buildsettings, settings.platform, settings.buildType);
			settings.compiler.extractBuildOptions(buildsettings);
			enforceBuildRequirements(buildsettings);
			targets[pack.name].buildSettings = buildsettings.dup;
		}

		return buildsettings;
	}

	private string[] downwardsInheritSettings(string target, TargetInfo[string] targets, in BuildSettings root_settings)
	{
		auto ti = &targets[target];
		ti.buildSettings.addVersions(root_settings.versions);
		ti.buildSettings.addDebugVersions(root_settings.debugVersions);
		ti.buildSettings.addOptions(root_settings.options);

		// special support for overriding string imports in parent packages
		// this is a candidate for deprecation, once an alternative approach
		// has been found
		if (ti.buildSettings.stringImportPaths.length)
			ti.buildSettings.prependStringImportPaths(root_settings.stringImportPaths);

		string[] packs = ti.packages.map!(p => p.name).array;
		foreach (d; ti.dependencies)
			packs ~= downwardsInheritSettings(d, targets, root_settings);

		logDebug("%s: %s", target, packs);

		// Add Have_* versions *after* downwards inheritance, so that dependencies
		// are build independently of the parent packages w.r.t the other parent
		// dependencies. This enables sharing of the same package build for
		// multiple dependees.
		ti.buildSettings.addVersions(packs.map!(pn => "Have_" ~ stripDlangSpecialChars(pn)).array);

		return packs;
	}
}


struct GeneratorSettings {
	BuildPlatform platform;
	Compiler compiler;
	string config;
	string buildType;
	BuildSettings buildSettings;

	bool combined; // compile all in one go instead of each dependency separately

	// only used for generator "build"
	bool run, force, direct, clean, rdmd;
	string[] runArgs;
	void delegate(int status, string output) compileCallback;
	void delegate(int status, string output) linkCallback;
	void delegate(int status, string output) runCallback;
}


/**
	Creates a project generator of the given type for the specified project.
*/
ProjectGenerator createProjectGenerator(string generator_type, Project app, PackageManager mgr)
{
	assert(app !is null && mgr !is null, "Project and package manager needed to create a generator.");

	generator_type = generator_type.toLower();
	switch(generator_type) {
		default:
			throw new Exception("Unknown project generator: "~generator_type);
		case "build":
			logDebug("Creating build generator.");
			return new BuildGenerator(app, mgr);
		case "mono-d":
			throw new Exception("The Mono-D generator has been removed. Use Mono-D's built in DUB support instead.");
		case "visuald":
			logDebug("Creating VisualD generator.");
			return new VisualDGenerator(app, mgr);
	}
}


/**
	Runs pre-build commands and performs other required setup before project files are generated.
*/
private void prepareGeneration(string pack, in BuildSettings buildsettings)
{
	if( buildsettings.preGenerateCommands.length ){
		logInfo("Running pre-generate commands for %s...", pack);
		runBuildCommands(buildsettings.preGenerateCommands, buildsettings);
	}
}

/**
	Runs post-build commands and copies required files to the binary directory.
*/
private void finalizeGeneration(string pack, in BuildSettings buildsettings, bool generate_binary)
{
	if (buildsettings.postGenerateCommands.length) {
		logInfo("Running post-generate commands for %s...", pack);
		runBuildCommands(buildsettings.postGenerateCommands, buildsettings);
	}

	if (generate_binary) {
		if (!exists(buildsettings.targetPath))
			mkdirRecurse(buildsettings.targetPath);
		
		if (buildsettings.copyFiles.length) {
			logInfo("Copying files for %s...", pack);
			foreach (f; buildsettings.copyFiles) {
				auto src = Path(f);
				auto dst = Path(buildsettings.targetPath) ~ Path(f).head;
				logDiagnostic("  %s to %s", src.toNativeString(), dst.toNativeString());
				try {
					copyFile(src, dst, true);
				} catch logWarn("Failed to copy to %s", dst.toNativeString());
			}
		}
	}
}

void runBuildCommands(in string[] commands, in BuildSettings build_settings)
{
	import std.process;
	import dub.internal.utils;

	string[string] env = environment.toAA();
	// TODO: do more elaborate things here
	// TODO: escape/quote individual items appropriately
	env["DFLAGS"] = join(cast(string[])build_settings.dflags, " ");
	env["LFLAGS"] = join(cast(string[])build_settings.lflags," ");
	env["VERSIONS"] = join(cast(string[])build_settings.versions," ");
	env["LIBS"] = join(cast(string[])build_settings.libs," ");
	env["IMPORT_PATHS"] = join(cast(string[])build_settings.importPaths," ");
	env["STRING_IMPORT_PATHS"] = join(cast(string[])build_settings.stringImportPaths," ");
	runCommands(commands, env);
}
