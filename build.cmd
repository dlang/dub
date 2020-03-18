@if "%DC%"=="" set DC=dmd

@echo @@@@ WARNING @@@@@
@echo @ This script is DEPRECATED. Use build.d directly instead @
@echo @@@@@@@@@@@@@@@@@@
@%DC% -run build.d
@if errorlevel 1 exit /b 1

@echo DUB has been built. You probably also want to add the following entry to your
@echo PATH environment variable:
@echo %CD%\bin
