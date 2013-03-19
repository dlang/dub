@echo off

echo Executing rdmd ...
rdmd --force --build-only -ofbin\dub.exe -g -debug -w -property -Isource curl.lib %* source\app.d

echo dub has been build. You propably want to add this to your PATH environment variable:
echo %CD%\bin