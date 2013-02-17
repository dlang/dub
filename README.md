dub package manager
===================

Package and build manager for [D](http://dlang.org/) applications and libraries.


Introduction
------------

DUB emerged as a more general replacement for [vibe.d's](http://vibed.org/) package manager. It does not imply a dependecy to vibe.d for packages and was extended to not only directly build projects, but also to generate project files (currently [VisualD](https://github.com/rainers/visuald) and [Mono-D](http://mono-d.alexanderbothe.com/)).

The project's pilosophy is to keep things as simple as possible. All that is needed to make a project a dub package is to write a short [package.json](http://registry.vibed.org/publish) file and put the source code into a `source` subfolder. It *can* then be registered on the public [package registry](http://registry.vibed.org) to be made available for everyone. Any dependencies specified in `package.json` are automatically downloaded and made available to the project during the build process.


Future direction
----------------

To make things as flexible as they need to for certain projects, it is planned to gradually add more options to the package file format and eventually to add the possibility to specify an external build tool along with the path of it's output files. The idea is that DUB provides a convenient build management that suffices for 99% of projects, but is also usable as a bare package manager that doesn't get in your way if needed.


Installation
------------

DUB comes [precompiled](http://registry.vibed.org/download) for Windows, Mac OS, Linux and FreeBSD. It needs to have the following dependencies installed (except on Windows):

 - libevent 2.0.x
 - OpenSSL

The `dub` executable then just needs to be accessible from `PATH` and can be invoked from the root folder of any DUB enabled project to build and run it.

If you want to build for yourself, you need to install [vibe.d](http://vibed.org/download) and run `vibe build` from DUB's main folder and rename the resulting "app" file to "dub".
