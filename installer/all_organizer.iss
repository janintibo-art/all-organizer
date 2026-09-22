; Installateur Windows d'All Organizer, compilé par Inno Setup 6 dans le
; workflow GitHub. La version arrive de la ligne de commande :
;   ISCC /DAppVersion=1.42.0 installer\all_organizer.iss
; Les chemins sont relatifs à ce fichier, d'où les « ..\ ».

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName "All Organizer"
#define AppExe "all_organizer.exe"
#define AppRepo "https://github.com/janintibo-art/all-organizer"

[Setup]
; Identifiant fixe : c'est lui qui permet à une nouvelle version de
; remplacer l'ancienne au même endroit au lieu de s'installer à côté.
; Ne jamais le changer.
AppId={{14CC2D94-714A-4A44-863C-9E2EB3ED75DC}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=janintibo-art
AppPublisherURL={#AppRepo}
AppSupportURL={#AppRepo}/issues
AppUpdatesURL={#AppRepo}/actions

; Installation pour soi seul par défaut, sans droits administrateur ;
; l'assistant propose aussi « pour tous les utilisateurs ». {autopf} vaut
; alors Program Files, ou le dossier Programmes de l'utilisateur.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

OutputDir=..\dist
OutputBaseFilename=AllOrganizer-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}

Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

; L'application peut tourner en tâche de fond, serveur compris : on la
; ferme proprement avant de remplacer ses fichiers.
CloseApplications=yes
RestartApplications=no

; Le nettoyage du démarrage automatique touche le dossier Démarrage de
; l'utilisateur, même lors d'une installation pour tous : c'est voulu.
UsedUserAreasWarning=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Tout le dossier Release : l'exécutable, les DLL de Flutter et de
; media_kit, le dossier data, et les trois DLL Visual C++ que le workflow
; y a copiées — sans elles l'application ne démarre pas sur un PC neuf.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Le démarrage automatique réglé dans l'application survivrait sinon à la
; désinstallation, et Windows tenterait de lancer un fichier disparu à
; chaque démarrage. La tâche planifiée exige les droits administrateur :
; sans eux, cette ligne échoue en silence et n'empêche rien.
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /F /TN MediaOrganizerServeur"; Flags: runhidden; RunOnceId: "SupprimerTacheDemarrage"

[UninstallDelete]
Type: files; Name: "{userstartup}\MediaOrganizer.bat"

; La bibliothèque, les réglages et les téléchargements vivent dans le
; dossier de données de l'utilisateur, pas ici : ils sont conservés, et
; une réinstallation les retrouve.
