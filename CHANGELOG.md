Changelog
=========

v1.1.2 - 2017-01-
-------------------

### Bug fixes ###

 - Fixes configuration resolution in diamond dependency settings - [issue #1005][issue1005], [pull #1006][issue1006]
 - Fixed compilation of the 
 - Contains various diagnostic and error message improvements - [issue #957][issue957], [pull #1010][issue1010], [pull #1012][issue1012], [issue #1019][issue1019]

[issue957]: https://github.com/dlang/dub/issues/957
[issue1005]: https://github.com/dlang/dub/issues/1005
[issue1006]: https://github.com/dlang/dub/issues/1006
[issue1010]: https://github.com/dlang/dub/issues/1010
[issue1012]: https://github.com/dlang/dub/issues/1012
[issue1019]: https://github.com/dlang/dub/issues/1019


 v1.1.1 - 2016-11-30
-------------------

### Bug fixes ###

 - Fixed a regression where path based dependencies were not properly resolved - [issue #934][issue934], [issue #959][issue959], [pull #962][issue962], [pull #969][issue969]
 - Fixed DMD separate compile/link detection code for the case where the compiler binary is not called "dmd" - [pull #966][issur966]
 - Fixed using the selected compiler for generated Sublime Text projects - [issue #931][issue931], [pull #983][issue983]
 - Fixed upgrading of optional dependencies (were ignored during the upgrade previously) - [issue #672][issue672], [pull #989][issue989]
 - Fixed automatic downloading of selected optional dependencies - [issue #990][issue990], [pull #991][issue991]

[issue672]: https://github.com/dlang/dub/issues/672
[issue931]: https://github.com/dlang/dub/issues/931
[issue934]: https://github.com/dlang/dub/issues/934
[issue959]: https://github.com/dlang/dub/issues/959
[issue962]: https://github.com/dlang/dub/issues/962
[issue966]: https://github.com/dlang/dub/issues/966
[issue969]: https://github.com/dlang/dub/issues/969
[issue983]: https://github.com/dlang/dub/issues/983
[issue989]: https://github.com/dlang/dub/issues/989
[issue990]: https://github.com/dlang/dub/issues/990
[issue991]: https://github.com/dlang/dub/issues/991


v1.1.0 - 2016-10-31
-------------------

### Features and improvements ###

 - Fixed compilation for DMD 2.072.0 (minimum supported frontend version is 2.065) - [pull #891][issue891]
 - Fixed compilation with the latest vibe.d 0.7.30 alpha versions (avoid `Bson.opDispatch`)
 - Single-file packages are now built locally unless the shebang syntax is used (still performs a build in the temporary folder in that case) - [issue #887][issue887], [pull #888][issue888]
 - DUB now searches for a configuration file in "../etc/dub/settings.json" (relative to the executable location), enabling distribution-specific configuration - [issue #895][issue895], [pull #897][issue897]
 - "dub remove" is now interactive in case of multiple matching package versions - [pull #879][issue879]
 - Added a "--stdout" switch to "dub convert" - [issue #932][issue932], [pull #933][issue933]

### Bug fixes ###

 - Pressing Ctrl+C during "dub init" now doesn't leave a half-initialized package behind - [issue #883][issue883], [pull #884][issue884]
 - Fixed handling of empty array directives in the SDLang recipe parser (e.g. a single `sourcePaths` directive with no arguments now properly avoids searching for default source directories)
 - Fixed a bad error message for missing dependencies that are referenced in the root package, as well as from a dependency - [issue #896][issue896]
 - Fixed naming of folders in generated Sublime Text projects (by p0nce) - [pull #918][issue918]
 - Fixed the workaround for "dub test" and modern vibe.d projects (proper fix is planned after a grace period)
 - Fixed linking against intermediate dependencies in their build folder instead of the final build output file - [issue #921][issue921], [pull #922][issue922]
 - Fixed omission of packages in a moderately complex sub package scenario - [issue #923][issue923], [pull #924][issue924]
 - Fixed the default lib command line flag passed to LDC when building shared libraries (by Олег Леленков aka goodbin) - [pull #930][issue930]
 - Fixed extraneous fields getting added to the package recipe by "dub convert" - [issue #820][issue820], [pull #901][issue901]

[issue820]: https://github.com/dlang/dub/issues/820
[issue879]: https://github.com/dlang/dub/issues/879
[issue883]: https://github.com/dlang/dub/issues/883
[issue884]: https://github.com/dlang/dub/issues/884
[issue887]: https://github.com/dlang/dub/issues/887
[issue888]: https://github.com/dlang/dub/issues/888
[issue891]: https://github.com/dlang/dub/issues/891
[issue895]: https://github.com/dlang/dub/issues/895
[issue896]: https://github.com/dlang/dub/issues/896
[issue897]: https://github.com/dlang/dub/issues/897
[issue901]: https://github.com/dlang/dub/issues/901
[issue918]: https://github.com/dlang/dub/issues/918
[issue921]: https://github.com/dlang/dub/issues/921
[issue922]: https://github.com/dlang/dub/issues/922
[issue923]: https://github.com/dlang/dub/issues/923
[issue924]: https://github.com/dlang/dub/issues/924
[issue930]: https://github.com/dlang/dub/issues/930
[issue932]: https://github.com/dlang/dub/issues/932
[issue933]: https://github.com/dlang/dub/issues/933


v1.0.0 - 2016-06-20
-------------------

### Features and improvements ###

 - Implemented support for single-file packages, including shebang script support - [issue #103][issue103], [pull #851][issue851], [pull #866][issue866], [pull #870][issue870], [pull #878][issue878]
 - Builds on DMD 2.065.0 up to 2.071.1
 - Removed all deprecated functionality from the API, CLI and data formats
 - The minimum supported OS X version is now 10.7
 - Switched from `std.stream` to `std.stdio` (beware that a recent version of DMD is now necessary when building DUB to support Unicode file names on Windows) - [pull #847][issue847]
 - Now passes `-vcolumns` also to LDC - [issue #859][issue859], [pull #860][issue860]

### Bug fixes ###
 - Avoids superfluous registry queries when building - [issue #831][issue831], [pull #861][issue861]
 - Fixed handling of "libs" on Windows/DMD when building in `allAtOnce` mode
 - Fixed building with LDC on Windows for both, the VisualStudio based version and the MinGW version - [issue #618][issue618], [pull #688][issue688]
 - Fixed escaping of command line arguments with spaces for LDC - [issue #834][issue834], [pull #860][issue860]

[issue103]: https://github.com/dlang/dub/issues/103
[issue618]: https://github.com/dlang/dub/issues/618
[issue688]: https://github.com/dlang/dub/issues/688
[issue831]: https://github.com/dlang/dub/issues/831
[issue834]: https://github.com/dlang/dub/issues/834
[issue847]: https://github.com/dlang/dub/issues/847
[issue851]: https://github.com/dlang/dub/issues/851
[issue859]: https://github.com/dlang/dub/issues/859
[issue860]: https://github.com/dlang/dub/issues/860
[issue861]: https://github.com/dlang/dub/issues/861
[issue866]: https://github.com/dlang/dub/issues/866
[issue870]: https://github.com/dlang/dub/issues/870
[issue878]: https://github.com/dlang/dub/issues/878


v0.9.25 - 2016-05-22
--------------------

### Features and improvements ###

 - Builds on DMD 2.064.2 up to 2.071.0
 - Cleaned up the API to be (almost) ready for the 1.0.0 release - [issue #349][issue349] - [pull #785][issue785]
 - Implemented new semantics for optional dependencies (now controlled using dub.selections.json) - [issue #361][issue361], [pull #733][issue733]
 - Made "dub init" interactive to improve/simplify the creation of new packages (can be disabled with the "-n" switch) - [pull #734][issue734]
 - Switched back the default "dub init" recipe format to JSON (both, JSON and SDLang will stay supported) - [issue #724][issue724]
 - Locally cached packages are now stored in a folder that matches their name, which enables more possible ways to organize the source code (mostly by Guillaume Piolat aka p0nce) - [issue #502][issue502], [pull #735][issue735]
 - Improved worst-case speed of the dependency resolver for some pathological cases
 - Sped up GIT based local package version detection using a cache on Windows - [pull #692][issue692]
 - Implemented "dub convert" to convert between JSON and SDLang package recipes - [pull #732][issue732]
 - Implemented a "dub search" command to search the package registry from the CLI - [pull #663][issue663]
 - "dub test" doesn't build dependencies in unittest mode anymore - [issue #640][issue640], [issue #823][issue823]
 - Added a "-ddoxTool"/"x:ddoxTool" field to override the package used for DDOX documentation builds - [pull #702][issue702]
 - DUB init now uses the users full name on Posix systems - [issue #715][issue715]
 - Added support for the "DFLAGS" environment variable to "dub test"
 - Added a "release-debug" default build type
 - Path based dependencies are now also stored in dub.selections.json - [issue #772][issue772]
 - Entries in dub.selections.json are now output in alphabetic order - [issue #709][issue709]
 - The Sublime Text generator now outputs import paths for use with DKit (by xentec) - [pull #757][issue757]
 - The VisualD generator now creates the project files in the ".dub" subdirectory (by Guillaume Piolat aka p0nce) - [pull #680][issue680]

### Bug fixes ###

 - Fixed outputting global build settings (e.g. architecture flags) only once - [issue #346][issue346], [issue #635][issue635], [issue #686][issue686], [pull #759][issue759]
 - Fixed an infinite recursive DUB invocation if dub was invoked in "preGenerateCommands" (by Nick Sabalausky) - [issue #616][issue616], [pull #633][issue633]
 - Fixed the VisualD generator to set the correct debug working directory
 - Fixed disabling bounds-checking on LDC to avoid the deprecated/removed `-noboundscheck` flag (by Guillaume Piolat aka p0nce) - [pull #693][issue693]
 - Fixed race conditions when running multiple DUB instances concurrently - [issue #674][issue674], [pull #683][issue683]
 - Fixed the error message when trying to build with DUB from a directory that doesn't contain a package - [issue #696][issue696]
 - Fixed running the pre-compiled version of DUB on Mac OS versions prior to 10.11 (by Guillaume Piolat aka p0nce) - [pull #704][issue704]
 - Fixed "dub dustmite" to emit a proper DUB command line if no explicit compiler/architecture is given
 - Fixed "dub dustmite" when invoked on packages with path based dependencies - [issue #240][issue240], [pull #762][issue762]
 - Fixed target type inheritance from the top level scope in the SDLang recipe parser
 - Fixed the error message when a dependency name is omitted in an SDLang recipe (by lablanu) - [pull #723][issue723]
 - Fixed the error message when using one of the "list" modes of "dub describe" on a target type "none" package - [issue #739][issue739]
 - Fixed writing the "subConfigurations" field in the JSON recipe of downloaded packages - [issue #745][issue745]
 - Fixed recently updated packages sometimes to fail to download - [issue #528][issue528]
 - Fixed handling of path based dependencies that have internal sub package references - [issue #754][issue754], [pull #766][issue766]
 - Fixed issues with generated CMake files due to backslashes in paths on Windows (by Steven Dwy) - [pull #738][issue738]
 - Fixed path based dependencies sometimes overriding version based dependencies of the same package - [issue #777][issue777]
 - Fixed loading of packages that have a path based selection
 - Fixed detection of compiler errors in the build output for generated Sublime Text projects (by Justinas Šneideris aka develop32) - [pull #788][issue788]
 - Fixed handling of certain libraries that got included using "pkg-config" (by Jean-Baptiste Lab) - [issue #782][issue782], [pull #794][issue794]
 - Quick fix for building shared libraries with LDC/Windows/OS X and DMD/OS X (by Guillaume Piolat aka p0nce) - [pull #801][issue801]
 - Fixed several issues with the SDLang parser
 - Fixed release-specific regressions regarding sub package dependencies that got ignored during dependency graph collection - [issue #803][issue803], [pull #807][issue807]
 - Fixed target type "none" packages still generating a binary target (affected `dub describe`)
 - Fixed `dub describe --data-list target-type` work for target type "none" packages


[issue240]: https://github.com/dlang/dub/issues/240
[issue346]: https://github.com/dlang/dub/issues/346
[issue349]: https://github.com/dlang/dub/issues/349
[issue361]: https://github.com/dlang/dub/issues/361
[issue502]: https://github.com/dlang/dub/issues/502
[issue528]: https://github.com/dlang/dub/issues/528
[issue616]: https://github.com/dlang/dub/issues/616
[issue633]: https://github.com/dlang/dub/issues/633
[issue635]: https://github.com/dlang/dub/issues/635
[issue640]: https://github.com/dlang/dub/issues/640
[issue663]: https://github.com/dlang/dub/issues/663
[issue674]: https://github.com/dlang/dub/issues/674
[issue680]: https://github.com/dlang/dub/issues/680
[issue683]: https://github.com/dlang/dub/issues/683
[issue686]: https://github.com/dlang/dub/issues/686
[issue692]: https://github.com/dlang/dub/issues/692
[issue693]: https://github.com/dlang/dub/issues/693
[issue696]: https://github.com/dlang/dub/issues/696
[issue702]: https://github.com/dlang/dub/issues/702
[issue704]: https://github.com/dlang/dub/issues/704
[issue709]: https://github.com/dlang/dub/issues/709
[issue715]: https://github.com/dlang/dub/issues/715
[issue723]: https://github.com/dlang/dub/issues/723
[issue724]: https://github.com/dlang/dub/issues/724
[issue732]: https://github.com/dlang/dub/issues/732
[issue733]: https://github.com/dlang/dub/issues/733
[issue734]: https://github.com/dlang/dub/issues/734
[issue735]: https://github.com/dlang/dub/issues/735
[issue738]: https://github.com/dlang/dub/issues/738
[issue739]: https://github.com/dlang/dub/issues/739
[issue745]: https://github.com/dlang/dub/issues/745
[issue754]: https://github.com/dlang/dub/issues/754
[issue757]: https://github.com/dlang/dub/issues/757
[issue759]: https://github.com/dlang/dub/issues/759
[issue762]: https://github.com/dlang/dub/issues/762
[issue766]: https://github.com/dlang/dub/issues/766
[issue772]: https://github.com/dlang/dub/issues/772
[issue777]: https://github.com/dlang/dub/issues/777
[issue782]: https://github.com/dlang/dub/issues/782
[issue785]: https://github.com/dlang/dub/issues/785
[issue788]: https://github.com/dlang/dub/issues/788
[issue794]: https://github.com/dlang/dub/issues/794
[issue801]: https://github.com/dlang/dub/issues/801
[issue803]: https://github.com/dlang/dub/issues/803
[issue807]: https://github.com/dlang/dub/issues/807
[issue823]: https://github.com/dlang/dub/issues/823


v0.9.24 - 2015-09-20
--------------------

### Features and improvements ###

 - Added support for [SDLang][sdl-package-format] based package descriptions - [issue #348][issue348], [pull #582][issue582]
 - Source code updated to build with DMD 2.064.2 through 2.068.0
 - Enhanced `dub describe` support:
   - The D API is now strongly typed instead of using `Json`
   - Added a `"targets"` field that can be used to sport external build tools
   - Added a `--data=X` switch to get information in a shell script friendly format (by Nick Sabalausky) - [pull #572][issue572]
   - Added an `"active"` field to each package to be used to signal if a certain dependency takes part in the build - [issue #393][issue393]
   - Added a set of additional environment variables that are available to pre/post build/generate commands (by Nick Sabalausky) - [issue #593][issue593]
   - Errors and warnings are not suppressed anymore, but output to stderr
   - Added the possibility to get all import paths for `dub describe` (by w0rp) - [pull #552][issue552], [issue #560][issue560], [pull #561][issue561]
 - Added stricter package name validation checks
 - Added a `--bare` option to search for dependencies only in the current directory (useful for running tests)
 - Removed the deprecated "visuald-combined" generator (use `dub generate visuald --combined` instead)
 - The command line shown for verbose output now contain the same quotes as used for the actual command invocation
 - Uses `-vcolumns` for DMD if supported - [issue #581][issue581]
 - Properly suppressing compiler output when `--quiet` or `--vquiet` are given (by Nick Sabalausky) - [issue #585][issue585], [pull #587][issue587]
 - Added a warning when referencing sub packages by their path (instead of their parent's path)
 - Building `sourceLibrary` targets with `-o-` is allowed now (enables documentation generation in particular) - [issue #553][issue553]
 - The VisualD generator doesn't use a "_d" suffix for debug build targets anymore (by Guillaume Piolat aka p0nce) - [pull #617][issue617]
 - Added a new "profile-gc" build type
 - Cleaned up console output (parts by Guillaume Piolat aka p0nce) - [pull #621][issue621]
 - Added "arm" and "arm_thumb" cross-compilation invocation support for GDC
 - Added configuration support to set the default compiler binary "defaultCompiler" field in the settings.json file
 - Removed the build script based selection of the default compiler (by Marc Schütz) - [pull #678][issue678]
 - Added a `--skip-registry=` switch to skip searching for packages on remote registries - [issue #580][issue580]

### Bug fixes ###

 - Fixed quoting of command line arguments for the DMD backend in the linker phase - [issue #540][issue540]
 - Fixed running Dustmite with versioned dependencies that are available as a git working copy
 - Fixed dependency resolution for packages that have sub packages and all of them are path based - [issue #543][issue543]
 - Fixed the error message for path based dependencies that are missing a package description file - see [issue #535][issue535]
 - Fixed running Dustmite with dub not available in `PATH` - [pull #547][issue547]
 - Fixed passing compiler, architecture, build type and configuration options to Dustmite - [pull #547][issue547]
 - Fixed return code when `dub run` is used on a library (returns non-zero now) - [pull #546][issue546]
 - Fixed spurious warning when building a package by name and DUB is not run from a package directory
 - Fixed handling of dependency errors that occur during automatic upgrade checks - [issue #564][issue564], [pull #565][issue565]
 - Fixed the architecture flag for x64 passed to LDC (by p0nce) - [pull #574][issue574]
 - Fixed enforcement of build requirements in dependencies - [issue #592][issue592]
 - Fixed `dub remove` to only remove managed packages - [issue #596][issue596]
 - Added a workaround for a data corruption issue (codegen bug) - [issue #601][issue601]
 - Fixed building dynamic libraries with DMD - [issue #613][issue613]

[sdl-package-format]: http://code.dlang.org/package-format?lang=sdl
[issue348]: https://github.com/dlang/dub/issues/348
[issue393]: https://github.com/dlang/dub/issues/393
[issue535]: https://github.com/dlang/dub/issues/535
[issue540]: https://github.com/dlang/dub/issues/540
[issue543]: https://github.com/dlang/dub/issues/543
[issue546]: https://github.com/dlang/dub/issues/546
[issue547]: https://github.com/dlang/dub/issues/547
[issue552]: https://github.com/dlang/dub/issues/552
[issue552]: https://github.com/dlang/dub/issues/552
[issue553]: https://github.com/dlang/dub/issues/553
[issue560]: https://github.com/dlang/dub/issues/560
[issue561]: https://github.com/dlang/dub/issues/561
[issue564]: https://github.com/dlang/dub/issues/564
[issue565]: https://github.com/dlang/dub/issues/565
[issue572]: https://github.com/dlang/dub/issues/572
[issue574]: https://github.com/dlang/dub/issues/574
[issue580]: https://github.com/dlang/dub/issues/580
[issue581]: https://github.com/dlang/dub/issues/581
[issue582]: https://github.com/dlang/dub/issues/582
[issue585]: https://github.com/dlang/dub/issues/585
[issue587]: https://github.com/dlang/dub/issues/587
[issue592]: https://github.com/dlang/dub/issues/592
[issue593]: https://github.com/dlang/dub/issues/593
[issue596]: https://github.com/dlang/dub/issues/596
[issue601]: https://github.com/dlang/dub/issues/601
[issue613]: https://github.com/dlang/dub/issues/613
[issue617]: https://github.com/dlang/dub/issues/617
[issue621]: https://github.com/dlang/dub/issues/621
[issue678]: https://github.com/dlang/dub/issues/678

v0.9.23 - 2015-04-06
--------------------

### Features and improvements ###

 - Compiles with DMD frontend versions 2.064 up to 2.067
 - Largely reduced the execution time needed by DUB itself during builds - [pull #388][issue388]
 - Added a `dub clean-caches` command to clear online registry meta data that is cached locally - [pull #433][issue433]
 - Added a "deimos" template type to the `dub init` command - [pull #431][issue431]
 - Added support for dub init to take a list of dependencies (by Colin Grogan) - [pull #453][issue453]
	 - Example: `dub init myProj logger vibe-d gfm --type=vibe.d`
	 - DUB will try to get the latest version number for each of these dependencies from [code.dlang.org](http://code.dlang.org/) and automatically add them to the dependencies section of dub.json
	 - The previous syntax where the argument to `dub init` is the project type instead of a dependency list is preserved, but deprecated - use the `--type=` switch instead
 - Added a project generator for Sublime Text (by Nicholas Londey) - [pull #461][issue461]
 - Added a project generator for CMake files (by Steven Dwy) - [pull #489][issue489]
 - Added support for `dub test` and modules where the path doesn't match the module name (by Szabo Bogdan) - [pull #344][issue344]
 - Added `dub --version` option to output the program version and build date - [pull #513][issue513]
 - Improved `"copyFiles"` support
     - Added support for glob matches (by Colden Cullen) - [pull #407][issue407]
     - Added support for copying directories (by Vadim Lopatin) - [pull #471][issue471]
     - Files are now hard linked into the target directory instead of making a real copy
     - Avoids to hard link `"copyFiles"` that have not changed in the source directory on Windows - [issue #511][issue511]
 - DUB now searches the PATH for installed compilers and chooses the default compiler as appropriate - [issue #480][issue480], [pull #506][issue506]
 - `--build-mode=singleFile` can now build several files in parallel using the `--parallel` switch - [issue #498][issue498]
 - Improved the JSON error diagnostic format to `file(line): Error: message` for better IDE integration - [issue #317][issue317]

### Bug fixes ###

 - Fixed determining module names from empty modules for `dub test` (by Szabo Bogdan) - [pull #458][issue458]
 - Fixed generating VisualStudio solution files on Win64 (by Nicholas Londey) - [pull #455][issue455]
 - Fixed erroneously adding "executable" dependencies to the list of link dependencies (by Михаил Страшун aka Dicebot) - [pull #474][issue474]
 - Fixed overriding the default source paths with `"sourcePaths"` - [issue #483][issue483]
 - Fixed removing packages when build output files exist - [issue #377][issue377]
 - Fixed handling of sub package references that specify an explicit path - [issue #448][issue448]
 - Fixed erroneous detection of a "sourcemain.d" source file under certain circumstances - [issue #487][issue487]
 - Fixed `dub build -t ddox` on OS X - [issue #354][issue354]
 - Fixed using unique temporary files (by Михаил Страшун aka Dicebot) - [issue #482][issue482], [pull #497][issue497]
 - Fixed compiler command line issues on Windows with `--buildMode=singleFile` (by machindertech) - [pull #505][issue505]
 - Fixed a version range match error (">=A <B" + "==B" was merged to "==B")
 - Fixed broken up-to-date detection of changed overridden string import files - [issue #331][issue331]
 - Fixed handling of the new `-m32mscoff` flag (is now also passed to the linker stage)
 - Fixed handling of several command line options for GDC (by Iain Buclaw) - [pull #387][issue387]
 - Fixed handling of `"buildTypes"` for downloaded packages (by sinkuu) - [pull #406][issue406]

[issue317]: https://github.com/rejectedsoftware/dub/issues/317
[issue331]: https://github.com/rejectedsoftware/dub/issues/331
[issue344]: https://github.com/rejectedsoftware/dub/issues/344
[issue354]: https://github.com/rejectedsoftware/dub/issues/354
[issue377]: https://github.com/rejectedsoftware/dub/issues/377
[issue387]: https://github.com/rejectedsoftware/dub/issues/387
[issue388]: https://github.com/rejectedsoftware/dub/issues/388
[issue406]: https://github.com/rejectedsoftware/dub/issues/406
[issue407]: https://github.com/rejectedsoftware/dub/issues/407
[issue431]: https://github.com/rejectedsoftware/dub/issues/431
[issue433]: https://github.com/rejectedsoftware/dub/issues/433
[issue448]: https://github.com/rejectedsoftware/dub/issues/448
[issue453]: https://github.com/rejectedsoftware/dub/issues/453
[issue455]: https://github.com/rejectedsoftware/dub/issues/455
[issue458]: https://github.com/rejectedsoftware/dub/issues/458
[issue461]: https://github.com/rejectedsoftware/dub/issues/461
[issue471]: https://github.com/rejectedsoftware/dub/issues/471
[issue474]: https://github.com/rejectedsoftware/dub/issues/474
[issue480]: https://github.com/rejectedsoftware/dub/issues/480
[issue482]: https://github.com/rejectedsoftware/dub/issues/482
[issue483]: https://github.com/rejectedsoftware/dub/issues/483
[issue487]: https://github.com/rejectedsoftware/dub/issues/487
[issue489]: https://github.com/rejectedsoftware/dub/issues/489
[issue497]: https://github.com/rejectedsoftware/dub/issues/497
[issue498]: https://github.com/rejectedsoftware/dub/issues/498
[issue505]: https://github.com/rejectedsoftware/dub/issues/505
[issue506]: https://github.com/rejectedsoftware/dub/issues/506
[issue511]: https://github.com/rejectedsoftware/dub/issues/511
[issue513]: https://github.com/rejectedsoftware/dub/issues/513


v0.9.22 - 2014-09-22
--------------------

### Features and improvements ###

 - Implemented an improved dependency handling (supported by Matthias Dondorff)
	 - Deprecated `"~branch"` based dependencies - these have proven to facilitate unresolvable versioning conflicts
	 - Added a "selections" file that contains the pinned versions of all dependencies for more control - `dub upgrade` can be used to update this file
	 - Package selections can be overridden user or system wide using `dub add-override`
	 - When determining the version of a GIT working copy, the latest tag is preferred over the branch
	 - See the [full rationale](https://github.com/rejectedsoftware/dub/wiki/...)
 - Implemented the `dub dustmite` command for comfortable creation of reduced test cases of DUB packages
	 - All packages are automatically copied to an isolated folder where [Dustmite](https://github.com/CyberShadow/DustMite/wiki) can do its job
	 - DUB is run in a special mode that doesn't require expensive initialization, so that it doesn't slow down the reduction process
	 - The test condition can be a specific exit code or an output regex match on either the compiler, linker, or program run
 - Added support for single file builds (by Mathias Lang aka Geod24) - [pull #364][issue364]
 - The special `"*"` version specification now matches any version or branch (should always be used for referencing sub packages of the same package)
 - Warn about using certain build options outside of build types (in addition to warning about certain `"dflags"`)
 - Removed explicit linking against Phobos on Linux when building using DUB (fixed building with DMD 2.065)
 - Fixed imports for DMD master (by John Colvin) - [pull #283][issue283]
 - Path based dependencies don't require a version number anymore (ignored)
 - Add support for vibe.d based HTTP downloads for better integration into vibe.d projects
 - `"mainSourceFile"` is now implicitly added to `"sourceFiles"`
 - `"preGenerateCommands"` are now run before collecting source files, enabling better support for generating source files - [issue #144][issue144]
 - Added a `-missing-only` switch to `dub upgrade` to get the same upgrade/fetch behavior as for `dub build` - see also [issue #271][issue271]
 - The default compiler is now the one that was used to build DUB itself (by Iain Buclaw) - [pull #303][issue303]
 - When running an executable, the working directory is now only changed if an explicit `"workingDirectory"` is specified
 - The compiler is now invoked to determine the actual build platform for the chosen compiler flags instead of simply guessing
	 - Implemented for GDC by Kinsey Moore aka opticron - [pull #324][issue324]
 - Added a basic `dub clean` command - [issue #134][issue134]
 - Added a spell checker for the `-c`/`--config` flag (by Andrej Mitrovic) - [pull #313][issue313]
 - Added support for `$ROOT_PACKAGE_DIR` and `$<dependency>_PACKAGE_DIR` variables
 - Generalized the `--local`/`--system` flags to `--cache=<location>`, which is now available for all commands (by Colden Cullen) - [pull #306][issue306]
 - Added a `--build-mode` switch to choose between combined build and separate compile/link for DMD
 - When building a static library, its dependencies are not built anymore - [issue #316][issue316]
 - Displaying the line number where parsing a JSON document fails - see [issue #317][issue317]
 - Added a shorthand syntax for sub packages (":subpack" instead of "parent:subpack") - [issue #315][issue315]
 - Replace all "package.json" files/mentions with "dub.json" and clean up white space throughout the code base (by James Clarke aka jrtc27) - [pull #337][issue337], [pull #338][issue338], [pull #339][issue339]
 - `dub describe` not outputs all source/import files of all configurations and platforms - [issue #185][issue185]
 - Added basic support for the new human readable `"systemDependencies"` field
 - Added a `--temp-build` switch to force building in a temporary folder - [issue #294][issue294]
 - Using `executeShell` when invoking tools to enable more flexible use of shell features - [issue #356][issue356]
 - `dub init` now creates a default `.gitignore` file
 - An exit code of `-9` for a tool now triggers a short message with a possible cause (out of memory)
 - The information about possible package upgrades is now cached for one day, resulting in less online queries to the package registry
 - Implemented separate compile/link mode for GDC (by Mathias Lang aka Geod24) - [pull #367][issue367]
 - `.def` files are now passed to the linking stage when doing separate compile/link building
 - Added BASH shell completion script (by Per Nordlöw) - [issue #154][issue154]
 - Added FISH shell completion script (by Matt Soucy) - [pull #375][issue375]

### Bug fixes ###

 - Fixed automatic removing of packages, removing was only possible with --force-remove.
 - Fixed "local" package fetching (was doing the same as "system") - [issue #259][issue259]
 - Fixed handling of `"mainSourceFile"` when building with `--rdmd` - [issue #263][issue263]
 - Fixed useless separate compilation of dependencies when building with `--rdmd` - see [issue #255][issue255]
 - Fixed detection of known files during package removal, caused by a missing ending slash (by Matthias Dondorff)
 - Fixed `dub fetch <package> --version=<version>` to actually fetch the supplied version (by Matthias Dondorff)
 - Fixed linker issues for GCC based linking by putting `-l` flags after the list of source files - [issue #281][issue281]
 - Fixed spurious log output happening during `dub describe` - [issue #221][issue221]
 - Fixed interrupting the DDOX process for `dub -b ddox` (by Martin Nowak) - [pull #291][issue291]
 - Fixed building library targets with LDC (by Dmitri Makarov) - [pull #296][issue296]
 - Fixed the `"disallowInlining"` build option (by sinkuu) - [pull #297][issue297]
 - Fixed determining build flags using pkg-config when some libraries are unknown to pkg-config - [issue #274][issue274]
 - Fixed detection of dependency cycles - [issue #280][issue280]
 - Fixed detection of a required rebuild when the compiler (front end) version changes - [issue #284][issue284]
 - Fixed building of packages with a non-existent `"targetPath"` - [issue #261][issue261]
 - Fixed the warning that should appear when using manual `-debug=` flags instead of `"debugVersions"` - [issue #310][issue310]
 - Fixed processing of variables in `"preGenerateCommands"` and `"postGenerateCommands"`
 - Fixed handling of empty path nodes (e.g. "/home//someone/somefile") - [issue #177][issue177]
 - Fixed the up-to-date check for intermediate dependencies
 - Fixed detection of equal paths for `dub add-local` when only the ending slash character differs - [issue #268][issue268]
 - Fixed a bogus warning that the license of a sub package differs from the parent package when the sub package doesn't specify a license
 - Fixed building when files from "\\UNC" paths are involved - [issue #302][issue302]
 - Fixed up-to-date checking for embedded sub packages (by sinkuu) - [pull #336][issue336]
 - Fixed outputting multiple instances of the same platform flag which broke the build for some compilers - [issue #346][issue346]
 - Fixed referencing path based sub packages - [issue #347][issue347]
 - Fixed various error messages (by p0nce and sinkuu) - [pull #368][issue368], [pull #376][issue376]
 - Fixed the "ddox" build mode when DDOX hasn't already been installed - [issue #366][issue366]
 - Fixed probing the compiler for platform identifiers when performing cross compiling (by Mathias Lang aka Geod24) - [pull #380][issue380]
 - Fixed erroneously dropping the `"buildTypes"` field of downloaded packages (by sinkuu) - [pull #406][issue406]
 - Fixed trying to copy files with the same source and destination
 - Fixed downloading of packages with "+" in their version - [issue #411][issue411]
 - Fixed building dependencies with versions containing "+" on Windows/OPTLINK
 - Fixed a crash when sub packages of non-installed base packages are references - [issue #398][issue398]
 - Fixed repeated download of base packages when a non-existent sub package is referenced
 - Fixed intermediate build path for `--compiler=` binaries specified with path separators - [issue #412][issue412]

[issue134]: https://github.com/rejectedsoftware/dub/issues/134
[issue144]: https://github.com/rejectedsoftware/dub/issues/144
[issue154]: https://github.com/rejectedsoftware/dub/issues/154
[issue177]: https://github.com/rejectedsoftware/dub/issues/177
[issue185]: https://github.com/rejectedsoftware/dub/issues/185
[issue221]: https://github.com/rejectedsoftware/dub/issues/221
[issue255]: https://github.com/rejectedsoftware/dub/issues/255
[issue259]: https://github.com/rejectedsoftware/dub/issues/259
[issue261]: https://github.com/rejectedsoftware/dub/issues/261
[issue263]: https://github.com/rejectedsoftware/dub/issues/263
[issue268]: https://github.com/rejectedsoftware/dub/issues/268
[issue271]: https://github.com/rejectedsoftware/dub/issues/271
[issue274]: https://github.com/rejectedsoftware/dub/issues/274
[issue280]: https://github.com/rejectedsoftware/dub/issues/280
[issue281]: https://github.com/rejectedsoftware/dub/issues/281
[issue283]: https://github.com/rejectedsoftware/dub/issues/283
[issue284]: https://github.com/rejectedsoftware/dub/issues/284
[issue291]: https://github.com/rejectedsoftware/dub/issues/291
[issue294]: https://github.com/rejectedsoftware/dub/issues/294
[issue296]: https://github.com/rejectedsoftware/dub/issues/296
[issue297]: https://github.com/rejectedsoftware/dub/issues/297
[issue302]: https://github.com/rejectedsoftware/dub/issues/302
[issue303]: https://github.com/rejectedsoftware/dub/issues/303
[issue306]: https://github.com/rejectedsoftware/dub/issues/306
[issue310]: https://github.com/rejectedsoftware/dub/issues/310
[issue313]: https://github.com/rejectedsoftware/dub/issues/313
[issue315]: https://github.com/rejectedsoftware/dub/issues/315
[issue316]: https://github.com/rejectedsoftware/dub/issues/316
[issue317]: https://github.com/rejectedsoftware/dub/issues/317
[issue324]: https://github.com/rejectedsoftware/dub/issues/324
[issue336]: https://github.com/rejectedsoftware/dub/issues/336
[issue337]: https://github.com/rejectedsoftware/dub/issues/337
[issue338]: https://github.com/rejectedsoftware/dub/issues/338
[issue339]: https://github.com/rejectedsoftware/dub/issues/339
[issue346]: https://github.com/rejectedsoftware/dub/issues/346
[issue347]: https://github.com/rejectedsoftware/dub/issues/347
[issue356]: https://github.com/rejectedsoftware/dub/issues/356
[issue364]: https://github.com/rejectedsoftware/dub/issues/364
[issue366]: https://github.com/rejectedsoftware/dub/issues/366
[issue367]: https://github.com/rejectedsoftware/dub/issues/367
[issue368]: https://github.com/rejectedsoftware/dub/issues/368
[issue375]: https://github.com/rejectedsoftware/dub/issues/375
[issue376]: https://github.com/rejectedsoftware/dub/issues/376
[issue380]: https://github.com/rejectedsoftware/dub/issues/380
[issue398]: https://github.com/rejectedsoftware/dub/issues/398
[issue406]: https://github.com/rejectedsoftware/dub/issues/406
[issue411]: https://github.com/rejectedsoftware/dub/issues/411
[issue412]: https://github.com/rejectedsoftware/dub/issues/412


v0.9.21 - 2014-02-22
--------------------

### Features and improvements ###

 - Implemented building dependencies as separate libraries (use `--combined` to use - almost - the old behavior)
 - The preferred package description file name is now "dub.json" instead of "package.json" (which is still supported)
 - Revamped command line help now shows detailed help for each command
 - Added `dub test` to run the unit tests of a package using a custom main() function
 - Public sub packages can now (and are recommended to) reside in sub folders
 - Added ruby style `~>` version specifications: `"~>1.0.2"` is equivalent to `">=1.0.2 <1.1.0"` and `"~>1.3"` is equivalent to `">=1.3.0 <2.0.0"`
 - `--annotate` now works for all commands
 - Added a `--force-remove` switch to force package removal when untracked files are found in a package folder
 - Added a `"mainSourceFile"` field to better control how `--rdmd` and `dub test` work
 - The target binary (if any) is now automatically deleted after a linker error to avoid partially linked binaries
 - Added `--force` to `dub build` and `dub run` to force recompilation even if already up to date
 - Renamed the "debug_" and "release" build options to "debugMode" and "releaseMode" to avoid the D keyword clash
 - Renamed the "noBoundsChecks" build option to "noBoundsCheck" to be consistent with the corresponding build requirement
 - `dub init xxx vibe.d` now emits a `-version=VibeDefaultMain` as required by the latest versions
 - Reimplemented the VisualD project generator to use the new compile target logic
    - Instead of `dub generate visuald-combined` use `dub generate visuald --combined`
    - Properly handles the explicit library target types (those other than `"targetType": "library"`)
 - Added support for `dub add-local` without an explicit version argument (will be inferred using GIT) (by p0nce) - [pull #194][issue194]
 - Added a new "release-nobounds" build type
 - Improved the error message when "dub remove" fails because of a missing installation journal
 - Removed the Mono-D project generator - use Mono-D's built in DUB support instead
 - Added support for public sub packages in sub folders - this is the preferred way to use sub packages, see <http://code.dlang.org/package-format#sub-packages>
 - Only "main.d"/"app.d" or "packname/main.d"/"packname/app.d" are now automatically treated as `"mainSourceFile"` for executable targets and none for library targets
 - Excessive/unknown command line arguments now result in an error
 - The "checking dependencies" message on startup is now a diagnostic message
 - A `"dflags"` entry of the form `-defaultlib=*` for DMD is now passed to the linking stage for separate compilation
 - Added simple support for `--arch=x86` and `--arch=x86_64` and LDC
 - The order of source files as passed to the compiler is now sorted by name to avoid random triggering of order dependent compiler issues

### Bug fixes ###

 - Fixed a malformed log message for files with modification times in the future
 - Fixed handling of absolute working directories
 - Fixed a segmentation fault on OS X when doing `dub upgrade` - [issue #179][issue179]
 - Fixed extraction of pre-release SemVer versions from the "git describe" output
 - Fixed handling of paths with spaces in generated VisualD projects
 - Fixed DUB binaries compiled with GDC/LDC to work around a crash issue in `std.net.curl` - [issue #109][issue109], [issue #135][issue135]
 - Fixed iterating over directories containing invalid symbols links (e.g. when searching a directory for packages)
 - Fixed the path separators used for `$DUBPATH` (':' on Posix and ';' on Windows)
 - Fixed using custom registries in the global DUB configuration file - [issue #186][issue186]
 - Fixed assertions triggering when `$HOME` is a relative path (by Ognjen Ivkovic) - [pull #192][issue192]
 - Fixed the VisualD project generator to enforce build requirements
 - Fixed build requirements to also affect compiler options of the selected build
 - Fixed configuration resolution for complex dependency graphs (it could happen that configurations were picked that can't work on the selected platform)
 - Fixed `dub build -b ddox` to only copy resource files from DDOX if they are newer than existing files on Posix
 - Fixed storing sub packages when the modified package description is written after fetching a package
 - Fixed a bogus "conflicting references" error when referencing sub packages [issue #214][issue214]
 - Fixed a null pointer dereference for locally registered package directories that had been deleted
 - Fixed determining the version of the root package (previously, `~master` was always assumed)
 - Fixed parsing of `==~master` style dependencies (equivalent to just `~master`)
 - Fixed handling of packages with upper case letters in their name (which is not allowed)
 - Fixed running applications on Windows with relative paths (`.\` gets prepended now)


[issue109]: https://github.com/rejectedsoftware/dub/issues/109
[issue135]: https://github.com/rejectedsoftware/dub/issues/135
[issue179]: https://github.com/rejectedsoftware/dub/issues/179
[issue186]: https://github.com/rejectedsoftware/dub/issues/186
[issue192]: https://github.com/rejectedsoftware/dub/issues/192
[issue194]: https://github.com/rejectedsoftware/dub/issues/194
[issue214]: https://github.com/rejectedsoftware/dub/issues/214


v0.9.20 - 2013-11-29
--------------------

### Features and improvements ###

 - Compiles on DMD 2.064 without warnings - [issue #116][issue116]
 - Builds are cached now by default in the ".dub/" sub folder of each package
 - An explicit "dub upgrade --prerelease" is now necessary to upgrade to pre-release versions of dependencies
 - "dub describe" and generated VisualD projects now also contain pure import and string import files
 - "dub run" now only builds in "/tmp" or "%TEMP%" if the package folder is write protected - [issue #82][issue82]
 - "dub init" can not take an optional project template name (currently "minimal" or "vibe.d")
 - Renamed "dub install" to "dub fetch" to avoid giving the impression of actual system installation (by Михаил Страшун aka Dicebot) - [pull #150][issue150]
 - Added support for "dub describe (package name)" and "dub describe --root=(path to package)" to describe packages outside of the CWD
 - `"excludedSourceFiles"` now supports [glob expressions](http://dlang.org/phobos/std_path.html#.globMatch) (by Jacob Carlborg) - [pull #155][issue155]
 - "dub --build=ddox" now starts a local HTTP server and automatically opens the browser to display the documentation
 - Environment variables can now be used inside path based fields in package.json (by Alexei Bykov) - [pull #158][issue158]
 - "dub describe" now contains a `"targetFileName"` field that includes the file extension (e.g. ".exe" or ".so")
 - Removed the compatibility version of the new `std.process` as it lacks support for `browse()`
 - Support using .obj/.lib/.res/.o/.a/.so/.dylib files to be specified as "sourceFiles", they will be bassed to the compiler at the linking stage
 - Added a "library-nonet" configuration to the package description file to compile without a CURL dependency
 - Added support for the "http_proxy" environment variable

### Bug fixes ###

 - Fixed building of explicitly selected packages with custom configurations (using "dub build (package name)")
 - Fixed running DUB from outside of a valid package directory when an explicit package name is given
 - Fixed dependency calculation for dependencies referenced in configuration blocks - [issue #137][issue137]
 - Fixed warnings to be enabled as errors by default again
 - Fixed resolution of dependencies when sub packages are involved - [issue #140][issue140]
 - Fixed handling of build options for GDC/LDC (by finalpatch) - [pull #143][issue143]
 - Fixed emitting "-shared -fPIC" for DMD when building shared libraries - [issue #138][issue138]
 - Fixed "dub --build=ddox" for target types other than "executable" - [issue #142][issue142]
 - Fixed a crash when loading the main package failed - [issue #145][issue145]
 - Fixed the error message for empty path strings in the `"sourcePaths"` field - see [issue #149][issue149]
 - Fixed representing empty relative paths by "." instead of an empty string - [issue #153][issue153]
 - Fixed running executables for projects outside of the CWD
 - Fixed copying of DDOX resources on Posix for "--build=ddox" (by Martin Nowak) - [pull #162][issue162]
 - Fixed ARM floating-point platform/version identifiers
 - Fixed generating VisualD projects for shared library packages (by p0nce) - [pull #173][issue173]
 - Fixed erroneous upgrading of packages that are not managed by DUB (for "dub upgrade") - [issue #171][issue171]
 - Fixed erroneously fetching the same package multiple times when sub packages are used
 - Fixed string representation of empty paths (fixes the target file name for generated VisualD projects)

[issue82]: https://github.com/rejectedsoftware/dub/issues/82
[issue116]: https://github.com/rejectedsoftware/dub/issues/116
[issue137]: https://github.com/rejectedsoftware/dub/issues/137
[issue140]: https://github.com/rejectedsoftware/dub/issues/140
[issue142]: https://github.com/rejectedsoftware/dub/issues/142
[issue143]: https://github.com/rejectedsoftware/dub/issues/143
[issue145]: https://github.com/rejectedsoftware/dub/issues/145
[issue149]: https://github.com/rejectedsoftware/dub/issues/149
[issue150]: https://github.com/rejectedsoftware/dub/issues/150
[issue153]: https://github.com/rejectedsoftware/dub/issues/153
[issue155]: https://github.com/rejectedsoftware/dub/issues/155
[issue158]: https://github.com/rejectedsoftware/dub/issues/158
[issue162]: https://github.com/rejectedsoftware/dub/issues/162
[issue171]: https://github.com/rejectedsoftware/dub/issues/171
[issue173]: https://github.com/rejectedsoftware/dub/issues/173


v0.9.19 - 2013-10-18
--------------------

### Features and improvements ###

 - Added the possibility to build or run a specific package, including sub packages
 - Implemented a new "--root=PATH" switch to let dub operate from a different directory than the current working directory
 - "dub init" now always emits lower case DUB package names
 - Improved diagnostic output for "dub add-local" and "dub remove-local"
 - Using the static version of Phobos fro building DUB to improve platform independence on Linux

### Bug fixes ###

 - Fixed erroneous "-debug" switches in non-debug builds
 - Enabled again a warning when using "-debug=" flags in "dflags" instead of using "debugVersions"
 - Fixed handling of paths with spaces for "--build=ddox"
 - Fixed inclusion of multiple instances of the same package.json files in the "visuald-combined" generator (by p0nce) - [pull #124][issue124]
 - Fixed response file output for LDC - [issue #86][issue86]
 - Fixed response file output for GDC - [issue #125][issue125]
 - Partially fixed working in paths with Unicode characters by avoiding `std.stdio.File` - [issue #130][issue130]

[issue86]: https://github.com/rejectedsoftware/dub/issues/86
[issue124]: https://github.com/rejectedsoftware/dub/issues/124
[issue125]: https://github.com/rejectedsoftware/dub/issues/125
[issue130]: https://github.com/rejectedsoftware/dub/issues/130


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
 - Fixed bogus warnings about "dflags" that are confused with flags that are a prefix of those
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
