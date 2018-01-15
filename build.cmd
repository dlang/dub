@if "%DMD%"=="" set DMD="%DC%"
@if "%DMD%"=="" set DMD=dmd

@echo Generating version file...
@set GITVER=unknown
@for /f %%i in ('git describe') do @set GITVER=%%i
@echo module dub.version_; > source\dub\version_.d
@echo enum dubVersion = "%GITVER%"; >> source\dub\version_.d

@echo Executing %DMD%...
@%DMD% -ofbin\dub.exe -g -debug -w -version=DubUseCurl -Isource curl.lib %* @build-files.txt
@if errorlevel 1 exit /b 1

@echo DUB has been built. You probably also want to add the following entry to your
@echo PATH environment variable:
@echo %CD%\bin
