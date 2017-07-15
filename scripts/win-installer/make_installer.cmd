set GITVER=unknown
for /f %%i in ('git describe --tags') do set GITVER=%%i
"%ProgramFiles(x86)%\NSIS\makensis.exe" "/DVersion=%GITVER:~1%" installer.nsi
