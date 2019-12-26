# Guidelines for Contributing

## Building

Build a development version of dub using either `./build.sh` or `./build.cmd` on Windows.
When you already have a working dub binary, you can also just run `dub build`, though that won't update the version string.

## Changelog

Every feature addition should come with a changelog entry, see the [changelog/README.md](changelog/README.md) for how to add a new entry. Any `.dd` file is rendered using ddoc and is the same format used across all dlang repos.
For bugfixes make sure to automatically [close the issue via commit message](https://blog.github.com/2013-01-22-closing-issues-via-commit-messages/) (e.g. `fixes #123`), so that they can be listed in the changelog.

## Backwards compatiblity

DUB is a command line tool, as well as a library that can be embedded into other applications. We aim to stay backwards compatible as long as possible and as required by the SemVer specification. For this reason, any change to the public API, as well as to the command line interface, needs to be carefully reviewed for possible breaking changes. No breaking changes are allowed to enter the master branch at this point.

However, to prepare for backwards-incompatible changes that go into the next major release, it is allowed to deprecate symbols, as well as to hide symbols and command line options from the documentation.
