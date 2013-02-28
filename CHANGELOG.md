Changelog
=========

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
