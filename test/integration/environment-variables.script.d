/+ dub.json: {
   "name": "environment_variables"
} +/
module environment_variables;
import std;

void main()
{
	auto currDir = environment.get("CURR_DIR", __FILE_FULL_PATH__.dirName());
	// preGenerateCommands  uses system.environments < settings.environments < deppkg.environments < root.environments < deppkg.preGenerateEnvironments < root.preGenerateEnvironments
	// preBuildCommands     uses system.environments < settings.environments < deppkg.environments < root.environments < deppkg.buildEnvironments < root.buildEnvironments < deppkg.preBuildEnvironments < root.preBuildEnvironments
	// Build tools          uses system.environments < settings.environments < deppkg.environments < root.environments < deppkg.buildEnvironments < root.buildEnvironments
	// postBuildCommands    uses system.environments < settings.environments < deppkg.environments < root.environments < deppkg.buildEnvironments < root.buildEnvironments < deppkg.postBuildEnvironments < root.postBuildEnvironments
	// postGenerateCommands uses system.environments < settings.environments < deppkg.environments < root.environments < deppkg.postGenerateEnvironments < root.postGenerateEnvironments
	// preRunCommands       uses system.environments < settings.environments < deppkg.environments < root.environments < deppkg.runEnvironments < root.runEnvironments < deppkg.preRunEnvironments < root.preRunEnvironments
	// User application     uses system.environments < settings.environments < deppkg.environments < root.environments < deppkg.runEnvironments < root.runEnvironments
	// postRunCommands      uses system.environments < settings.environments < deppkg.environments < root.environments < deppkg.runEnvironments < root.runEnvironments < deppkg.postRunEnvironments < root.postRunEnvironments

	// Test cases covers:
	// preGenerateCommands [in root]
	//      priority check: system.environments < settings.environments
	//      priority check: settings.environments < deppkg.environments
	//      priority check: deppkg.environments < root.environments
	//      priority check: root.environments < deppkg.preGenerateEnvironments
	//      priority check: deppkg.preGenerateEnvironments < root.preGenerateEnvironments
	// postGenerateCommands [in root]
	//      expantion check: deppkg.VAR4
	// preBuildCommands [in deppkg]
	//      root.environments < deppkg.buildEnvironments
	//      deppkg.buildEnvironments < root.buildEnvironments
	//      root.buildEnvironments < deppkg.postBuildEnvironments
	//      deppkg.preBuildEnvironments < root.preBuildEnvironments
	// postBuildCommands [in deppkg]
	//      expantion check: deppkg.VAR4
	// preRunCommands [in deppkg][in root]
	//      expantion check: deppkg.VAR4
	// Application run
	//      expantion check: root.VAR1
	//      expantion check: settings.VAR2
	//      expantion check: root.VAR3
	//      expantion check: deppkg.VAR4
	//      expantion check: system.VAR5
	//      expantion check: system.SYSENVVAREXPCHECK
	// postRunCommands [in deppkg][in root]
	//      expantion check: deppkg.VAR4
	auto res = execute([environment.get("DUB", "dub"), "run", "-f"], [
		"PRIORITYCHECK_SYS_SET": "system.PRIORITYCHECK_SYS_SET",
		"SYSENVVAREXPCHECK":     "system.SYSENVVAREXPCHECK",
		"VAR5":                  "system.VAR5"
	], Config.none, size_t.max, currDir.buildPath("environment-variables"));
	scope (failure)
		writeln("environment-variables test failed... Testing stdout is:\n-----\n", res.output);

	// preGenerateCommands [in root]
	assert(res.output.canFind("root.preGenerate: setting.PRIORITYCHECK_SYS_SET"),       "preGenerate environment variables priority check is failed.");
	assert(res.output.canFind("root.preGenerate: deppkg.PRIORITYCHECK_SET_DEP"),        "preGenerate environment variables priority check is failed.");
	assert(res.output.canFind("root.preGenerate: deppkg.PRIORITYCHECK_DEP_ROOT"),       "preGenerate environment variables priority check is failed.");
	assert(res.output.canFind("root.preGenerate: deppkg.PRIORITYCHECK_ROOT_DEPSPEC"),   "preGenerate environment variables priority check is failed.");
	assert(res.output.canFind("root.preGenerate: root.PRIORITYCHECK_DEPSPEC_ROOTSPEC"), "preGenerate environment variables priority check is failed.");

	// postGenerateCommands [in root]
	assert(res.output.canFind("root.postGenerate: deppkg.VAR4", "postGenerate environment variables expantion check is failed."));

	// preBuildCommands [in deppkg]
	assert(res.output.canFind("deppkg.preBuild: deppkg.PRIORITYCHECK_ROOT_DEPBLDSPEC"),      "preBuild environment variables priority check is failed.");
	assert(res.output.canFind("deppkg.preBuild: root.PRIORITYCHECK_DEPBLDSPEC_ROOTBLDSPEC"), "preBuild environment variables priority check is failed.");
	assert(res.output.canFind("deppkg.preBuild: deppkg.PRIORITYCHECK_ROOTBLDSPEC_DEPSPEC"),  "preBuild environment variables priority check is failed.");
	assert(res.output.canFind("deppkg.preBuild: root.PRIORITYCHECK_DEPSPEC_ROOTSPEC"),       "preBuild environment variables priority check is failed.");

	// postBuildCommands [in deppkg]
	assert(res.output.canFind("deppkg.postBuild: deppkg.VAR4"), "postBuild environment variables expantion check is failed.");

	// preRunCommands [in deppkg][in root]
	assert(!res.output.canFind("deppkg.preRun: deppkg.VAR4"),   "preRun that is defined dependent library does not call.");
	assert(res.output.canFind("root.preRun: deppkg.VAR4"),      "preRun environment variables expantion check is failed.");

	// Application run
	assert(res.output.canFind("app.run: root.VAR1"),                "run environment variables expantion check is failed.");
	assert(res.output.canFind("app.run: settings.VAR2"),            "run environment variables expantion check is failed.");
	assert(res.output.canFind("app.run: root.VAR3"),                "run environment variables expantion check is failed.");
	assert(res.output.canFind("app.run: deppkg.VAR4"),              "run environment variables expantion check is failed.");
	assert(res.output.canFind("app.run: system.VAR5"),              "run environment variables expantion check is failed.");
	assert(res.output.canFind("app.run: system.SYSENVVAREXPCHECK"), "run environment variables expantion check is failed.");

	// postRunCommands [in deppkg][in root]
	assert(!res.output.canFind("deppkg.postRun: deppkg.VAR4"),  "postRunCommands that is defined dependent library does not call.");
	assert(res.output.canFind("root.postRun: deppkg.VAR4"),     "postRun environment variables expantion check is failed.");
}
