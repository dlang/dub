#
# Completions for the dub command
#

#
# Subcommands
#

# Package creation
complete -c dub -n '__fish_use_subcommand' -x -a init            -d 'Initializes an empty package skeleton'
# Build, test, and run
complete -c dub -n '__fish_use_subcommand' -x -a run             -d 'Builds and runs a package'
complete -c dub -n '__fish_use_subcommand' -x -a build           -d 'Builds a package'
complete -c dub -n '__fish_use_subcommand' -x -a test            -d 'Executes the tests of the selected package'
complete -c dub -n '__fish_use_subcommand' -x -a generate        -d 'Generates project files using the specified generator'
complete -c dub -n '__fish_use_subcommand' -x -a describe        -d 'Prints a JSON description of the project and its dependencies'
complete -c dub -n '__fish_use_subcommand' -x -a clean           -d 'Removes intermediate build files and cached build results'
complete -c dub -n '__fish_use_subcommand' -x -a dustmite        -d 'Create reduced test cases for build errors'
# Package management
complete -c dub -n '__fish_use_subcommand' -x -a fetch           -d 'Manually retrieves and caches a package'
complete -c dub -n '__fish_use_subcommand' -x -a remove          -d 'Removes a cached package'
complete -c dub -n '__fish_use_subcommand' -x -a upgrade         -d 'Forces an upgrade of all dependencies'
complete -c dub -n '__fish_use_subcommand' -x -a add-path        -d 'Adds a default package search path'
complete -c dub -n '__fish_use_subcommand' -x -a remove-path     -d 'Removes a package search path'
complete -c dub -n '__fish_use_subcommand' -x -a add-local       -d 'Adds a local package directory'
complete -c dub -n '__fish_use_subcommand' -x -a remove-local    -d 'Removes a local package directory'
complete -c dub -n '__fish_use_subcommand' -x -a list            -d 'Prints a list of all local packages dub is aware of'
complete -c dub -n '__fish_use_subcommand' -x -a add-override    -d 'Adds a new package override'
complete -c dub -n '__fish_use_subcommand' -x -a remove-override -d 'Removes an existing package override'
complete -c dub -n '__fish_use_subcommand' -x -a list-overrides  -d 'Prints a list of all local package overrides'
complete -c dub -n '__fish_use_subcommand' -x -a clean-caches    -d 'Removes cached metadata'

#
# Subcommand options
#
for cmd in run build
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l rdmd                  -d "Use rdmd"
end
for cmd in run build test
	complete -c dub -n "contains '$cmd' (commandline -poc)" -s f -l force                 -d "Force recompilation"
end

for cmd in run
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l temp-build            -d "Build in temp folder"
end

for cmd in run build test generate describe dustmite
	complete -c dub -n "contains '$cmd' (commandline -poc)" -s c -l config             -r -d "Build configuration"
	complete -c dub -n "contains '$cmd' (commandline -poc)" -s a -l arch               -r -d "Force architecture"
	complete -c dub -n "contains '$cmd' (commandline -poc)" -s d -l debug              -r -d "Debug identifier"
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l nodeps                -d "No dependency check"
	complete -c dub -n "contains '$cmd' (commandline -poc)" -s b -l build           -u -x -d "Build type"                        -a "debug plain release release-debug release-nobounds unittest profile profile-gc docs ddox cov unittest-cov"
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l build-mode         -x -d "How compiler & linker are invoked" -a "separate allAtOnce singleFile"
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l compiler           -x -d "Compiler binary"                   -a "dmd gdc ldc gdmd ldmd"
end

for cmd in run build test generate describe dustmite fetch remove upgrade
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l force-remove       -x -d "Force deletion"
end

for cmd in run build dustmite
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l combined              -d "Build project in single compiler run"
end

for cmd in run build test generate
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l print-builds          -d "Print list of build types"
end

for cmd in run build generate
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l print-configs         -d "Print list of configurations"
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l print-platform        -d "Print build platform identifiers"
end

for cmd in build dustmite fetch remove
	complete -c dub -n "contains '$cmd' (commandline -poc)"                            -x -d "Package"                           -a '(dub list | awk \'/^[[:space:]]+/ { print $1 }\' | cut -f 3 -d " ")'
end

for cmd in clean
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l all-packages          -d "Clean all known packages"
end

for cmd in dustmite
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l compiler-status    -x -d "Expected compiler status code"
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l compiler-regex     -x -d "Compiler output regular expression"
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l linker-status      -x -d "Expected linker status code"
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l linker-regex       -x -d "Linker output regular expression"
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l program-status     -x -d "Expected program status code"
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l program-regex      -x -d "Program output regular expression"
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l test-package       -x -d "Perform a test run"
end

for cmd in fetch remove
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l version            -r -d "Version to use"
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l system                -d "Deprecated"
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l local                 -d "Deprecated"
end

for cmd in upgrade
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l prerelease            -d "Use latest pre-release version"
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l verify                -d "Update if successful build"
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l missing-only          -d "Update dependencies without a selected version"
end

for cmd in add-path remove-path add-local remove-local add-override remove-override
	complete -c dub -n "contains '$cmd' (commandline -poc)"      -l system                -d "System-wide"
end



# Common options
complete -c dub -s h -l help        -d "Display help"
complete -c dub      -l root     -r -d "Path to operate in"
complete -c dub      -l registry -r -d "Use DUB registry URL"
complete -c dub      -l annotate    -d "Just print actions"
complete -c dub -s v -l verbose     -d "Print diagnostic output"
complete -c dub      -l vverbose    -d "Print debug output"
complete -c dub -s q -l quiet       -d "Only print warnings and errors"
complete -c dub      -l vquiet      -d "Print no messages"
complete -c dub      -l cache    -x -d "Use cache location" -a "local system user"
