@echo off
set DUB_BIN=%~dps0
set DUB_SOURCE=%DUB_BIN%..\source
set VIBE_SOURCE=%DUB_BIN%..\..\vibe.d\source
set LIBDIR=%VIBE_SOURCE%\..\lib\win-i386
set BINDIR=%DUB_BIN%..\lib\bin
set LIBS="%LIBDIR%\event2.lib" "%LIBDIR%\eay.lib" "%LIBDIR%\ssl.lib" ws2_32.lib
set EXEDIR=%TEMP%\.rdmd\source
set START_SCRIPT=%EXEDIR%\vibe.cmd

if NOT EXIST %EXEDIR% (
	mkdir %EXEDIR%
)
copy "%DUB_BIN%*.dll" %EXEDIR% > nul 2>&1
if "%1" == "build" copy "%DUB_BIN%*.dll" . > nul 2>&1
copy "%DUB_SOURCE%\app.d" %EXEDIR% > nul 2>&1

rem Run, execute, do everything..
rdmd -debug -g -w -property -of%EXEDIR%\dub.exe -I%DUB_SOURCE% -I%VIBE_SOURCE% %LIBS% %EXEDIR%\app.d %VIBE_SOURCE% %START_SCRIPT% %*

rem Finally, start the app, if dub succeded.
if ERRORLEVEL 0 %START_SCRIPT%
