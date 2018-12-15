/+ dub.sdl:
+/

import std.exception;
import std.path;
import std.process;
import std.stdio;

void main(in string[] args)
{
    enforce(args.length > 1);
    const string msg = args[1];

    const path = buildPath(environment["DUB_PACKAGE_DIR"], "source", "app.d");
    auto file = File(path, "w");
    file.writeln(`import std.stdio;`);
    file.writeln();
    file.writeln(`void main() {`);
    file.writefln(`    writeln("%s");`, msg);
    file.writeln(`}`);
}
