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
# This is really important for concurrency. If you depend on a
# (non-source) library you have to list otherwise there will
# be multiple dub processes spawned that touch the same files
# which will lead to test failures.
#
# The multi-threaded speed-up is really nice so you have to
# suck it up and fill this.
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
```

### You can put extra stuff in the extra folder

### What you can rely on
- `DUB` being present in the environment
- `DC` being present in the environment (and pointing to a D compiler)
- `DC` is an executable of `dmd`, `gdmd`, `ldc`, `ldmd` (so no `gdc`)
- `CURR_DIR` being present in the environment and pointing to the `test/` dir
- Your tests' `cwd` being the directory in which is resides

### What you can't rely on
- `DC` being `dmd` or other simple strings. `DC` could be `/usr/bin/dmd-2.109` or `x86_64-pc-linux-gnu-gdmd-11`.

### *Don't*s

Try not to overwrite `DFLAGS` or `DUB_HOME`. Those could be used to inject settings into the test runner by the users.

### Extra stuff

In your test you can print to the console (stdout or stderr, both work) lines that start with:
1. `[INFO]: `
2. `[ERRROR]: `

and the runner will show them properly prefixed and colored in the test output. All other lines from your test will be printed with a `[INFO]: ` prefix and be hidden unless the `-v` switch is given to `run_unittest`. (yes this means that doing you printing `[INFO]: ` at the beginning of the line is pointless). There's the `test/common` dep if you want specialized functions for prefixing your output.
