@echo off
if "%DC%"=="" set DC=dmd

echo Executing %DC%...
%DC% -ofbin\dub.exe -g -debug -w -property -Isource curl.lib %* @build-files.txt
if errorlevel 1 exit /b 1

echo DUB has been built. You probably also want to add the following entry to your
echo PATH environment variable:
echo %CD%\bin