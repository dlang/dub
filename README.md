# dub package manager

Package and build manager for [D](http://dlang.org/) applications and libraries.

There is a central [package registry](https://github.com/dlang/dub-registry/) located at <http://code.dlang.org>.

[![GitHub tag](https://img.shields.io/github/tag/dlang/dub.svg?maxAge=86400)](#)
[![Buildkite](https://badge.buildkite.com/c54d71c42284a042b9d578e28e093dff35f20cc8528319b1b6.svg?branch=master)](https://buildkite.com/dlang/dub)

## Introduction

DUB emerged as a more general replacement for [vibe.d's](http://vibed.org/) package manager. It does not imply a dependency to vibe.d for packages and was extended to not only directly build projects, but also to generate project files (currently [VisualD](https://github.com/rainers/visuald)).
[Mono-D](http://mono-d.alexanderbothe.com/) also supports the use of dub.json (dub's package description) as the project file.

The project's philosophy is to keep things as simple as possible. All that is needed to make a project a dub package is to write a short [dub.json](http://code.dlang.org/publish) file and put the source code into a `source` subfolder. It *can* then be registered on the public [package registry](http://code.dlang.org) to be made available for everyone. Any dependencies specified in `dub.json` are automatically downloaded and made available to the project during the build process.

## Key features

 - Simple package and build description not getting in your way
 - Integrated with Git, avoiding maintenance tasks such as incrementing version numbers or uploading new project releases
 - Generates VisualD project/solution files, integrated into MonoD
 - Support for DMD, GDC and LDC (common DMD flags are translated automatically)
 - Supports development workflows by optionally using local directories as a package source

## Future direction

To make things as flexible as they need to be for certain projects, it is planned to gradually add more options to the [package file format](http://code.dlang.org/package-format) and eventually to add the possibility to specify an external build tool along with the path of it's output files. The idea is that DUB provides a convenient build management that suffices for 99% of projects, but is also usable as a bare package manager that doesn't get in your way if needed.

## Installation

DUB comes [precompiled](http://code.dlang.org/download) for Windows, OS X and Linux. It needs to have libcurl with SSL support installed (except on Windows).

The `dub` executable then just needs to be accessible from `PATH` and can be invoked from the root folder of any DUB enabled project to build and run it.

If you want to build for yourself, just install a D compiler such as [DMD](http://dlang.org/download.html) and libcurl development headers and run `./build.d`.

### Arch Linux

Михаил Страшун (Dicebot) maintains a dub package of the latest release in `Community`, for [x86_64](https://www.archlinux.org/packages/community/x86_64/dub/) and [i686](https://www.archlinux.org/packages/community/i686/dub/).
Moritz Maxeiner has created a PKGBUILD file for GIT master: <https://aur.archlinux.org/packages/dub-git/>

### Debian/Ubuntu Linux

Jordi Sayol maintains a DEB package as part of his [D APT repository](http://d-apt.sourceforge.net). Run `sudo apt-get install dub` to install.

### OS X

Chris Molozian has added DUB to [Homebrew](http://mxcl.github.io/homebrew/). Use `brew install dub` to install the stable version, optionally adding `--HEAD`/`--devel` to install the latest git master or development release respectively.

There is also a [MacPorts](https://www.macports.org/) package available. Type `sudo port install dub` to install the latest stable version.

### Windows

Daniel Jost maintains a dub package on [chocolatey](https://chocolatey.org/packages/dub). Use `cinst dub` or `cinst dub -version #.#.#` to install stable or a custom version respectively.

## Alpine Linux

Mathias (@Geod24) Lang maintains the Alpine Linux packages.
It is currently part of 'edge' and can be installed through `apk --no-cache add -X http://dl-cdn.alpinelinux.org/alpine/edge/testing dub`.

## OpenBSD

Brian Callahan (bcallah@) maintains the OpenBSD package. Use `pkg_add dub` to install it.

## Using DUB as a library

The [DUB package of DUB](http://code.dlang.org/packages/dub) can be used as a library to load or manipulate packages, or to resemble any functionality of the command line tool. The former task can be achieved by using the [Package class](https://github.com/dlang/dub/blob/master/source/dub/package_.d#L40). For examples on how to replicate the command line functionality, see [commandline.d](https://github.com/dlang/dub/blob/master/source/dub/commandline.d).

## Minimal D compiler required to build DUB

In general it is always recommended to build DUB with the latest version of your D compiler.
However, currently [2.076](https://dlang.org/changelog/2.076.0.html) is required to build DUB from source.

# Contributing

New contributers are always welcome, there's plenty to work on! For an easy start, take a look at issues marked [`bootcamp`](https://github.com/dlang/dub/labels/bootcamp)
The contributing guidelines can be found [here](https://github.com/dlang/dub/blob/master/CONTRIBUTING.md)
