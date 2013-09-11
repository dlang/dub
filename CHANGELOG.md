Changelog
=========

v0.9.18 - 2013-09-11
--------------------

### Features and improvements ###

 - Added support for a "buildOptions" field to be able to specify compiler options in an abstract way
 - Implemented a new configuration resolution algorithm that is able to handle complex dependency graphs
 - Added support for a "debugVersions" field ("-debug=xyz")
 - Added support for a "-debug=xyz" command line option to specify additional debug version specifiers
 - The VisualD project generator doesn't specify redundant compiler flags for features that have dedicated checkboxes anymore
 - Improved folder structure in generated "visuald-combined" projects (by p0nce) - [pull #110][issue110]

### Bug fixes ###

 - Fixed handling of packages with no configurations (a global `null` configuration is now assumed in this case)
 - Fixed building of shared libraries (was missing the "-shared" flag)
 - Fixed upgrading in conjunction with sub packages (was causing an infinite loop) - [issue #100][issue100]
 - Fixed build of complex generated VisualD projects by avoiding redundant link dependencies
 - Fixed upgrading of branch based dependencies
 - Fixed inheriting of global build settings in configurations - [issue #113][issue113]
 - Fixed inclusion of entry point files (e.g. "source/app.d") in pure library packages - [issue #105][issue105]

[issue100]: https://github.com/rejectedsoftware/dub/issues/100
[issue105]: https://github.com/rejectedsoftware/dub/issues/105
[issue110]: https://github.com/rejectedsoftware/dub/issues/110
[issue113]: https://github.com/rejectedsoftware/dub/issues/113


v0.9.17 - 2013-07-24
--------------------

### Features and improvements ###

 - Added support for custom build types using the "buildTypes" field - [issue #78][issue78]
 - Added support for multiple and custom package registry URLs on the command line and as a configuration field - [issue #22][issue22]
 - Added support for a "workingDirectory" field to control from which directory the generated executable is run - [issue #84][issue84]
 - Added a new generator "visuald-combined", which combines the whole dependency tree into a single project
 - Updated default package registry URL to http://code.dlang.org
 - The default "unittest" and "unittest-cov" build types now issue the "-debug" flag
 - Building packages without any "importPaths" entry now issue a warning message

### Bug fixes ###

 - PARTIAL Fixed building with LDC - [issue #86][issue86]
 - The version string in the HTTP "User-Agent" field is now formatted according to SemVer
 - Fixed bogus warnings about "dflags" that are confised with flags that are a prefix of those
 - Fixed the VisualD generator to use the build settings and dependencies of the selected build configuration
 - Fixed the VisualD generator to enable the proper command line flags for each build type
 - Generated VisualD projects don't clean up JSON files on clean/rebuild anymore
 - Fixed building of packages with sub-packages when the main package is registered to DUB - [issue #87][issue87]
 - Fixed adhering to the specified global target type for library packages that have no explicit build configurations - [issue #92][issue92]
 - Fixed building of static libraries which have external library dependencies ("libs") - [issue #91][issue91]
 - Fixed error message for references to unknown sub-packages
 - Fixed handling of packages that are referenced multiple times using an explicit path - [issue #98][issue98]

[issue22]: https://github.com/rejectedsoftware/dub/issues/22
[issue78]: https://github.com/rejectedsoftware/dub/issues/78
[issue84]: https://github.com/rejectedsoftware/dub/issues/84
[issue86]: https://github.com/rejectedsoftware/dub/issues/86
[issue87]: https://github.com/rejectedsoftware/dub/issues/87
[issue91]: https://github.com/rejectedsoftware/dub/issues/91
[issue92]: https://github.com/rejectedsoftware/dub/issues/92
[issue98]: https://github.com/rejectedsoftware/dub/issues/98


v0.9.16 - 2013-06-29
--------------------

### Bug fixes ###

 - Fixed fetching of all recursive dependencies in one go
 - Fixed handling of paths with spaces when using "dub build"
 - Fixed upwards inheritance of version identifiers in generated VisualD projects


v0.9.15 - 2013-06-19
--------------------

### Features and improvements ###

 - Added `"targetType": "none"` for packages which don't contain sources and don't generate a binary output
 - Added build settings to the "dub describe" output

### Bug fixes ###

 - Fixed fetching of "main:sub" style dependencies from the registry
 - Remove half-broken support for sub-packages defined in sub-directories (needs to be determined if this feature is worth the trade-offs)
 - Fixed bogus re-installations of packages referenced by a sub-package
 - Fixed handling of dependencies of header-only (or target type "none") dependencies in the VisualD generator
 - Fixed the reported version of sub-packages in the output of "dub describe"


v0.9.14 - 2013-06-18
--------------------

### Features and improvements ###

 - Implemented support for multiple packages per directory and accessing sub-packages as dependencies - [issue #67][issue67]
 - Dependencies can now be specified per-configuration in addition to globally
 - Version numbers are now handled according to [SemVer](http://semver.org/) ("~master" style branch specifiers are independent of this and work as before)
 - Library packages are now only built when running "dub" instead of trying to execute them - partially [pull #66][issue66] by Vadim Lopatin and [issue #53][issue53]
 - Add support for optional dependencies (picked up only if already installed) - [issue #5][issue5]
 - Compiles on DMD 2.063
 - The build script now directly calls the compiler instead of relying an rdmd and supports ldmd and gdmd in addition to dmd (automatically detected)
 - Outputs a warning for package names with upper-case letters and treats package names case insensitive
 - Added `"buildRequirements": ["noDefaultFlags"]` for testing manual sets of command line flags - [issue #68][issue68]
 - Errors and diagnostic messages are now written to `stderr` instead of `stdout`
 - Added "dub describe" to output a build description of the whole dependency tree for external tools given a configuration/compiler/platform combination
 - Removed the -property switch and deprecated `"buildRequirements": ["relaxProperties"]`
 - Added support for a `DUBPATH` environment variable and support for adding a directory with multiple packages using "dub add-local" to search for dependencies in local directories other than the predefined ones
 - Replaced --list-locals/--list-user/--list-system with a single --list-installed switch
 - The version of DUB is now inferred using "git describe" and output on the help screen and in the user agent string of HTTP requests
 - Added some minimal example projects for several use cases
 - Temporarily disabled automatic package upgrading (was only working for the now removed project locally installed packages)

### Bug fixes ###

 - Fixed recursive inferring of configurations
 - Fixed including debug information for separate compile/link builds
 - Fixed VisualD generator for x64 builds and avoid building header-only dependencies
 - Fixed handling of "-Wl" flags returned by pkg-config
 - Fixed LDC builds for projects with multiple modules of the same name (but in different packages) using the -oq switch
 - Fixed the linker workaround in the build script to work on non-Ubuntu systems - [issue #71][issue71]
 - Fixed handling of Windows UNC paths (by Lutger Blijdestijn) - [pull #75][issue75]
 - Fixed a possible infinite update loop - [issue #72][issue72]
 - Fixed handling of multiple compiler/linker arguments with the same content (e.g. "--framework A --framework B" on OS X)

[issue5]: https://github.com/rejectedsoftware/dub/issues/5
[issue53]: https://github.com/rejectedsoftware/dub/issues/53
[issue66]: https://github.com/rejectedsoftware/dub/issues/66
[issue67]: https://github.com/rejectedsoftware/dub/issues/67
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
