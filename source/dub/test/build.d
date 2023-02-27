/*******************************************************************************

    Tests for `dub build`

*******************************************************************************/

module dub.test.build;

version (unittest):

import dub.test.base;

/// Test for cov-ctfe
unittest
{
    scope dub = new TestCLIApp();

    // Setup
    const pkg_path = dub.path.buildPath("cov-ctfe");
    std.file.mkdir(pkg_path);
    std.file.write(pkg_path.buildPath("dub.sdl"),
`name "test"
version "1.0.0"
targetType "executable"
dflags "-cov=100"
mainSourceFile "test.d"
`);
    std.file.write(pkg_path.buildPath("test.d"),
q{int f(int x)
{
	return x + 1;
}

int g(int x)
{
	return x * 2;
}

enum gResult = g(12);			// execute g() at compile-time

int main(string[] args)
{
	assert(f(11) + gResult == 36);
	return 0;
}
});

    // Run test
    auto res = dub.run(["--root", "cov-ctfe", "--build=cov-ctfe"]);
    assert(res.status == 0);
    assert(res.stdout.canFind("Running cov-ctfe/test"));
}
