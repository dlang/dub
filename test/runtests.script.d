/+ dub.sdl:
name "test-runtests"
+/
module test.runtests;

void main()
{
	import std.process, std.path, std.file, std.algorithm;
	auto targetDir = buildPath(environment.get("CURR_DIR", getcwd), "runtests");
	auto runtests(string[] args, string workDir)
	{
		return execute([environment.get("DUB", "dub"), "runtests"] ~ args, null, Config.none, size_t.max, workDir);
	}

	// runtests of default
	{
		auto result = runtests([], targetDir);
		assert(result.status == 0, result.output);
		assert(result.output.canFind("[SUCCESS] #0: test01 [runtest-testcase-01]"), result.output);
		assert(result.output.canFind("[SUCCESS] #1: test03 [runtest-testcase-03] - Test case 03 of runtests command."),
			result.output);
		assert(result.output.canFind("[SUCCESS] #2: test04 [runtest-testcase-04]"), result.output);
		assert(result.output.canFind("[SUCCESS] #3: test02.d"), result.output);
		assert(result.output.canFind("[SUCCESS] #4: test05.script.d [runtest-testcase-05]"), result.output);
		version (Windows)
		{
			// Batch files are only executed in a Windows environment.
			assert(result.output.canFind("Test 06 on windows batch file"), result.output);
			assert(result.output.canFind("[SUCCESS] #5: test06.bat"), result.output);
			assert(!result.output.canFind("test06.sh"), result.output);
		}
		version (Posix)
		{
			// shell scripts are only executed in a Posix environment.
			assert(result.output.canFind("Test 06 on posix shell script"), result.output);
			assert(result.output.canFind("[SUCCESS] #5: test06.sh"), result.output);
			assert(!result.output.canFind("test06.bat"), result.output);
		}
		assert(result.output.canFind("6/6 tests was succeeded."), result.output);
		assert(result.output.canFind("All tests are completed!"), result.output);
	}

	// Fail check and `--testdir` specified
	{
		auto result = runtests(["--testdir", "test2"], targetDir);
		version (Windows) assert(result.status == -1,  result.output);
		version (Posix)   assert(result.status == 255, result.output);
		assert(result.output.canFind("[FAILED] #0: test01 [fail-check-test]"));
		assert(result.output.canFind("[SUCCESS] #1: test02.d"));
		assert(result.output.canFind("1/2 tests was failed."), result.output);
		assert(result.output.canFind("1/2 tests was succeeded."), result.output);
		assert(result.output.canFind("Error Test failed."), result.output);
	}

	// Remove coverage data
	if (std.file.exists(targetDir.buildPath("test/test01/src-main.lst")))
		std.file.remove(targetDir.buildPath("test/test01/src-main.lst"));
	if (std.file.exists(targetDir.buildPath("test/test01/srcexe-app.lst")))
		std.file.remove(targetDir.buildPath("test/test01/srcexe-app.lst"));
	if (std.file.exists(targetDir.buildPath("test/srcexe-app.lst")))
		std.file.remove(targetDir.buildPath("test/srcexe-app.lst"));

	// Check `--coverage` of test case without building test targets
	{
		auto result = runtests(["--skip-build", "--coverage", "-t", "test01"], targetDir);
		scope (exit) if (std.file.exists(targetDir.buildPath("test/test01/src-main.lst")))
			std.file.remove(targetDir.buildPath("test/test01/src-main.lst"));
		assert(result.status == 0, result.output);
		assert(!result.output.canFind("Linking runtests"), result.output);
		assert(result.output.canFind("[SUCCESS] #0: test01 [runtest-testcase-01]"), result.output);
		assert(result.output.canFind("1/1 tests was succeeded."), result.output);
		assert(result.output.canFind("All tests are completed!"), result.output);
		assert(std.file.exists(targetDir.buildPath("test/test01/src-main.lst")));
		assert(std.file.readText(targetDir.buildPath("test/test01/src-main.lst")).canFind("main.d is 100% covered"));
		assert(!std.file.exists(targetDir.buildPath("test/test01/srcexe-app.lst")));
	}

	// `--force` build the test target with `--coverage` enabled and check the coverage of the test target
	{
		auto result = runtests(["--force", "--coverage", "-t", "test02.d"], targetDir);
		scope (exit) if (std.file.exists(targetDir.buildPath("test/srcexe-app.lst")))
			std.file.remove(targetDir.buildPath("test/srcexe-app.lst"));
		assert(result.status == 0, result.output);
		assert(result.output.canFind("Linking runtests"), result.output);
		assert(result.output.canFind("[SUCCESS] #0: test02"), result.output);
		assert(result.output.canFind("1/1 tests was succeeded."), result.output);
		assert(result.output.canFind("All tests are completed!"), result.output);
		assert(std.file.exists(targetDir.buildPath("test/srcexe-app.lst")));
		assert(std.file.readText(targetDir.buildPath("test/srcexe-app.lst")).canFind("app.d is 100% covered"));
	}

}
