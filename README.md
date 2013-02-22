dub package manager
===================

Package and build manager for [D](http://dlang.org/) applications and libraries.

There is a central [package registry](https://github.com/rejectedsoftware/dub-registry/) located at <http://registry.vibed.org>. The location will likely change to a dedicated domain at some point.


Introduction
------------

DUB emerged as a more general replacement for [vibe.d's](http://vibed.org/) package manager. It does not imply a dependecy to vibe.d for packages and was extended to not only directly build projects, but also to generate project files (currently [VisualD](https://github.com/rainers/visuald) and [Mono-D](http://mono-d.alexanderbothe.com/)).

The project's pilosophy is to keep things as simple as possible. All that is needed to make a project a dub package is to write a short [package.json](http://registry.vibed.org/publish) file and put the source code into a `source` subfolder. It *can* then be registered on the public [package registry](http://registry.vibed.org) to be made available for everyone. Any dependencies specified in `package.json` are automatically downloaded and made available to the project during the build process.


Key features
------------

 - Simple package and build description not getting in your way

 - Integrated with Git, avoiding maintainance tasks such as incrementing version numbers or uploading new project releases

 - Generation of VisualD and Mono-D project/solution files

 - Support for DMD, GDC and LDC (common DMD flags are translated automatically)

 - Supports development workflows by optionally using local directories as a package source


Future direction
----------------

To make things as flexible as they need to be for certain projects, it is planned to gradually add more options to the package file format and eventually to add the possibility to specify an external build tool along with the path of it's output files. The idea is that DUB provides a convenient build management that suffices for 99% of projects, but is also usable as a bare package manager that doesn't get in your way if needed.


Installation
------------

DUB comes [precompiled](http://registry.vibed.org/download) for Windows, Mac OS, Linux and FreeBSD. It needs to have libcurl with SSL support installed (except on Windows).

The `dub` executable then just needs to be accessible from `PATH` and can be invoked from the root folder of any DUB enabled project to build and run it.

If you want to build for yourself, just install [DMD](http://dlang.org/download.html) and libcurl development headers and run `./build.sh`. On Windows you can simply run `build.cmd` without installing anything besides DMD.

### Arch Linux

Moritz Maxeiner has created a PKGBUILD file for Arch:

<https://aur.archlinux.org/packages/dub/>

