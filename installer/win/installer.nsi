;--------------------------------------------------------
; Defines
;--------------------------------------------------------

; Options
!define Version "0.9.8"
!define DubExecPath "..\..\dub.exe"

;--------------------------------------------------------
; Includes
;--------------------------------------------------------

!include "MUI.nsh"
!include "EnvVarUpdate.nsh"

;--------------------------------------------------------
; General definitions
;--------------------------------------------------------

; Name of the installer
Name "dub Package Manager ${Version}"

; Name of the output file of the installer
OutFile "dub-install-${Version}.exe"

; Where the program will be installed
InstallDir "$PROGRAMFILES\dub"

; Take the installation directory from the registry, if possible
InstallDirRegKey HKLM "Software\dub" ""

; Prevent installation of a corrupt installer
CRCCheck force

RequestExecutionLevel admin

;--------------------------------------------------------
; Interface settings
;--------------------------------------------------------

;!define MUI_ICON "installer-icon.ico"
;!define MUI_UNICON "uninstaller-icon.ico"

;--------------------------------------------------------
; Installer pages
;--------------------------------------------------------

;!define MUI_WELCOMEFINISHPAGE_BITMAP "installer_image.bmp"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

;--------------------------------------------------------
; The languages
;--------------------------------------------------------

!insertmacro MUI_LANGUAGE "English"


;--------------------------------------------------------
; Required section: main program files,
; registry entries, etc.
;--------------------------------------------------------
;
Section "dub" DubFiles

    ; This section is mandatory
    SectionIn RO
    
    SetOutPath $INSTDIR
    
    ; Create installation directory
    CreateDirectory "$INSTDIR"
    
	File "${DubExecPath}"
    
    ; Create command line batch file
    FileOpen $0 "$INSTDIR\dubvars.bat" w
    FileWrite $0 "@echo.$\n"
    FileWrite $0 "@echo Setting up environment for using dub from %~dp0$\n"
    FileWrite $0 "@set PATH=%~dp0;%PATH%$\n"
    FileClose $0

    ; Write installation dir in the registry
    WriteRegStr HKLM SOFTWARE\dub "Install_Dir" "$INSTDIR"

    ; Write registry keys to make uninstall from Windows
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\dub" "DisplayName" "dub"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\dub" "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\dub" "NoModify" 1
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\dub" "NoRepair" 1
    WriteUninstaller "uninstall.exe"

SectionEnd

Section "Add to PATH" AddDubToPath

    ; Add dub directory to path (for all users)
	${EnvVarUpdate} $0 "PATH" "A" "HKLM" "$INSTDIR"

SectionEnd

Section /o "Start Menu shortcuts" StartMenuShortcuts
    CreateDirectory "$SMPROGRAMS\dub"

    ; install dub command prompt
	CreateShortCut "$SMPROGRAMS\dub\dub Command Prompt.lnk" '%comspec%' '/k ""$INSTDIR\dubvars.bat""' "" "" SW_SHOWNORMAL "" "Open dub Command Prompt"

    CreateShortCut "$SMPROGRAMS\dub\Uninstall.lnk" "$INSTDIR\uninstall.exe" "" "$INSTDIR\uninstall.exe" 0
SectionEnd

;--------------------------------------------------------
; Uninstaller
;--------------------------------------------------------

Section "Uninstall"

    ; Remove directories to path (for all users)
    ; (if for the current user, use HKCU)
    ${un.EnvVarUpdate} $0 "PATH" "R" "HKLM" "$INSTDIR"

    ; Remove stuff from registry
    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\dub"
    DeleteRegKey HKLM SOFTWARE\dub
    DeleteRegKey /ifempty HKLM SOFTWARE\dub

    ; This is for deleting the remembered language of the installation
    DeleteRegKey HKCU Software\dub
    DeleteRegKey /ifempty HKCU Software\dub

    ; Remove the uninstaller
    Delete $INSTDIR\uninstall.exe
    
    ; Remove shortcuts
    Delete "$SMPROGRAMS\dub\dub Command Prompt.lnk"

    ; Remove used directories
    RMDir /r /REBOOTOK "$INSTDIR"
    RMDir /r /REBOOTOK "$SMPROGRAMS\dub"

SectionEnd

