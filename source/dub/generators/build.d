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

	this(Project app, PackageManager mgr)
	{
		super(app);
		m_project = app;
		m_packageMan = mgr;
	}

	override void generateTargets(GeneratorSettings settings, in TargetInfo[string] targets)
	{
		scope (exit) cleanupTemporaries();

		bool[string] visited;
		void buildTargetRec(string target)
		{
			if (target in visited) return;
			visited[target] = true;

			auto ti = targets[target];

			foreach (dep; ti.dependencies)
				buildTargetRec(dep);

			auto bs = ti.buildSettings.dup;
			if (bs.targetType != TargetType.staticLibrary)
				foreach (ldep; ti.linkDependencies) {
					auto dbs = targets[ldep].buildSettings;
					bs.addSourceFiles((Path(dbs.targetPath) ~ getTargetFileName(dbs, settings.platform)).toNativeString());
				}
			buildTarget(settings, bs, ti.pack, ti.config);
		}

		// build all targets
		buildTargetRec(m_project.mainPackage.name);

		// run the generated executable
		auto buildsettings = targets[m_project.mainPackage.name].buildSettings;
		if (settings.run && !(buildsettings.options & BuildOptions.syntaxOnly)) {
			auto exe_file_path = Path(buildsettings.targetPath) ~ getTargetFileName(buildsettings, settings.platform);
			runTarget(exe_file_path, buildsettings, settings.runArgs);
		}
	}

	private void buildTarget(GeneratorSettings settings, BuildSettings buildsettings, in Package pack, string config)
	{
		auto cwd = Path(getcwd());
		bool generate_binary = !(buildsettings.options & BuildOptions.syntaxOnly);

		auto build_id = computeBuildID(config, buildsettings, settings);

		// make all paths relative to shrink the command line
		string makeRelative(string path) { auto p = Path(path); if (p.absolute) p = p.relativeTo(cwd); return p.toNativeString(); }
		foreach (ref f; buildsettings.sourceFiles) f = makeRelative(f);
		foreach (ref p; buildsettings.importPaths) p = makeRelative(p);
		foreach (ref p; buildsettings.stringImportPaths) p = makeRelative(p);

		// perform the actual build
		if (settings.rdmd) performRDMDBuild(settings, buildsettings, pack, config);
		else if (settings.direct || !generate_binary) performDirectBuild(settings, buildsettings, pack, config);
		else performCachedBuild(settings, buildsettings, pack, config, build_id);

		// run post-build commands
		if (buildsettings.postBuildCommands.length) {
			logInfo("Running post-build commands...");
			runBuildCommands(buildsettings.postBuildCommands, buildsettings);
		}
	}

	void performCachedBuild(GeneratorSettings settings, BuildSettings buildsettings, in Package pack, string config, string build_id)
	{
		auto cwd = Path(getcwd());
		auto target_path = pack.path ~ format(".dub/build/%s/", build_id);

		if (!settings.force && isUpToDate(target_path, buildsettings, settings.platform)) {
			logInfo("Target is up to date. Using existing build in %s. Use --force to force a rebuild.", target_path.toNativeString());
			copyTargetFile(target_path, buildsettings, settings.platform);
			return;
		}

		if (!isWritableDir(target_path, true)) {
			logInfo("Build directory %s is not writable. Falling back to direct build in the system's temp folder.", target_path.relativeTo(cwd).toNativeString());
			performDirectBuild(settings, buildsettings, pack, config);
			return;
		}

		// determine basic build properties
		auto generate_binary = !(buildsettings.options & BuildOptions.syntaxOnly);

		// run pre-/post-generate commands and copy "copyFiles"
		prepareGeneration(buildsettings);
		finalizeGeneration(buildsettings, generate_binary);

		logInfo("Building %s configuration \"%s\", build type %s.", pack.name, config, settings.buildType);

		if( buildsettings.preBuildCommands.length ){
			logInfo("Running pre-build commands...");
			runBuildCommands(buildsettings.preBuildCommands, buildsettings);
		}

		// override target path
		auto cbuildsettings = buildsettings;
		cbuildsettings.targetPath = target_path.relativeTo(cwd).toNativeString();
		buildWithCompiler(settings, cbuildsettings);

		copyTargetFile(target_path, buildsettings, settings.platform);
	}

	void performRDMDBuild(GeneratorSettings settings, ref BuildSettings buildsettings, in Package pack, string config)
	{
		auto cwd = Path(getcwd());
		//Added check for existance of [AppNameInPackagejson].d
		//If exists, use that as the starting file.
		auto mainsrc = buildsettings.mainSourceFile.length ? pack.path ~ buildsettings.mainSourceFile : getMainSourceFile(pack);

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
		if (settings.force) flags ~= "--force";
		flags ~= buildsettings.dflags;
		flags ~= mainsrc.relativeTo(cwd).toNativeString();

		prepareGeneration(buildsettings);
		finalizeGeneration(buildsettings, generate_binary);

		if (buildsettings.preBuildCommands.length){
			logInfo("Running pre-build commands...");
			runCommands(buildsettings.preBuildCommands);
		}

		logInfo("Building configuration "~config~", build type "~settings.buildType);

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

	void performDirectBuild(GeneratorSettings settings, ref BuildSettings buildsettings, in Package pack, string config)
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

		logInfo("Building configuration \""~config~"\", build type "~settings.buildType);

		prepareGeneration(buildsettings);

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

	private string computeBuildID(string config, in BuildSettings buildsettings, GeneratorSettings settings)
	{
		import std.digest.digest;
		import std.digest.md;
		MD5 hash;
		hash.start();
		void addHash(in string[] strings...) { foreach (s; strings) { hash.put(cast(ubyte[])s); hash.put(0); } hash.put(0); }
		addHash(buildsettings.versions);
		addHash(buildsettings.debugVersions);
		//addHash(buildsettings.versionLevel);
		//addHash(buildsettings.debugLevel);
		addHash(buildsettings.dflags);
		addHash(buildsettings.lflags);
		addHash((cast(uint)buildsettings.options).to!string);
		addHash(buildsettings.stringImportPaths);
		addHash(settings.platform.architecture);
		addHash(settings.platform.compiler);
		//addHash(settings.platform.frontendVersion);
		auto hashstr = hash.finish().toHexString().idup;

		return format("%s-%s-%s-%s-%s-%s", config, settings.buildType,
			settings.platform.platform.join("."),
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
		if (!existsFile(targetfile)) {
			logDiagnostic("Target '%s' doesn't exist, need rebuild.", targetfile.toNativeString());
			return false;
		}
		auto targettime = getFileInfo(targetfile).timeModified;

		auto allfiles = appender!(string[]);
		allfiles ~= buildsettings.sourceFiles;
		allfiles ~= buildsettings.importFiles;
		allfiles ~= buildsettings.stringImportFiles;
		// TODO: add library files
		/*foreach (p; m_project.getTopologicalPackageList())
			allfiles ~= p.packageInfoFile.toNativeString();*/

		foreach (file; allfiles.data) {
			auto ftime = getFileInfo(file).timeModified;
			if (ftime > Clock.currTime)
				logWarn("File '%s' was modified in the future. Please re-save.", file);
			if (ftime > targettime) {
				logDiagnostic("File '%s' modified, need rebuild.", file);
				return false;
			}
		}
		return true;
	}

	void buildWithCompiler(GeneratorSettings settings, BuildSettings buildsettings)
	{
		auto generate_binary = !(buildsettings.options & BuildOptions.syntaxOnly);
		auto is_static_library = buildsettings.targetType == TargetType.staticLibrary || buildsettings.targetType == TargetType.library;

		Path target_file;
		scope (failure) {
			logInfo("FAIL %s %s %s" , buildsettings.targetPath, buildsettings.targetName, buildsettings.targetType);
			auto tpath = Path(buildsettings.targetPath) ~ getTargetFileName(buildsettings, settings.platform);
			if (generate_binary && existsFile(tpath))
				removeFile(tpath);
		}

		/*
			NOTE: for DMD experimental separate compile/link is used, but this is not yet implemented
			      on the other compilers. Later this should be integrated somehow in the build process
			      (either in the package.json, or using a command line flag)
		*/
		if (settings.platform.compilerBinary != "dmd" || !generate_binary || is_static_library) {
			// setup for command line
			if (generate_binary) settings.compiler.setTarget(buildsettings, settings.platform);
			settings.compiler.prepareBuildSettings(buildsettings, BuildSetting.commandLine);

			// don't include symbols of dependencies (will be included by the top level target)
			if (is_static_library) buildsettings.sourceFiles = buildsettings.sourceFiles.filter!(f => !f.isLinkerFile()).array;

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
			settings.compiler.setTarget(lbuildsettings, settings.platform);
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

	void runTarget(Path exe_file_path, in BuildSettings buildsettings, string[] run_args)
	{
		if (buildsettings.targetType == TargetType.executable) {
			auto cwd = Path(getcwd());
			auto runcwd = cwd;
			if (buildsettings.workingDirectory.length) {
				runcwd = Path(buildsettings.workingDirectory);
				if (!runcwd.absolute) runcwd = cwd ~ runcwd;
				logDiagnostic("Switching to %s", runcwd.toNativeString());
				chdir(runcwd.toNativeString());
			}
			scope(exit) chdir(cwd.toNativeString());
			if (!exe_file_path.absolute) exe_file_path = cwd ~ exe_file_path;
			auto exe_path_string = exe_file_path.relativeTo(runcwd).toNativeString();
			version (Posix) {
				if (!exe_path_string.startsWith(".") && !exe_path_string.startsWith("/"))
					exe_path_string = "./" ~ exe_path_string;
			}
			version (Windows) {
				if (!exe_path_string.startsWith(".") && (exe_path_string.length < 2 || exe_path_string[1] != ':'))
					exe_path_string = ".\\" ~ exe_path_string;
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

private Path getMainSourceFile(in Package prj)
{
	foreach (f; ["source/app.d", "src/app.d", "source/"~prj.name~".d", "src/"~prj.name~".d"])
		if (existsFile(prj.path ~ f))
			return prj.path ~ f;
	return prj.path ~ "source/app.d";
}

unittest {
	version (Windows) {
		assert(isLinkerFile("test.obj"));
		assert(isLinkerFile("test.lib"));
		assert(isLinkerFile("test.res"));
		assert(!isLinkerFile("test.o"));
		assert(!isLinkerFile("test.d"));
	} else {
		assert(isLinkerFile("test.o"));
		assert(isLinkerFile("test.a"));
		assert(isLinkerFile("test.so"));
		assert(isLinkerFile("test.dylib"));
		assert(!isLinkerFile("test.obj"));
		assert(!isLinkerFile("test.d"));
	}
}