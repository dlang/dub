import std.algorithm;
import std.array;
import std.file;
import std.path;
import std.process;
import std.range;
import std.stdio;

import common;
import describe_test_utils;

void main()
{
	if (!environment["DC"].baseName.canFind("dmd")) skip("need dmd like compiler");

	environment.remove("DFLAGS");
	immutable cmd = [
		dub,
		"describe",
		"--filter-versions",
		"--data=main-source-file",
		"--data=dflags,lflags",
		"--data=libs,linker-files",
		"--data=source-files",
		"--data=versions",
		"--data=debug-versions",
		"--data=import-paths",
		"--data=string-import-paths",
		"--data=import-files",
		"--data=options",
	];

	immutable describeDir = buildNormalizedPath(getcwd(), "../extra/4-describe");
	auto pipes = pipeProcess(cmd, Redirect.all, null, Config.none,
							 describeDir.buildPath("project"));
	if (pipes.pid.wait() != 0)
		die("Printing project data failed");

	auto expectedArray = [
		// --data=main-source-file
		describeDir.myBuildPath("project", "src", "dummy.d").escape,
		// --data=dflags
		"--some-dflag",
		"--another-dflag",
		// --data=lflags
		"-L--some-lflag",
		"-L--another-lflag",
	];

	version(Posix)
	expectedArray ~= [
		// --data=libs
		"-L-lsomelib",
		"-L-lanotherlib",
	];
	else
	expectedArray ~= [
		// --data=libs
		"-Lsomelib.lib",
		"-Lanotherlib.lib",
	];

	expectedArray ~= [
		// --data=linker-files
		describeDir.myBuildPath("dependency-3", "describe-dependency-3".libName).escape,
		describeDir.myBuildPath("project", "some" ~ libSuffix).escape,
		describeDir.myBuildPath("dependency-1", "dep" ~ libSuffix).escape,
		// --data=source-files
		describeDir.myBuildPath("project", "src", "dummy.d").escape,
		describeDir.myBuildPath("dependency-1", "source", "dummy.d").escape,
		// --data=versions
		"-version=someVerIdent",
		"-version=anotherVerIdent",
		"-version=Have_describe_dependency_3",
		// --data=debug-versions
		"-debug=someDebugVerIdent",
		"-debug=anotherDebugVerIdent",
		// --data=import-paths
		escape("-I" ~ describeDir.myBuildPath("project", "src", "")),
		escape("-I" ~ describeDir.myBuildPath("dependency-1", "source", "")),
		escape("-I" ~ describeDir.myBuildPath("dependency-2", "some-path", "")),
		escape("-I" ~ describeDir.myBuildPath("dependency-3", "dep3-source", "")),
		// --data=string-import-paths
		escape("-J" ~ describeDir.myBuildPath("project", "views", "")),
		escape("-J" ~ describeDir.myBuildPath("dependency-2", "some-extra-string-import-path", "")),
		escape("-J" ~ describeDir.myBuildPath("dependency-3", "dep3-string-import-path", "")),
		// --data=import-files
		escape(describeDir.myBuildPath("dependency-2", "some-path", "dummy.d")),
		// --data=options
		"-debug",
		// releaseMode is not included, even though it's specified, because the requireContracts requirement drops it
		"-g",
		"-gx",
		"-wi",
	];
	immutable expected = expectedArray.join(" ");

	const got = pipes.stdout.byLineCopy.map!fixWindowsCR.array;

	if (equal(got, [ expected ])) return;

	copy(got, File("dub-output.txt", "w").lockingTextWriter);
	std.file.write("expected-output.txt", expected);

	die("Dub output didn't match. Check dub-output.txt and expected-output.txt for details");
}
