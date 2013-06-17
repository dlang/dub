Changelog
=========

v0.9.14 - 2013-06-
--------------------

### Features and improvements ###

 - Library packages are now only built when running "dub" instead of trying to execute them - partially [pull #66][issue66] by Vadim Lopatin and [issue #53][issue53]
 - Add support for optional dependencies (picked up only if already installed) - [issue #5][issue5]
 - Compiles on DMD 2.063
 - The build script now directly calls the compiler instead of relying an rdmd and supports ldmd and gdmd in addition to dmd
 - Outputs a warning for package names with upper-case letters and treats package names case insensitive
 - Added `"buildRequirements": ["noDefaultFlags"]` for testing manual sets of command line flags - [issue #68][issue68]
 - Errors and diagnostic messages are now written to `stderr` instead of `stdout`
 - Added "dub describe" to output a build description of the whole dependency tree for external tools given a configuration/compiler/platform combination
 - Removed the -property switch and deprecated `"buildRequirements": ["relaxProperties"]`
 - Added support for a `DUBPATH` environment variable and support for adding a directory with multiple packages using "dub add-local" to search for dependencies in local directories other than the predefined ones
 - Replaced --list-locals/--list-user/--list-system with a single --list-installed switch
 - The version of DUB is now inferred using "git describe" and output on the help screen and in the user agent string for HTTP requests

### Bug fixes ###

 - Fixed recursive inferring of configurations
 - Fixed including debug information for separate compile/link builds
 - Fixed VisualD generator for x64 builds and avoid building header-only dependencies
 - Fixed handling of "-Wl" flags returned by pkg-config
 - Fixed LDC builds for projects with multiple modules of the same name (but in different packages) using the -oq switch
 - Fixed the linker workaround in the build script to work on non-Ubuntu systems - [issue #71][issue71]
 - Fixed handling of Windows UNC paths (by Lutger Blijdestijn) - [pull #75][issue75]
 - Fixed a possible infinite update loop - [issue #72][issue72]

[issue5]: https://github.com/rejectedsoftware/dub/issues/5
[issue53]: https://github.com/rejectedsoftware/dub/issues/53
[issue66]: https://github.com/rejectedsoftware/dub/issues/66
[issue68]: https://github.com/rejectedsoftware/dub/issues/68
[issue71]: https://github.com/rejectedsoftware/dub/issues/71
[issue72]: https://github.com/rejectedsoftware/dub/issues/72
[issue75]: https://github.com/rejectedsoftware/dub/issues/75


v0.9.13 - 2013-04-16
--------------------

### Features and improvements ###

 - Implemented `"buildRequirements"` to allow packages to specify certain build requirements (e.g. avoiding function inlining or warnings)
 - Experimental support to specify flags to pass to "ddox filter" for --build=ddox
 - Configurations inherit the global `"targetType"` by default now
 - Import paths in VisualD projects are now relative
 - Cleaner console output for -v (no thread/fiber ID is printed anymore)
 - Build settings for VisualD projects are tuned to avoid common linker/compiler bugs by default
 - Generated VisualD projects put intermediate files to ".dub/obj/&lt;projectname&gt;" now

### Bug fixes ###

 - Fixed upgrading of branch based dependencies - [issue #55][issue55]
 - Fixed wording and repetition of the reserved compiler flag warning message - [issue #54][issue54]
 - Fixed erroneous inclusion of .d files in the import libraries field of generated VisualD projects
 - Fixed passing "package.json" to the compiler in generated Mono-D projects - [issue #60][issue60]
 - Fixed the Mono-D and VisualD generators to properly copy `"copyFiles"` - [issue #58][issue58]
 - Fixed removing of temporary files in case of unexpected folder contents - [issue #41][issue41]
 - Fixed invocation of the linker on Windows in case of another "link.exe" being in PATH - [issue #57][issue57]
 - Fixed computation of build settings for VisualD projects (inheritance works only bottom to top now)

[issue41]: https://github.com/rejectedsoftware/dub/issues/41
[issue54]: https://github.com/rejectedsoftware/dub/issues/54
[issue55]: https://github.com/rejectedsoftware/dub/issues/55
[issue57]: https://github.com/rejectedsoftware/dub/issues/57
[issue58]: https://github.com/rejectedsoftware/dub/issues/58
[issue60]: https://github.com/rejectedsoftware/dub/issues/60


v0.9.12 - 2013-03-21
--------------------

### Features and improvements ###

 - Implemented separate compile/link building when using DMD
 - Optimized platform field matching (by Robert Klotzner) - [pull #47][issue47]
 - Added build types for coverage analysis - [issue #45][issue45]
 - Wrong use of `"dflags"` now triggers a warning with suggestion for an alternative approach - [issue #37][issue37]
 - The "dub" binary is now in "bin/" instead of the root directory

### Bug fixes ###

 - Fixed an assertion that triggered when appending an absolute path
 - Fixed `--build=ddox` when DDOX was not yet installed/built - [issue #42][issue42]
 - Fixed the build script to work on Ubuntu
 - Fixed building in a project directory that contains no "package.json" file
 - Fixed the error message for non-existent dependency versions - [issue #44][issue44]
 - Fixed matching of (only) D source files (by Robert Klotzner) - [pull #46][issue46]
 - Fixed `"targetName"` and `"targetPath"` fields - [issue #48][issue48]

[issue37]: https://github.com/rejectedsoftware/dub/issues/37
[issue42]: https://github.com/rejectedsoftware/dub/issues/42
[issue44]: https://github.com/rejectedsoftware/dub/issues/44
[issue45]: https://github.com/rejectedsoftware/dub/issues/45
[issue46]: https://github.com/rejectedsoftware/dub/issues/46
[issue47]: https://github.com/rejectedsoftware/dub/issues/47
[issue48]: https://github.com/rejectedsoftware/dub/issues/48


v0.9.11 - 2013-03-05
--------------------

### Features and improvements ###

 - Configurations are now "shallow", meaning that configurations of dependencies can be selected by a package, but stay invisible to users of the package itself - [issue #33]
 - Target type selection is now supported (executable, static lib, dynamic lib etc.) - [issue #26][issue26]
 - Target name and path can be configured now
 - Added a possibility to exclude certain files from the build
 - The package description files is now added to IDE projects - [issue #35][issue35]
 - Using a response file to handle large compiler command lines - [issue #19][issue19]

### Bug fixes ###

 - Fixed spurious loading of the package during `dub install` - [issue #25][issue25]

[issue19]: https://github.com/rejectedsoftware/dub/issues/19
[issue25]: https://github.com/rejectedsoftware/dub/issues/25
[issue26]: https://github.com/rejectedsoftware/dub/issues/26
[issue35]: https://github.com/rejectedsoftware/dub/issues/35


v0.9.10 - 2013-03-04
--------------------

### Features and improvements ###

 - Added direct support for generating HTML documentation using DDOC or DDOX
 - Added support for pre/post generate/build commands
 - `dub install` does not add a dependency anymore (reverted to old behavior)

### Bug fixes ###

 - `dub uninstall` actually works now
 - The Windows installer also installs the needed DLLs
 - Fixed Windows paths on non-Windows systems emitted by the Mono-D generator - [issue #32][issue32]

[issue32]: https://github.com/rejectedsoftware/dub/issues/32


v0.9.9 - 2013-02-28
-------------------

### Features and improvements ###

 - Adds a Windows installer (by Brad Anderson aka eco) - [pull #27][issue27]
 - Support for branches other than "~master"
 - The MonoD generator now generates a pretty source hierarchy for dependencies
 - The "sourcePath" field has been changed to "sourcePaths" to support multiple paths (by Nathan M. Swan aka carlor) - [pull #28][issue28]

### Bug fixes ###

 - "dub init" with no arguments uses the current directory name as the project name - [issue #16][issue16]
 - The tilde character is not used for path names anymore - [issue #23][issue23]

[issue16]: https://github.com/rejectedsoftware/dub/issues/16
[issue23]: https://github.com/rejectedsoftware/dub/issues/23
[issue27]: https://github.com/rejectedsoftware/dub/issues/27
[issue28]: https://github.com/rejectedsoftware/dub/issues/28
