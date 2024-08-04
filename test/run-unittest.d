#!/usr/bin/env dub
/+dub.sdl:
	name: run_unittest
	targetName: run-unittest
	dependency "common" path="./common"
+/
module run_unittest;

import common;

int main(string[] args)
{
	import std.algorithm, std.file, std.format, std.stdio, std.path, std.process, std.string;
	alias ProcessConfig = std.process.Config;

	//** if [ -z ${DUB:-} ]; then
	//**     die $LINENO 'Variable $DUB must be defined to run the tests.'
	//** fi
	auto dub = environment.get("DUB", "");
	if (dub == "")
	{
		logError(`Environment variable "DUB" must be defined to run the tests.`);
		return 1;
	}

	//** if [ -z ${DC:-} ]; then
	//**     log '$DC not defined, assuming dmd...'
	//**     DC=dmd
	//** fi
	auto dc = environment.get("DC", "");
	if (dc == "")
	{
		log(`Environment variable "DC" not defined, assuming dmd...`);
		dc = "dmd";
	}

	// Clear log file
	{
		File(logFile, "w");
	}

	//** DC_BIN=$(basename "$DC")
	//** CURR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
	//** FRONTEND="${FRONTEND:-}"
	const dc_bin = baseName(dc).stripExtension;
	const curr_dir = __FILE_FULL_PATH__.dirName();
	const frontend = environment.get("FRONTEND", __VERSION__.format!"%04d");

	//** if [ "$#" -gt 0 ]; then FILTER=$1; else FILTER=".*"; fi
	auto filter = (args.length > 1) ? args[1] : "*";
	version (linux)   auto os = "linux";
	version (Windows) auto os = "windows";
	version (OSX)     auto os = "osx";

	version (Posix)
	{
		//** for script in $(ls $CURR_DIR/*.sh); do
		//**     if [[ ! "$script" =~ $FILTER ]]; then continue; fi
		//**     if [ "$script" = "$(gnureadlink ${BASH_SOURCE[0]})" ] || [ "$(basename $script)" = "common.sh" ]; then continue; fi
		//**     if [ -e $script.min_frontend ] && [ ! -z "$FRONTEND" ] && [ ${FRONTEND} \< $(cat $script.min_frontend) ]; then continue; fi
		//**     log "Running $script..."
		//**     DUB=$DUB DC=$DC CURR_DIR="$CURR_DIR" $script || logError "Script failure."
		//** done
		foreach(DirEntry script; dirEntries(curr_dir, "*.sh", SpanMode.shallow))
		{
			if (!script.name.baseName.globMatch(filter)) continue;
			if (!script.name.endsWith(".sh"))
				continue;
			if (baseName(script.name).among("run-unittest.sh", "common.sh")) continue;
			const min_frontend = script.name ~ ".min_frontend";
			if (exists(min_frontend) && frontend.length && cmp(frontend, min_frontend.readText) < 0) continue;
			log("Running " ~ script ~ "...");
			if (spawnShell(script.name, ["DUB":dub, "DC":dc, "CURR_DIR":curr_dir]).wait)
				logError("Script failure.");
			else
				log(script.name.baseName, " status: Ok");
		}
	}

	foreach (DirEntry script; dirEntries(curr_dir, "*.script.d", SpanMode.shallow))
	{
		if (!script.name.baseName.globMatch(filter)) continue;
		if (!script.name.endsWith(".d"))
			continue;
		const min_frontend = script.name ~ ".min_frontend";
		if (frontend.length && exists(min_frontend) && cmp(frontend, min_frontend.readText) < 0) continue;
		log("Running " ~ script ~ "...");
		if (spawnProcess([dub, script.name], ["DUB":dub, "DC":dc, "CURR_DIR":curr_dir]).wait)
			logError("Script failure.");
		else
			log(script.name, " status: Ok");
	}

	//for pack in $(ls -d $CURR_DIR/*/); do
	foreach (DirEntry pack; dirEntries(curr_dir, SpanMode.shallow))
	{
		//if [[ ! "$pack" =~ $FILTER ]]; then continue; fi
		if (!pack.name.baseName.globMatch(filter)) continue;
		if (!pack.isDir || pack.name.baseName.startsWith(".")) continue;
		if (!pack.name.buildPath("dub.json").exists && !pack.name.buildPath("dub.sdl").exists && !pack.name.buildPath("package.json").exists) continue;
		//if [ -e $pack/.min_frontend ] && [ ! -z "$FRONTEND" -a "$FRONTEND" \< $(cat $pack/.min_frontend) ]; then continue; fi
		if (pack.name.buildPath(".min_frontend").exists && cmp(frontend, pack.name.buildPath(".min_frontend").readText) < 0) continue;

		//#First we build the packages
		//if [ ! -e $pack/.no_build ] && [ ! -e $pack/.no_build_$DC_BIN ]; then # For sourceLibrary
		bool build = (!pack.name.buildPath(".no_build").exists
			&& !pack.name.buildPath(".no_build_" ~ dc_bin).exists
			&& !pack.name.buildPath(".no_build_" ~ os).exists);
		if (build)
		{
			//build=1
			//if [ -e $pack/.fail_build ]; then
			//    log "Building $pack, expected failure..."
			//    $DUB build --force --root=$pack --compiler=$DC 2>/dev/null && logError "Error: Failure expected, but build passed."
			//else
			//    log "Building $pack..."
			//    $DUB build --force --root=$pack --compiler=$DC || logError "Build failure."
			//fi
			//if [ -e $pack/.fail_build ]; then
			if (pack.name.buildPath(".fail_build").exists)
			{
				log("Building " ~ pack.name.baseName ~ ", expected failure...");
				if (spawnProcess([dub, "build", "--force", "--compiler", dc], ["DUB":dub, "DC":dc, "CURR_DIR":curr_dir], ProcessConfig.none, pack.name).wait)
					log(pack.name.baseName, " status: Ok");
				else
					logError("Failure expected, but build passed.");
			}
			else
			{
				log("Building ", pack.name.baseName, "...");
				if (spawnProcess([dub, "build", "--force", "--compiler", dc], ["DUB":dub, "DC":dc, "CURR_DIR":curr_dir], ProcessConfig.none, pack.name).wait)
					logError("Script failure.");
				else
					log(pack.name.baseName, " status: Ok");
			}
		}
		//else
		//    build=0
		//fi

		//# We run the ones that are supposed to be run
		//if [ $build -eq 1 ] && [ ! -e $pack/.no_run ] && [ ! -e $pack/.no_run_$DC_BIN ]; then
		//    log "Running $pack..."
		//    $DUB run --force --root=$pack --compiler=$DC || logError "Run failure."
		//fi
		if (build
			&& !pack.name.buildPath(".no_run").exists
			&& !pack.name.buildPath(".no_run_" ~ dc_bin).exists
			&& !pack.name.buildPath(".no_run_" ~ os).exists)
		{
			log("Running ", pack.name.baseName, "...");
			if (spawnProcess([dub, "run", "--force", "--compiler", dc], ["DUB":dub, "DC":dc, "CURR_DIR":curr_dir], ProcessConfig.none, pack.name).wait)
				logError("Run failure.");
			else
				log(pack.name.baseName, " status: Ok");
		}

		//# Finally, the unittest part
		//if [ $build -eq 1 ] && [ ! -e $pack/.no_test ] && [ ! -e $pack/.no_test_$DC_BIN ]; then
		//    log "Testing $pack..."
		//    $DUB test --force --root=$pack --compiler=$DC || logError "Test failure."
		//fi
		if (build
			&& !pack.name.buildPath(".no_test").exists
			&& !pack.name.buildPath(".no_test_" ~ dc_bin).exists
			&& !pack.name.buildPath(".no_test_" ~ os).exists)
		{
			log("Testing ", pack.name.baseName, "...");
			if (spawnProcess([dub, "test", "--force", "--root", pack.name, "--compiler", dc], ["DUB":dub, "DC":dc, "CURR_DIR":curr_dir]).wait)
				logError("Test failure.");
			else
				log(pack.name.baseName, " status: Ok");
		}
	//done
	}

	//echo
	//echo 'Testing summary:'
	//cat $(dirname "${BASH_SOURCE[0]}")/test.log
	writeln();
	writeln("Testing summary:");
	auto logLines = readText("test.log").splitLines;
	foreach (line; logLines)
		writeln(line);
	auto errCnt = logLines.count!(a => a.startsWith("[ERROR]"));
	auto passCnt = logLines.count!(a => a.startsWith("[INFO]") && a.endsWith("status: Ok"));
	writeln(passCnt , "/", errCnt + passCnt, " tests were successed.");

	return any_errors;
}
