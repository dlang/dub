@echo off

echo Executing rdmd ...
rdmd --force --build-only -ofbin\dub.exe -g -debug -w -property -Isource curl.lib %* source\app.d

echo DUB has been built. You probably also want to add the following entry to your
echo PATH environment variable:
echo %CD%\bin