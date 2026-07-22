Full-Stack tests may be written for any given bug, they live in the test directory`.

A test must be named using the issueXXXX-thing-fails-for-thing convention. A bash script ( with executable flag set ) and folder should be created with this name.

The script may execute arbitrary commands designed to replicate the bug in question, it may use the folder of the same name in any way to support recreating this bug.
Scripts have a number of special variables they may access:

```
$DC    The D compiler
$DUB    The built dub executable
$CURR_DIR    The current directory
$HOME    The home directory of the user
```

Scripts should use $DUB to run the dub executable built from the current branch being tested.
Scripts should use $DC to set the compiler Dub uses. Don't worry about explicitly setting a compiler ( i.e dmd, ldc, or gdc ), each test script is ran with each compiler.
The $(HOME) path should be used to avoid stomping over files which should not be stomped over.

Test scripts are free to create and delete files lmost everywhere ( i.e userwide dub configurations ) in order to replicate their bug.

A test's corresponding directory is commonly used to contain an example dub project.

Tests in the test directory should be used to demonstrate bugs which are exposed by things like:

    dub.json/.sdl files
    user/systemwide configurations
    Or to:
    test the stdout output of dub.

Try reading the existing tests in the test directory. Please include a test if you can.

Tests can be ran locally by exporting those special variables for your local environment.
For example, if the script you need to run uses CURR_DIR and DUB. Set those environment variables to point to something reasonable before running the script.

```
export CURR_DIR=.
export DUB=~/dub.git/bin/dub
```

Be careful though, some test scripts modify systemwide or userwide settings! Read the script before running it, or run it in a sandboxed environment.
