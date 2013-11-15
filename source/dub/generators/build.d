/**
	Generator for direct compiler builds.
	
	Copyright: © 2013-2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.generators.build;

import dub.compilers.compiler;
import dub.generators.generator;
import dub.internal.utils;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.inet.path;
import dub.package_;
import dub.packagemanager;
import dub.project;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.process;
import std.string;


class BuildGenerator : ProjectGenerator {
	private {
		Project m_project;
		PackageManager m_packageMan;
		Path[] m_temporaryFiles;
	}

	bool useRDMD = false;
	
	this(Project app, PackageManager mgr)
	{
		m_project = app;
		m_packageMan = mgr;
	}

	void generateProject(GeneratorSettings settings)
	{
		scope(exit) cleanupTemporaries();

		auto cwd = Path(getcwd());
		if (!settings.config.length) settings.config = m_project.getDefaultConfiguration(settings.platform);

		auto buildsettings = settings.buildSettings;
		m_project.addBuildSettings(buildsettings, settings.platform, settings.config, null, settings.buildType == "ddox");
		m_project.addBuildTypeSettings(buildsettings, settings.platform, settings.buildType);

		// make all paths relative to shrink the command line
		string makeRelative(string path) { auto p = Path(path); if (p.absolute) p = p.relativeTo(cwd); return p.toNativeString(); }
		foreach (ref f; buildsettings.sourceFiles) f = makeRelative(f);
		foreach (ref p; buildsettings.importPaths) p = makeRelative(p);
		foreach (ref p; buildsettings.stringImportPaths) p = makeRelative(p);

		// perform the actual build
		if (this.useRDMD) performRDMDBuild(settings, buildsettings);
		else if (settings.direct) performDirectBuild(settings, buildsettings);
		else performCachedBuild(settings, buildsettings);

		// run post-build commands
		if (buildsettings.postBuildCommands.length) {
			logInfo("Running post-build commands...");
			runBuildCommands(buildsettings.postBuildCommands, buildsettings);
		}

		// run the generated executable
		if (!(buildsettings.options & BuildOptions.syntaxOnly) && settings.run) {
			auto exe_file_path = Path(buildsettings.targetPath) ~ getTargetFileName(buildsettings, settings.platform);
			runTarget(exe_file_path, buildsettings, settings.runArgs);
		}
	}

	void performCachedBuild(GeneratorSettings settings, BuildSettings buildsettings)
	{
		auto cwd = Path(getcwd());
		auto build_id = computeBuildID(settings);
		auto target_path = m_project.mainPackage.path ~ format(".dub/build/%s/", build_id);

		if (isUpToDate(target_path, buildsettings, settings.platform)) {
			logInfo("Target is up to date. Skipping build.");
			copyTargetFile(target_path, buildsettings, settings.platform);
			return;
		}

		if (!isWritableDir(target_path, true)) {
			logInfo("Build directory %s is not writable. Falling back to direct build in the system's temp folder.", target_path.relativeTo(cwd).toNativeString());
			performDirectBuild(settings, buildsettings);
			return;
		}

		// determine basic build properties
		auto generate_binary = !(buildsettings.options & BuildOptions.syntaxOnly);

		// run pre-/post-generate commands and copy "copyFiles"
		prepareGeneration(buildsettings);
		finalizeGeneration(buildsettings, generate_binary);

		logInfo("Building configuration \""~settings.config~"\", build type "~settings.buildType);

		if( buildsettings.preBuildCommands.length ){
			logInfo("Running pre-build commands...");
			runBuildCommands(buildsettings.preBuildCommands, buildsettings);
		}

		// override target path
		auto cbuildsettings = buildsettings;
		cbuildsettings.targetPath = target_path.relativeTo(cwd).toNativeString();
		if (generate_binary) settings.compiler.setTarget(cbuildsettings, settings.platform);
		buildWithCompiler(settings, cbuildsettings);

		copyTargetFile(target_path, buildsettings, settings.platform);
	}

	void performRDMDBuild(GeneratorSettings settings, ref BuildSettings buildsettings)
	{
		//Added check for existance of [AppNameInPackagejson].d
		//If exists, use that as the starting file.
		auto mainsrc = getMainSourceFile(m_project);

		// do not pass all source files to RDMD, only the main source file
		buildsettings.sourceFiles = buildsettings.sourceFiles.filter!(s => !s.endsWith(".d"))().array();
		settings.compiler.prepareBuildSettings(buildsettings, BuildSetting.commandLine);

		auto generate_binary = !buildsettings.dflags.canFind("-o-");

		// Create start script, which will be used by the calling bash/cmd script.
		// build "rdmd --force %DFLAGS% -I%~dp0..\source -Jviews -Isource @deps.txt %LIBS% source\app.d" ~ application arguments
		// or with "/" instead of "\"
		Path exe_file_path;
		bool tmp_target = false;
		if (generate_binary) {
			if (settings.run && !isWritableDir(Path(buildsettings.targetPath), true)) {
				import std.random;
				auto rnd = to!string(uniform(uint.min, uint.max)) ~ "-";
				auto tmpdir = getTempDir()~".rdmd/source/";
				buildsettings.targetPath = tmpdir.toNativeString();
				buildsettings.targetName = rnd ~ buildsettings.targetName;
				m_temporaryFiles ~= tmpdir;
				tmp_target = true;
			}
			exe_file_path = Path(buildsettings.targetPath) ~ getTargetFileName(buildsettings, settings.platform);
			settings.compiler.setTarget(buildsettings, settings.platform);
		}

		logDiagnostic("Application output name is '%s'", getTargetFileName(buildsettings, settings.platform));

		string[] flags = ["--build-only", "--compiler="~settings.platform.compilerBinary];
		flags ~= buildsettings.dflags;
		flags ~= (mainsrc).toNativeString();

		prepareGeneration(buildsettings);
		finalizeGeneration(buildsettings, generate_binary);

		if (buildsettings.preBuildCommands.length){
			logInfo("Running pre-build commands...");
			runCommands(buildsettings.preBuildCommands);
		}

		logInfo("Building configuration "~settings.config~", build type "~settings.buildType);

		logInfo("Running rdmd...");
		logDiagnostic("rdmd %s", join(flags, " "));
		auto rdmd_pid = spawnProcess("rdmd" ~ flags);
		auto result = rdmd_pid.wait();
		enforce(result == 0, "Build command failed with exit code "~to!string(result));

		if (tmp_target) {
			m_temporaryFiles ~= exe_file_path;
			foreach (f; buildsettings.copyFiles)
				m_temporaryFiles ~= Path(buildsettings.targetPath).parentPath ~ Path(f).head;
		}
	}

	void performDirectBuild(GeneratorSettings settings, ref BuildSettings buildsettings)
	{
		auto cwd = Path(getcwd());

		auto generate_binary = !(buildsettings.options & BuildOptions.syntaxOnly);
		auto is_static_library = buildsettings.targetType == TargetType.staticLibrary || buildsettings.targetType == TargetType.library;

		// make file paths relative to shrink the command line
		foreach (ref f; buildsettings.sourceFiles) {
			auto fp = Path(f);
			if( fp.absolute ) fp = fp.relativeTo(cwd);
			f = fp.toNativeString();
		}

		logInfo("Building configuration \""~settings.config~"\", build type "~settings.buildType);

		prepareGeneration(buildsettings);

		// determine the absolute target path
		if (!Path(buildsettings.targetPath).absolute)
			buildsettings.targetPath = (m_project.mainPackage.path ~ Path(buildsettings.targetPath)).toNativeString();

		// make all target/import paths relative
		string makeRelative(string path) { auto p = Path(path); if (p.absolute) p = p.relativeTo(cwd); return p.toNativeString(); }
		buildsettings.targetPath = makeRelative(buildsettings.targetPath);
		foreach (ref p; buildsettings.importPaths) p = makeRelative(p);
		foreach (ref p; buildsettings.stringImportPaths) p = makeRelative(p);

		Path exe_file_path;
		bool is_temp_target = false;
		if (generate_binary) {
			if (settings.run && !isWritableDir(Path(buildsettings.targetPath), true)) {
				import std.random;
				auto rnd = to!string(uniform(uint.min, uint.max));
				auto tmppath = getTempDir()~("dub/"~rnd~"/");
				buildsettings.targetPath = tmppath.toNativeString();
				m_temporaryFiles ~= tmppath;
				is_temp_target = true;
			}
			exe_file_path = Path(buildsettings.targetPath) ~ getTargetFileName(buildsettings, settings.platform);
			settings.compiler.setTarget(buildsettings, settings.platform);
		}

		finalizeGeneration(buildsettings, generate_binary);

		if( buildsettings.preBuildCommands.length ){
			logInfo("Running pre-build commands...");
			runBuildCommands(buildsettings.preBuildCommands, buildsettings);
		}

		buildWithCompiler(settings, buildsettings);

		if (is_temp_target) {
			m_temporaryFiles ~= exe_file_path;
			foreach (f; buildsettings.copyFiles)
				m_temporaryFiles ~= Path(buildsettings.targetPath).parentPath ~ Path(f).head;
		}
	}

	private string computeBuildID(GeneratorSettings settings)
	{
		import std.digest.digest;
		import std.digest.sha;
		SHA1 hash;
		hash.start();
		// ...
		auto hashstr = hash.finish().toHexString().idup;

		return format("%s-%s-%s-%s-%s", settings.config, settings.buildType,
			settings.platform.architecture.join("."),
			settings.platform.compilerBinary, hashstr);
	}

	private void copyTargetFile(Path build_path, BuildSettings buildsettings, BuildPlatform platform)
	{
		auto filename = getTargetFileName(buildsettings, platform);
		auto src = build_path ~ filename;
		logDiagnostic("Copying target from %s to %s", src.toNativeString(), buildsettings.targetPath);
		copyFile(src, Path(buildsettings.targetPath) ~ filename, true);
	}

	private bool isUpToDate(Path target_path, BuildSettings buildsettings, BuildPlatform platform)
	{
		import std.datetime;

		auto targetfile = target_path ~ getTargetFileName(buildsettings, platform);
		if (!existsFile(targetfile)) return false;
		auto targettime = getFileInfo(targetfile).timeModified;

		auto allfiles = appender!(string[]);
		allfiles ~= buildsettings.sourceFiles;
		allfiles ~= buildsettings.importFiles;
		allfiles ~= buildsettings.stringImportFiles;
		foreach (p; m_project.getTopologicalPackageList())
			allfiles ~= p.packageInfoFile.toNativeString();

		foreach (file; allfiles.data) {
			auto ftime = getFileInfo(file).timeModified;
			if (ftime > Clock.currTime)
				logWarn("File '%s' was modified in the future. Please re-save.");
			if (ftime > targettime)
				return false;
		}
		return true;
	}

	void buildWithCompiler(GeneratorSettings settings, BuildSettings buildsettings)
	{
		auto generate_binary = !(buildsettings.options & BuildOptions.syntaxOnly);
		auto is_static_library = buildsettings.targetType == TargetType.staticLibrary || buildsettings.targetType == TargetType.library;

		/*
			NOTE: for DMD experimental separate compile/link is used, but this is not yet implemented
			      on the other compilers. Later this should be integrated somehow in the build process
			      (either in the package.json, or using a command line flag)
		*/
		if (settings.platform.compilerBinary != "dmd" || !generate_binary || is_static_library) {
			// setup for command line
			settings.compiler.prepareBuildSettings(buildsettings, BuildSetting.commandLine);

			// invoke the compiler
			logInfo("Running %s...", settings.platform.compilerBinary);
			settings.compiler.invoke(buildsettings, settings.platform);
		} else {
			// determine path for the temporary object file
			string tempobjname = buildsettings.targetName;
			version(Windows) tempobjname ~= ".obj";
			else tempobjname ~= ".o";
			Path tempobj = Path(buildsettings.targetPath) ~ tempobjname;

			// setup linker command line
			auto lbuildsettings = buildsettings;
			lbuildsettings.sourceFiles = lbuildsettings.sourceFiles.filter!(f => isLinkerFile(f)).array;
			settings.compiler.prepareBuildSettings(lbuildsettings, BuildSetting.commandLineSeparate|BuildSetting.sourceFiles);

			// setup compiler command line
			buildsettings.libs = null;
			buildsettings.lflags = null;
			buildsettings.addDFlags("-c", "-of"~tempobj.toNativeString());
			buildsettings.sourceFiles = buildsettings.sourceFiles.filter!(f => !isLinkerFile(f)).array;
			settings.compiler.prepareBuildSettings(buildsettings, BuildSetting.commandLine);

			logInfo("Compiling...");
			settings.compiler.invoke(buildsettings, settings.platform);

			logInfo("Linking...");
			settings.compiler.invokeLinker(lbuildsettings, settings.platform, [tempobj.toNativeString()]);
		}
	}

	void runTarget(Path exe_file_path, BuildSettings buildsettings, string[] run_args)
	{
		if (buildsettings.targetType == TargetType.executable) {
			auto cwd = Path(getcwd());
			auto runcwd = cwd;
			if (buildsettings.workingDirectory.length) {
				runcwd = cwd ~ buildsettings.workingDirectory;
				logDiagnostic("Switching to %s", runcwd.toNativeString());
				chdir(runcwd.toNativeString());
			}
			scope(exit) chdir(cwd.toNativeString());
			if (!exe_file_path.absolute) exe_file_path = cwd ~ exe_file_path;
			auto exe_path_string = exe_file_path.relativeTo(runcwd).toNativeString();
			version (OSX) { // spawnProcess on OS X requires an explicit path to the executable
				if (!exe_path_string.startsWith(".") && !exe_path_string.startsWith("/"))
					exe_path_string = "./" ~ exe_path_string;
			}
			logInfo("Running %s %s", exe_path_string, run_args.join(" "));
			auto prg_pid = spawnProcess(exe_path_string ~ run_args);
			auto result = prg_pid.wait();
			enforce(result == 0, "Program exited with code "~to!string(result));
		} else logInfo("Target is a library. Skipping execution.");
	}

	void cleanupTemporaries()
	{
		foreach_reverse (f; m_temporaryFiles) {
			try {
				if (f.endsWithSlash) rmdir(f.toNativeString());
				else remove(f.toNativeString());
			} catch (Exception e) {
				logWarn("Failed to remove temporary file '%s': %s", f.toNativeString(), e.msg);
				logDiagnostic("Full error: %s", e.toString().sanitize);
			}
		}
		m_temporaryFiles = null;
	}
}

private Path getMainSourceFile(in Project prj)
{
	foreach( f; ["source/app.d", "src/app.d", "source/"~prj.name~".d", "src/"~prj.name~".d"])
		if( exists(f) )
			return Path(f);
	return Path("source/app.d");
}

private bool isLinkerFile(string f)
{
	version (Windows) {
		return f.endsWith(".lib") || f.endsWith(".obj");
	} else {
		return f.endsWith(".a") || f.endsWith(".o") || f.endsWith(".so") || f.endsWith(".dylib");
	}
}
