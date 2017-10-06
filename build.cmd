@if "%DC%"=="" set DC=dmd

@echo Generating version file...
@set GITVER=unknown
@for /f %%i in ('git describe') do @set GITVER=%%i
@echo module dub.version_; > source\dub\version_.d
@echo enum dubVersion = "%GITVER%"; >> source\dub\version_.d

:: Find our source files.
@set res_file=.dub-sources-%RANDOM%.rsp
@dir /b /s source\*.d | sort > %res_file%

@echo Executing %DC%...
@%DC% -ofbin\dub.exe -g -debug -w -version=DubUseCurl -Isource curl.lib %* @%res_file%
@if errorlevel 1 exit /b 1
@bin\dub.exe --version
@del %res_file%

@echo DUB has been built. You probably also want to add the following entry to your
@echo PATH environment variable:
@echo %CD%\bin
