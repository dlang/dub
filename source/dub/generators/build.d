/**
	Generator for direct compiler builds.
	
	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.generators.build;

import dub.compilers.compiler;
import dub.generators.generator;
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
import stdx.process;

import vibecompat.core.file;
import vibecompat.core.log;
import vibecompat.inet.path;


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
		buildsettings.addDFlags(["-w"/*, "-property"*/]);
		string dflags = environment.get("DFLAGS");
		if( dflags.length ){
			settings.buildType = "$DFLAGS";
			buildsettings.addDFlags(dflags.split());
		} else {
			addBuildTypeFlags(buildsettings, settings.buildType);
		}

		auto generate_binary = !buildsettings.dflags.canFind("-o-");

		// make paths relative to shrink the command line
		foreach(ref f; buildsettings.sourceFiles){
			auto fp = Path(f);
			if( fp.absolute ) fp = fp.relativeTo(Path(getcwd));
			f = fp.toNativeString();
		}

		// setup for command line
		settings.compiler.prepareBuildSettings(buildsettings, BuildSetting.commandLine);

		// find the temp directory
		auto tmp = environment.get("TEMP");
		if( !tmp.length ) tmp = environment.get("TMP");
		if( !tmp.length ){
			version(Posix) tmp = "/tmp";
			else tmp = ".";
		}

		Path exe_file_path;
		if( generate_binary ){
			if( settings.run ){
				import std.random;
				auto rnd = to!string(uniform(uint.min, uint.max));
				buildsettings.targetPath = (Path(tmp)~"dub/"~rnd).toNativeString();
			}
			exe_file_path = Path(buildsettings.targetPath) ~ getTargetFileName(buildsettings, settings.platform);
			settings.compiler.setTarget(buildsettings, settings.platform);
		}
		logDebug("Application output name is '%s'", exe_file_path.toNativeString());

		string[] flags = buildsettings.dflags;

		if( settings.config.length ) logInfo("Building configuration "~settings.config~", build type "~settings.buildType);
		else logInfo("Building default configuration, build type "~settings.buildType);

		if( buildsettings.preGenerateCommands.length ){
			logInfo("Running pre-generate commands...");
			runCommands(buildsettings.preGenerateCommands);
		}

		if( buildsettings.postGenerateCommands.length ){
			logInfo("Running post-generate commands...");
			runCommands(buildsettings.postGenerateCommands);
		}

		if( buildsettings.preBuildCommands.length ){
			logInfo("Running pre-build commands...");
			runCommands(buildsettings.preBuildCommands);
		}

		// assure that we clean up after ourselves
		Path[] cleanup_files;
		scope(exit){
			foreach(f; cleanup_files)
				if( existsFile(f) )
					remove(f.toNativeString());
			rmdir(buildsettings.targetPath);
		}
		mkdirRecurse(buildsettings.targetPath);

		// write response file instead of passing flags directly to the compiler
		auto res_file = Path(buildsettings.targetPath) ~ ".dmd-response-file.txt";
		cleanup_files ~= res_file;
		std.file.write(res_file.toNativeString(), join(flags, "\n"));

		// invoke the compiler
		logInfo("Running %s...", settings.compilerBinary);
		logDebug("%s %s", settings.compilerBinary, join(flags, " "));
		if( settings.run ) cleanup_files ~= exe_file_path;
		auto compiler_pid = spawnProcess([settings.compilerBinary, "@"~res_file.toNativeString()]);
		auto result = compiler_pid.wait();
		enforce(result == 0, "Build command failed with exit code "~to!string(result));

		// run post-build commands
		if( buildsettings.postBuildCommands.length ){
			logInfo("Running post-build commands...");
			runCommands(buildsettings.postBuildCommands);
		}

		// copy files and run the executable
		if( generate_binary ){
			// TODO: move to a common place - this is not generator specific
			if( buildsettings.copyFiles.length ){
				logInfo("Copying files...");
				foreach( f; buildsettings.copyFiles ){
					auto src = Path(f);
					auto dst = exe_file_path.parentPath ~ Path(f).head;
					logDebug("  %s to %s", src.toNativeString(), dst.toNativeString());
					try {
						cleanup_files ~= dst;
						copyFile(src, dst, true);
					} catch logWarn("Failed to copy to %s", dst.toNativeString());
				}
			}

			if( settings.run ){
				logDebug("Running %s...", exe_file_path.toNativeString());
				auto prg_pid = spawnProcess(exe_file_path.toNativeString() ~ settings.runArgs);
				result = prg_pid.wait();
				enforce(result == 0, "Program exited with code "~to!string(result));
			}
		}
	}
}
