/+ dub.sdl:
	name "issue426-visuald-build-events"
+/

module issue426_visuald_build_events;

void main()
{
	version (Windows) {
		import std.exception : enforce;
		import std.file : mkdir, readText, remove, rmdirRecurse, write;
		import std.path : buildPath, dirName;
		import std.process : Config, environment, execute;
		import std.uuid : randomUUID;

		auto dub = environment.get("DUB", buildPath(__FILE_FULL_PATH__.dirName.dirName, "bin", "dub.exe"));
		auto compiler = "--compiler=" ~ environment.get("DC", "dmd");
		auto dir = buildPath(__FILE_FULL_PATH__.dirName, "dub issue426 " ~ randomUUID().toString());
		mkdir(dir);
		scope (exit) rmdirRecurse(dir);

		mkdir(buildPath(dir, "source"));
		write(buildPath(dir, "source", "app.d"), "void main() {}");
		write(buildPath(dir, "R&D.txt"), "input\r\n");
		write(buildPath(dir, "record.cmd"), "@echo %DUB_PACKAGE% %PHASE%>>result.txt\r\n");
		write(buildPath(dir, "dub.json"), `{
			"name": "events",
			"targetType": "executable",
			"buildEnvironments": {"PHASE": "build"},
			"preBuildEnvironments": {"PHASE": "before"},
			"postBuildEnvironments": {"PHASE": "after"},
			"preBuildCommands": ["type \"R&D.txt\" > result.txt", "record.cmd"],
			"postBuildCommands": ["record.cmd"]
		}`);

		void run(string[] args, string cwd) {
			auto result = execute(args, null, Config.none, size_t.max, cwd);
			enforce(result.status == 0, result.output);
		}

		auto output = buildPath(dir, "result.txt");
		run([dub, "build", compiler], dir);
		auto expected = readText(output);
		enforce(expected == "input\r\nevents before\r\nevents after\r\n", expected);
		remove(output);

		run([dub, "generate", "visuald", compiler], dir);
		run(["powershell.exe", "-NoProfile", "-Command", `
			$config = ([xml](Get-Content -Raw events.visualdproj)).DProject.Config
			foreach ($event in $config.preBuildCommand, $config.postBuildCommand) {
				[IO.File]::WriteAllLines((Join-Path $pwd 'event.cmd'), $event.Split([char]10))
				cmd.exe /d /c event.cmd
				if ($LASTEXITCODE) { exit $LASTEXITCODE }
			}`], buildPath(dir, ".dub"));
		enforce(readText(output) == expected, "Visual D build events differed from dub build");
	}
}
