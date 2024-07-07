!include "MUI2.nsh"

!define MUI_ICON "assets/icons/logo.ico"
!insertmacro MUI_PAGE_DIRECTORY # In which folder install page.
!insertmacro MUI_PAGE_LICENSE "LICENSE.rtf"
!insertmacro MUI_PAGE_INSTFILES # Installing page.

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES


# define the name of the app
Name "Quadrant"

# define name of installer
OutFile "QuadrantSetup.exe"

# define installation directory
InstallDir "$PROGRAMFILES64\mrquantumoff.dev\quadrant"

# For removing Start Menu shortcut in Windows 7
RequestExecutionLevel admin

# start default section
Section
    Var /GLOBAL APP_REGISTRY_PATH

    StrCpy $APP_REGISTRY_PATH "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Quadrant"

    # set the installation directory as the destination for the following actions
    SetOutPath $INSTDIR

    # create the uninstaller
    WriteUninstaller "$INSTDIR\uninstall.exe"

    # point the new shortcut at the program uninstaller
    CreateShortcut "$SMPROGRAMS\Quadrant.lnk" "$INSTDIR\Release\quadrant.exe"
    CreateShortcut "$SMPROGRAMS\Uninstall Quadrant.lnk" "$INSTDIR\uninstall.exe"

    # Create a shortcut in the Startup folder with arguments
    CreateShortcut "$SMSTARTUP\Quadrant (not from microsoft store).lnk" "$INSTDIR\Release\quadrant.exe" "autostart"


    File /r "build\windows\x64\runner\Release"
    File "assets\icons\logo.ico"

    WriteRegStr HKLM "$APP_REGISTRY_PATH" "Publisher" "MrQuantumOFF (Demir Yerli)"
    WriteRegStr HKLM "$APP_REGISTRY_PATH" "UninstallString" "$INSTDIR\uninstall.exe"
    WriteRegStr HKLM "$APP_REGISTRY_PATH" "URLInfoAbout" "https://github.com/mrquantumoff/quadrant"
    WriteRegStr HKLM "$APP_REGISTRY_PATH" "InstallLocation" "$INSTDIR"
    WriteRegStr HKLM "$APP_REGISTRY_PATH" "DisplayName" "Quadrant"
    WriteRegStr HKLM "$APP_REGISTRY_PATH" "DisplayIcon" "$INSTDIR\logo.ico"
    WriteRegDWORD HKLM "$APP_REGISTRY_PATH" "NoModify" "1"
    WriteRegDWORD HKLM "$APP_REGISTRY_PATH" "NoRepair" "1"






SectionEnd

# uninstaller section start
Section "uninstall"
    StrCpy $APP_REGISTRY_PATH "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Quadrant"

    # first, delete the uninstaller
    Delete "$INSTDIR\uninstall.exe"

    # second, remove the link from the start menu
    Delete "$SMPROGRAMS\Quadrant.lnk"
    Delete "$SMPROGRAMS\Uninstall Quadrant.lnk"
    # Remove the shortcut from the Startup folder
    Delete "$SMSTARTUP\Quadrant (not from microsoft store).lnk"
    DeleteRegValue HKLM "$APP_REGISTRY_PATH" "Publisher"
    DeleteRegValue HKLM "$APP_REGISTRY_PATH" "UninstallString"
    DeleteRegValue HKLM "$APP_REGISTRY_PATH" "URLInfoAbout"
    DeleteRegValue HKLM "$APP_REGISTRY_PATH" "InstallLocation"
    DeleteRegValue HKLM "$APP_REGISTRY_PATH" "DisplayName"
    DeleteRegValue HKLM "$APP_REGISTRY_PATH" "DisplayIcon"
    DeleteRegValue HKLM "$APP_REGISTRY_PATH" "NoModify"
    DeleteRegValue HKLM "$APP_REGISTRY_PATH" "NoRepair"
    DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "Quadrant (Manual install)"
    DeleteRegKey HKLM "$APP_REGISTRY_PATH"
    Delete "$INSTDIR\*"
    RMDir /r "$INSTDIR"


# uninstaller section end
SectionEnd