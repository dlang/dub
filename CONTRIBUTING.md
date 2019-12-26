# Guidelines for Contributing

## Building

Build a development version of dub using either `./build.sh` or `./build.cmd` on Windows.
When you already have a working dub binary, you can also just run `dub build`, though that won't update the version string.

## Changelog

Every feature addition should come with a changelog entry, see the [changelog/README.md](changelog/README.md) for how to add a new entry. Any `.dd` file is rendered using ddoc and is the same format used across all dlang repos.
For bugfixes make sure to automatically [close the issue via commit message](https://blog.github.com/2013-01-22-closing-issues-via-commit-messages/) (e.g. `fixes #123`), so that they can be listed in the changelog.

## Backwards compatiblity

DUB is a command line tool, as well as a library that can be embedded into other applications. For this reason, any change to the public API, as well as to the command line interface, needs to be carefully reviewed for possible breaking changes. No breaking changes are allowed to enter the master branch at this point. However, deprecating symbols and adding new ones is a possible way to prepare for breaking changes that will get into 2.0.0.
