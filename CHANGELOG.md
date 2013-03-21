Changelog
=========

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
