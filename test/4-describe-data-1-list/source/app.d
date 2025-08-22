import std.stdio;
import std.process;
import std.path;

import common;
import describe_test_utils;

void main()
{
	environment.remove("DFLAGS");

	immutable cmd = [
		dub,
		"describe",
		"--filter-versions",
		"--data-list",
		"--data= target-type , target-path , target-name",
		"--data= working-directory ",
		"--data=main-source-file",
		"--data=dflags,lflags",
		"--data=libs, linker-files",
		"--data=source-files, copy-files",
		"--data=versions, debug-versions",
		"--data=import-paths",
		"--data=string-import-paths",
		"--data=import-files",
		"--data=string-import-files",
		"--data=pre-generate-commands",
		"--data=post-generate-commands",
		"--data=pre-build-commands",
		"--data=post-build-commands",
		"--data=requirements, options",
		"--data=default-config",
		"--data=configs",
		"--data=default-build",
		"--data=builds",
	];

	import std.file;
	immutable describeDir = buildNormalizedPath(getcwd(), "../extra/4-describe");
	auto pipes = pipeProcess(cmd, Redirect.all, null, Config.none,
							 describeDir.buildPath("project"));
	if (pipes.pid.wait() != 0)
		die("Printing project data failed");

	auto expected = [
		// --data=target-type
		"executable", "",
		// --data=target-path
		describeDir.myBuildPath("project", ""), "",
		// --data=target-name
		"describe-project", "",
		// --data=working-directory
		describeDir.myBuildPath("project", ""), "",
		// --data=main-source-file
		describeDir.myBuildPath("project", "src", "dummy.d"), "",
		// --data=dflags
		"--some-dflag",
		"--another-dflag",
		"",
		// --data=lflags
		"--some-lflag",
		"--another-lflag",
		"",
		// --data=libs
		"somelib",
		"anotherlib",
		"",
		// --data=linker-files
		describeDir.myBuildPath("dependency-3", "describe-dependency-3".libName),
		describeDir.myBuildPath("project", "some" ~ libSuffix),
		describeDir.myBuildPath("dependency-1", "dep" ~ libSuffix),
		"",
		// --data=source-files
		describeDir.myBuildPath("project", "src", "dummy.d"),
		describeDir.myBuildPath("dependency-1", "source", "dummy.d"),
		"",
		// --data=copy-files
		describeDir.myBuildPath("project", "data", "dummy.dat"),
		describeDir.myBuildPath("dependency-1", "data", "*"),
		"",
		// --data=versions
		"someVerIdent",
		"anotherVerIdent",
		"Have_describe_dependency_3",
		"",
		// --data=debug-versions
		"someDebugVerIdent",
		"anotherDebugVerIdent",
		"",
		// --data=import-paths
		describeDir.myBuildPath("project", "src", ""),
		describeDir.myBuildPath("dependency-1", "source", ""),
		describeDir.myBuildPath("dependency-2", "some-path", ""),
		describeDir.myBuildPath("dependency-3", "dep3-source", ""),
		"",
		// --data=string-import-paths
		describeDir.myBuildPath("project", "views", ""),
		describeDir.myBuildPath("dependency-2", "some-extra-string-import-path", ""),
		describeDir.myBuildPath("dependency-3", "dep3-string-import-path", ""),
		"",
		// --data=import-files
		describeDir.myBuildPath("dependency-2", "some-path", "dummy.d"),
		"",
		// --data=string-import-files
		describeDir.myBuildPath("project", "views", "dummy.d"),
		//describeDir.myBuildPath("dependency-2", "some-extra-string-import-path", "dummy.d"), // This is missing from result, is that a bug?
		"",
	];

	version(Posix)
	expected ~= [
		// --data=pre-generate-commands
		"./do-preGenerateCommands.sh",
		"../dependency-1/dependency-preGenerateCommands.sh",
		"",
		// --data=post-generate-commands
		"./do-postGenerateCommands.sh",
		"../dependency-1/dependency-postGenerateCommands.sh",
		"",
		// --data=pre-build-commands
		"./do-preBuildCommands.sh",
		"../dependency-1/dependency-preBuildCommands.sh",
		"",
		// --data=post-build-commands
		"./do-postBuildCommands.sh",
		"../dependency-1/dependency-postBuildCommands.sh",
		"",
	];
	else
	expected ~= [
		// --data=pre-generate-commands
		"",
		"",
		// --data=post-generate-commands
		"",
		"",
		// --data=pre-build-commands
		"",
		"",
		// --data=post-build-commands
		"",
		"",
	];

	expected ~= [
		// --data=requirements
		"allowWarnings",
		"disallowInlining",
		"requireContracts",
		"",
		// --data=options
		"debugMode",
		// releaseMode is not included, even though it's specified, because the requireContracts requirement,
		"debugInfo",
		"stackStomping",
		"warnings",
		"",
		// --data=default-config
		"my-project-config",
		"",
		// --data=configs
		"my-project-config",
		"",
		// --data=default-build
		"debug",
		"",
		// --data=builds
		"debug",
		"plain",
		"release",
		"release-debug",
		"release-nobounds",
		"unittest",
		"profile",
		"profile-gc",
		"docs",
		"ddox",
		"cov",
		"cov-ctfe",
		"unittest-cov",
		"unittest-cov-ctfe",
		"syntax",
	];

	import std.array;
	import std.algorithm;
	const got = pipes.stdout.byLineCopy.map!fixWindowsCR.array;
	if (equal(got, expected)) return;

	printDifference(got, expected);
	die("Dub describe output differs");
}
