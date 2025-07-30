### Make a directory under test

### Write a test.config (if needed)
```
# Compilers that the test supports
dc_backend = [gdc, dmd, ldc]

# OSes that the test supported
os = [linux, windows, osx]

# Does your test require `dub build` instead of `dub run`?
# = none disables running dub
dub_command = build

# Does your test require a minimum D frontend version
dlang_fe_version_min = 2108

# locks
# This is really important for concurrency.
#
# You can put any key here, so be sure you don't typo it.
# run_unittest will always acquire a lock for <name_of_test>
# of each test case (the directory name).
#
# Example: If you have in a dub.json
#
# "dependencies": {
#     "dynlib-simple": { "path": "../1-dynLib-simple/" }
# }
#
# Then you should put `1-dynLib-simple` in here to make sure
# that your test is not run at the same time that `dub build`
# is run for `1-dynLib-simple`.
locks = [ 1-dynLib-simple ]

# Lets you pass `--config myconfig` when invoking dub
dub_config = myconfig
# ditto but with `--build`
dub_build_type = mybuild
# An array of arbitrary arguments to append to the CLI when invoking the test
extra_dub_args = [ -- -my-app-flag-1 ]

# Whether the test runner should interpret your program exiting with a non-zero
# status as the test succeeding. The default is false so a test exiting with
# 0 means success, otherwise failure. This settings allows you to swap it.
#
# If you explicitly fail the test by printing `[FAIL]:` to the stdout
# then this setting will not matter, the test failes regardless of exit status.
expect_nonzero = false

# If your test absolutely can not be run alongside any others, set this to `true`
must_be_run_alone = true
```

### You can put extra stuff in the extra folder

### What you can rely on
- `DUB` being present in the environment
- `DC` being present in the environment (and pointing to a D compiler)
- `DC` is an executable of `dmd`, `gdmd`, `ldc`, `ldmd` (so no `gdc`)
- `CURR_DIR` being present in the environment and pointing to the `test/` dir
- Your tests' `cwd` being the directory in which is resides
- `DUB_HOME` being set by `common.d` to a test-specific directory (so you can fetch, build, and, clean any packages without fear of conflict with other tests)

### What you can't rely on
- `DC` being `dmd` or other simple strings. `DC` could be `/usr/bin/dmd-2.109` or `x86_64-pc-linux-gnu-gdmd-11`.

### *Don't*s

Avoid overwriting `DFLAGS` as those can be set by users to fix system-specific failures.
The runner, for example, uses them to add flags that fix common build failures with `gdc`.

Do *NOT* (irreversibly) modify `<this_dub_repo>/bin/../etc/dub/settings.json`. That file is reserved for users to add custom settings.

### Extra stuff

In your test you can print to the console (stdout or stderr, both work) lines that start with:
1. `[INFO]: `
2. `[ERRROR]: `
3. `[FAIL]: `
4. `[SKIP]: `

and the runner will show them properly prefixed and colored in the test output. All other lines from your test will be printed with a `[INFO]: ` prefix and be hidden unless the `-v` switch is given to `run_unittest`.
(yes this means that printing `[INFO]: ` at the beginning of the line is pointless).
In `test/common` there are convenience functions for printing all of the above.
