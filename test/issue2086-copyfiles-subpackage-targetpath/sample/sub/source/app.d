import std.exception: enforce;
import std.file: exists, thisExePath;
import std.path: dirName, buildPath;

void main()
{
    string filePath = buildPath(thisExePath.dirName, "to_be_deployed.txt");
    enforce(filePath.exists);
}
