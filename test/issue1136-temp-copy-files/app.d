/+ dub.sdl:

name "app"
dependency "mylib" path="./mylib"
+/

import std.exception: enforce;
import std.file: exists, thisExePath;
import std.path: dirName, buildPath;

void main()
{
    string filePath = buildPath(thisExePath.dirName, "helloworld.txt");
    enforce(filePath.exists);
}