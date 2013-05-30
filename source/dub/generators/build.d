/**
	Generator for direct compiler builds.
	
	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.generators.build;

import dub.compilers.compiler;
import dub.generators.generator;
import dub.internal.std.process;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.inet.path;
import dub.package_;
import dub.packagemanager;
import dub.project;
import dub.utils;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.string;


class BuildGenerator : ProjectGenerator {
	private {
		Project m_project;
		PackageManager m_pkgMgr;
	}
	
	this(Project app, PackageManager mgr)
	{
		m_project = app;
		m_pkgMgr = mgr;
	}
	
	void generateProject(GeneratorSettings settings)
	{
		auto cwd = Path(getcwd());

		auto buildsettings = settings.buildSettings;
		m_project.addBuildSettings(buildsettings, settings.platform, settings.config);
		bool usedefflags = !(buildsettings.requirements & BuildRequirements.noDefaultFlags);
		if (usedefflags) buildsettings.addDFlags(["-w"]);
		string dflags = environment.get("DFLAGS");
		if( dflags.length ){
			settings.buildType = "$DFLAGS";
			buildsettings.addDFlags(dflags.split());
		} else if (usedefflags) {
			addBuildTypeFlags(buildsettings, settings.buildType);
		}

		auto generate_binary = !buildsettings.dflags.canFind("-o-");
		auto is_static_library = buildsettings.targetType == TargetType.staticLibrary || buildsettings.targetType == TargetType.library;

		// make paths relative to shrink the command line
		foreach(ref f; buildsettings.sourceFiles){
			auto fp = Path(f);
			if( fp.absolute ) fp = fp.relativeTo(Path(getcwd()));
			f = fp.toNativeString();
		}

		// find the temp directory
		auto tmp = environment.get("TEMP");
		if( !tmp.length ) tmp = environment.get("TMP");
		if( !tmp.length ){
			version(Posix) tmp = "/tmp";
			else tmp = ".";
		}

		if( settings.config.length ) logInfo("Building configuration \""~settings.config~"\", build type "~settings.buildType);
		else logInfo("Building default configuration, build type "~settings.buildType);

		prepareGeneration(buildsettings);

		// determine the absolute target path
		if( !Path(buildsettings.targetPath).absolute )
			buildsettings.targetPath = (m_project.mainPackage.path ~ Path(buildsettings.targetPath)).toNativeString();

		Path exe_file_path;
		if( generate_binary ){
			if( settings.run ){
				import std.random;
				auto rnd = to!string(uniform(uint.min, uint.max));
				buildsettings.targetPath = (Path(tmp)~"dub/"~rnd).toNativeString();
			}
			exe_file_path = Path(buildsettings.targetPath) ~ getTargetFileName(buildsettings, settings.platform);
		}
		logDebug("Application output name is '%s'", exe_file_path.toNativeString());

		finalizeGeneration(buildsettings, generate_binary);

		if( buildsettings.preBuildCommands.length ){
			logInfo("Running pre-build commands...");
			runBuildCommands(buildsettings.preBuildCommands, buildsettings);
		}

		// assure that we clean up after ourselves
		Path[] cleanup_files;
		scope (exit) {
			foreach (f; cleanup_files)
				if (existsFile(f))
					remove(f.toNativeString());
			if (generate_binary && settings.run)
				rmdirRecurse(buildsettings.targetPath);
		}

		/*
			NOTE: for DMD experimental separate compile/link is used, but this is not yet implemented
			      on the other compilers. Later this should be integrated somehow in the build process
			      (either in the package.json, or using a command line flag)
		*/
		if (settings.compilerBinary != "dmd" || !generate_binary || is_static_library) {
			// setup for command line
			if( generate_binary ) settings.compiler.setTarget(buildsettings, settings.platform);
			settings.compiler.prepareBuildSettings(buildsettings, BuildSetting.commandLine);

			// write response file instead of passing flags directly to the compiler
			auto res_file = Path(buildsettings.targetPath) ~ ".dmd-response-file.txt";
			cleanup_files ~= res_file;
			std.file.write(res_file.toNativeString(), join(buildsettings.dflags, "\n"));

			// invoke the compiler
			logInfo("Running %s...", settings.compilerBinary);
			logDebug("%s %s", settings.compilerBinary, join(buildsettings.dflags, " "));
			if( settings.run ) cleanup_files ~= exe_file_path;
			auto compiler_pid = spawnProcess([settings.compilerBinary, "@"~res_file.toNativeString()]);
			auto result = compiler_pid.wait();
			enforce(result == 0, "Build command failed with exit code "~to!string(result));
		} else {
			// determine path for the temporary object file
			version(Windows) enum tempobjname = "temp.obj";
			else enum tempobjname = "temp.o";
			Path tempobj = Path(buildsettings.targetPath) ~ tempobjname;

			// setup linker command line
			auto lbuildsettings = buildsettings;
			lbuildsettings.sourceFiles = lbuildsettings.sourceFiles.filter!(f => f.endsWith(".lib"))().array();
			settings.compiler.prepareBuildSettings(lbuildsettings, BuildSetting.commandLineSeparate|BuildSetting.sourceFiles);

			// setup compiler command line
			buildsettings.libs = null;
			buildsettings.lflags = null;
			buildsettings.addDFlags("-c", "-of"~tempobj.toNativeString());
			buildsettings.sourceFiles = buildsettings.sourceFiles.filter!(f => !f.endsWith(".lib"))().array();
			settings.compiler.prepareBuildSettings(buildsettings, BuildSetting.commandLine);

			// write response file instead of passing flags directly to the compiler
			auto res_file = Path(buildsettings.targetPath) ~ ".dmd-response-file.txt";
			cleanup_files ~= res_file;
			cleanup_files ~= tempobj;
			std.file.write(res_file.toNativeString(), join(buildsettings.dflags, "\n"));

			logInfo("Running %s (compile)...", settings.compilerBinary);
			logDebug("%s %s", settings.compilerBinary, join(buildsettings.dflags, " "));
			auto result = spawnProcess([settings.compilerBinary, "@"~res_file.toNativeString()]).wait();
			enforce(result == 0, "Build command failed with exit code "~to!string(result));

			logInfo("Linking...", settings.compilerBinary);
			if( settings.run ) cleanup_files ~= exe_file_path;
			settings.compiler.invokeLinker(lbuildsettings, settings.platform, [tempobj.toNativeString()]);
		}

		// run post-build commands
		if( buildsettings.postBuildCommands.length ){
			logInfo("Running post-build commands...");
			runBuildCommands(buildsettings.postBuildCommands, buildsettings);
		}

		// copy files and run the executable
		if (generate_binary && settings.run) {
			if (buildsettings.targetType == TargetType.executable) {
				logInfo("Running %s...", exe_file_path.toNativeString());
				auto prg_pid = spawnProcess(exe_file_path.toNativeString() ~ settings.runArgs);
				auto result = prg_pid.wait();
				enforce(result == 0, "Program exited with code "~to!string(result));
			} else logInfo("Target is a library. Skipping execution.");
		}
	}
}
