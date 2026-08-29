# For test writers

The short version of the process is:

1. Make a new directory under test
2. (optionally) write a test.config if you need
3. Invoke `dub` in your code with any arguments/paths you need and check the generated files or output; or anything else you need to test.

Feel free to peek at other tests for inspiration.

# For test runners

Run:
```
DC=<your_dc> ./bin/dub run --root test/run_unittest -- <any_extra_args>
```

Where:
- `<your_dc>` is replaced by your desired D compiler.
  The supported variants are:
  - `dmd`
  - `ldc2`
  - `ldmd2`
  - `gdmd` (only very recent of the `gdmd` script work, the underlying `gdc` can be older)
  
  `gdc` is not supported.
  
- `<any_extra_args>`
  Can contain the switches:
  - `-j<jobs>` for how many tests to run in parallel
  - `-v` in order to show the full output of each test to the console, rather than only *starting* and *finished* lines. The full output is still saved to the `test.log` file so you can safely pass this switch and still have the full output available in case of a failure.
  - `--color[=<true|false>]` To turn on/off color output for log lines and the dub invocations. Note that this leads to color output being saved in the `test.log` file
  
  You can also pass any amount of glob patterns in order to select which tests to run.
  It is an error not to select any tests so if you misspell the pattern the runner will complain.
  
As an example, the following invocation:
```
DC=/usr/bin/dmd-2.111 ./bin/dub run --root test/run_unittest -- -j4 --color=false -v '1-exec-*'
```
runs the all the tests that match `1-exec-*` (currently those are `1-exec-simple` and `1-exec-simple-package-json`), without color but with full output, with 4 threads.

# Advanced test writing

## The `test.config` file

A summary of all the settings:
```
# Test requirements
os = [linux, windows, osx]
dc_backend = [gdc, dmd, ldc]
dlang_fe_version_min = 2108

# CLI switches passed to dub when running the test
dub_command = build
dub_config = myconfig
dub_build_type = mybuild
extra_dub_args = [ --, -my-app-flag-1 ]

# Synchronization 
locks = [ 1-dynLib-simple ]
must_be_run_alone = true

# Misc
expect_nonzero = false
```

The syntax is very basic:
- empty or whitespace-only lines are ignored
- comments start with `#` and can only be placed at the start of a line
- Other lines are treated as `key = value` assignments.

The value can be an array denoted by the `[` and `]` characters, with elements separated by commas.
The value can also be a simple string.
Quotes are not supported, nor can you span an array multiple lines.

The accepted keys are the members of the `TestConfig` struct in [test_config.d](/test/run_unittest/source/run_unittest/test_config.d)

The accepted values for each setting are based on their D type:
- `enum` accepts any of the names of the `enum`'s members
- `string` accepts any value
- `bool` accept only `true` and `false`

Arrays accept any number of their element's type.

As a shorthand, if an array contains only one element, you can skip writing the `[]` around the value.
For example, the following two lines are equivalent:
```
os = windows
os = [ windows ]
```

What follows are detailed descriptions for each setting key:

#### `os`

Restricts the test to only run on selected platforms.

For example:
```
os = [linux, osx]
```
will only run the test of `Linux` and `MacOS` platforms.

### `dc_backend`

Required that the compiler backend be one of the listed values.

For example:
```
dc_backend = [dmd, ldc]
```
will only run the test with `dmd`, `ldc2`, or `ldmd2`, but not with `gdmd`.

If you need to disallow `ldc2` but not `ldmd2` then you will need to do so pragmatically inside your test code.
The `common.skip` helper function can be used for this purpose.

### `dlang_fe_version_min`

Restrict the compiler frontend version to be higher or equal to the passed value.
The frontend version is the version of the `dmd` code each compiler contains.
For example `gdmd-14` has a FE version of `2.108`.

Example:
```
dlang_fe_version_min = 2101
```

Use this setting if you are testing a new feature of the compiler, otherwise try to make your test work with older compilers by not using very recent language features.

### `dub_command`

This selects how to run your test.
Possible values are:
- `build`
- `test`
- `run`

Each value translates to a `dub build`, `dub test`, or, `dub run` invocation.

This setting is an array so you can pass multiple of the above values, in case you need the test to be built multiple times.

The default value is `run`.

For example:
```
dub_command = build
```
will not run your test, it will only call `dub build` and interpret a zero exit status as success.

### `dub_config`

This selects the package configuration (the `--config` dub switch).

By default, no value is selected and the switch is not passed to dub.

For example:
```
dub_config = myconfig
```
will run your test with `dub run --config myconfig`

### `dub_build_type`

Similarly to `dub_config`, this selects what is passed to the `--build` switch.

By default, no value is passed.

For example:
```
dub_build_type = release
```
will result in your test being run as `dub run --build release`

### `extra_dub_args`

This is a catch-all setting for any specific switches you want to pass to dub.

For example:
```
extra_dub_args = [ --, --my-switch ]
```
will run the test as `dub run -- --my-switch`.

### `locks`

This setting is used to prevent tests that use the same resource/dependency from running at the same time.
While the runner tries to isolate each test by passing a specific `DUB_HOME` directory in order to avoid concurrent build of the same (named) package this is not always possible.

For example, if three tests depend on the same library in `extra/` those could not be run at the same time.
In that scenario, each of those three tests would need to have a `locks` setting with the same value, say `locks = extra/mydep`.
The value doesn't matter, so long as it matches between the three `test.config` files.
Do try, however, to use a self-explanatory name, in order to make it obvious why the tests can't be run in parallel.

As a special case, the runner always adds the directory name of the test to the `locks` setting to facilitate the few cases in which a test depends on another test.

For example, if you had two tests `1-lib` and `2-exec-dep-lib`, with `2-exec-dep-lib` having a dependency in its `dub.json` for `1-lib` then you can solve this with a single `test.config`.
It would be placed in the `2-exec-dep-lib` directory and contain:
```
locks = [ 1-lib ]
```

### `must_be_run_alone`

Similarly to `locks` this setting controls how a test is scheduled with regards to other tests.
It accepts only a `true` or `false` value and, if the value is `true`, like the name suggests, the test will only be run if no other tests are being run.

It stands to reason that you should only use this setting as a last resort, in case the functionality you are testing actively interferes with the test setup.
An example of such an operation may involve renaming the `dub` executable back and forth.

Example:
```
must_be_run_alone = true
```

### `expect_nonzero`

This setting controls the default behavior of deciding the test success/failure based on its exit status.
Normally a zero exit status means that the test completed successfully and a non-zero status means that something failed.
You can switch this behavior with this boolean setting and require that your test exits with a non-zero status in order to be declared successful.

Note that it is still possible to explicitly fail a test by printing a `[FAIL]: ` line in the output of your program (which is what the `common.die` helper does).
In such a case the test is still marked as a failure, even if `expect_nonzero` is set to `true`.

Example:
```
expect_nonzero = true
```

## General guarantees

- `DUB` exists in the environment
- `DC` exists in the environment
- Your test program's working directory is its test folder
- `DUB_HOME` being set and pointing to a test-specific directory.
  This allows you to freely build/fetch/remove packages without affecting the user's setup or interfere with other tests.
- `CURR_DIR` exists in the environment and point to the [test](/test) directory

## General requirements

### Try to respect `DFLAGS`

Try to respect the `DFLAGS` environment variable and not overwrite it, as it is meant for users to pass arguments possibly required by their setup.

If you test fails with any `DFLAGS` then it is acceptable to delete its value.

### Don't overwrite `etc/dub/settings.json`

This path, relative to the root of this repository, is meant for users to control `dub` settings.

### Avoid short names for packages

Don't have top-level packages (i.e. directly inside [test](/test)) with short or common names.
If two test have the same name (for example `test`) they risk being built at the same time and trigger race conditions between compiler processes.
Use names like `issue1202-test` and `issue1404-test`.

Note that it is fine to use names such as `test` when generating or building packages from inside your test, since at that point the test will have a separate `DUB_HOME` which will be local to your test so no conflicts can arise.

## Other notes

### Output format

The test runner picks up lines that start with:
- `[INFO]: `
- `[WARN]: `
- `[ERROR]: `
- `[FAIL]: `
- `[SKIP]: `

and either prints them with possible color or it marks the test as failed or skipped.

The `common` package provides convenience wrappers for these but you're free to print them directly if its easier.

`[FAIL]:` and `[SKIP]:` use the remaining portion of the line to tell the user why the test was skipped so try to print something meaningful.

### Directory structure

The common pattern is that each test is a folder inside `/test/`.
If your test needs some static files they are usually placed inside `sample/`.
If your test dynamically generated some data it is usually placed in a local `test/` subdirectory (for example `/test/custom-unittest/test`).
A `dub` subdirectory inside each test directory is also generated and `DUB_HOME` is set to point to it when the test is run.

### .gitignore usage

The default policy is black-list all, white-list as needed.
Try to follow this when you unmask your test's files, which you probably have to do when adding anything other that a `dub.json` and a `source/` directory.

### cleaning up garbage files

It's fine if your tests leave temporary files laying around in git-ignored paths.
You don't have to explicitly clean up everything as the user is entrusted to run `git clean -fdx` if they want to get rid of all the junk.

It is, however, important to perform all the necessary cleanup at the start of your test.
You can't assume that a previous invocation completed successfully or unsuccessfully so try to always start with a clean environment and manually reset all generated files or directories.

# Advanced test running

You can configure setting with either the `DFLAGS` environment variable or the `etc/dub/settings.json` file (relative to the root of this repository)

If you change `DFLAGS` take a note that `gdmd` may fail to build some tests unless you pass it `-q,-Wno-error -allinst`, so be sure to also include these flags.

The `dub/settings.json` file can be used to configure custom package registries which would allow you to run (some of) the tests without internet access.
It can also give you control of all the tests' inputs.
However, a few tests do fail without internet access and which packages would need to be manually downloaded is not clearly stated.
With some hacking it can be done but if you rely on this functionality feel free to open an issue if you want the situation to improve.
