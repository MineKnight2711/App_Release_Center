# App Release Center

Desktop release automation console with an Android remote-control surface.

## Remote Control Flow

1. Deploy `serverless/notifications` behind HTTPS and configure
   `DESKTOP_API_TOKEN`.
2. In the Windows desktop app, set the serverless endpoint and desktop token in
   Notifications.
3. Enable Options > Remote Control > Phone command relay.
4. Use Pair control app to create a pairing code.
5. Install/run the Android app, enter the relay endpoint and pairing code, then
   run scripts, Fastlane lanes, or shell commands against allowed project roots.

Remote shell execution is constrained to recent project folders plus any roots
saved in Remote Control > Allowed roots.

## Firebase Auth and Teams

The Windows desktop app can use Firebase Auth and Cloud Firestore for team
login and shared HTTP Tools.

1. Create a Firebase project, enable Email/Password sign-in, and enable Cloud
   Firestore.
2. Copy `.env.example` to `.env` and fill the `FIREBASE_*` values.
3. Deploy `firestore.rules` to the same Firebase project.
4. Start the app. The first user can register and create a team as Admin.
5. Admin users can open the Team menu in the app header to create invite codes
   for Admin or Dev members.

HTTP Tool collections, folders, requests, and environments are shared per team.
HTTP response history stays local on each machine.

For Windows release/installer builds, `installer\windows\build_installer.ps1`
copies only the `FIREBASE_*` values from `.env` or process environment into a
generated `firebase.env` beside the installed executable. It deliberately does
not package the full `.env`, so secrets such as `GEMINI_API_KEY` are not bundled.
You can also compile Firebase config directly with `--dart-define` values.

## Telegram Release Notes

1. Create a bot with `@BotFather` by running `/newbot` and keep its token
   private.
2. Add the bot to the target Telegram group and allow it to send messages.
3. Send a command that mentions the bot in the group, such as
   `/start@your_bot_name`.
4. Open `https://api.telegram.org/bot<BOT_TOKEN>/getUpdates` and copy the
   group's `message.chat.id`. Supergroup IDs commonly start with `-100`.
5. In Options > AI Release Notes > Telegram, enter the bot token and chat ID,
   then select Save and Test.
6. Enable Auto send release updates. Generate a release note and verify the
   group receives the app name, full pubspec version, and notes.
7. Run Deploy and choose Upload for CH Play. After the AAB/CH Play command
   succeeds, the app builds a release APK, renames it as
   `<AppName>_v<VersionName>_<dd_MM_yyyy>.apk`, and sends it to the same group.

The APK remains under `build/app/outputs/flutter-apk` if Telegram auto send is
disabled or delivery fails. Telegram's hosted Bot API accepts documents up to
50 MB; larger APKs can be delivered through the Google Drive fallback below.

## Google Drive APK fallback

Use this only when you want APKs larger than Telegram's 50 MB Bot API document
limit to be uploaded to Drive and sent as a Telegram link.

1. In Google Cloud Console, enable Google Drive API for the project.
2. Configure the OAuth consent screen for the Google account that will upload
   release APKs.
3. Create an OAuth Client ID with application type Desktop app. Copy the
   Client ID. If Google also shows or downloads a Client Secret for that
   client, keep it private; some Google OAuth clients require it during the
   token exchange.
4. In Options > AI Release Notes > Telegram > Google Drive APK fallback, enter
   the OAuth Client ID. If Connect Drive previously failed with
   `client_secret is missing`, also enter the OAuth Client Secret, then select
   Save Drive.
5. Select Connect Drive, sign in with the browser, and allow the narrow
   `drive.file` scope.
6. Select Test Drive. The app creates or reuses a folder named
   `App Release Center APKs`.
7. Enable Use Drive for APKs over 50 MB. The switch is available only when the
   Telegram config is complete and Drive is connected.
8. To upload an APK to Drive without running a CH Play deploy, select
   Build/Upload APK. The app reuses the latest release APK in
   `build/app/outputs/flutter-apk` when one exists; otherwise it builds a new
   release APK first, renames it with the standard
   `<AppName>_v<VersionName>_<dd_MM_yyyy>.apk` format, uploads it to Drive, and
   shows the resulting link in the status/log.

Drive credentials are stored with the platform secure credential store. The app
does not log Google access tokens or refresh tokens. Uploaded APKs are shared as
Anyone with link / reader so the Telegram group can download them.

The bot token is stored with the platform secure credential store and must not
be committed or placed in project files. If it is exposed, revoke and replace
it through `@BotFather`.

The command progress bar in the application header covers standalone commands
and multi-step workflows such as Play image validation, deploy, release APK
build, and Telegram upload.

## Windows Installer

Build the release application and package it as one per-user installer EXE:

```powershell
flutter build windows --release
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File installer\windows\build_installer.ps1
```

The installer is written to `build\installer`. It installs the complete Flutter
runtime under `%LOCALAPPDATA%\Programs\App Release Center`, creates Desktop and
Start Menu shortcuts, and registers an uninstall entry without requiring
administrator permission.

To build and deliver the installer from the app, select this App Release Center
repo in the Project panel, configure Telegram, then use Options > Telegram >
Windows installer > Build/Send Installer. Installers up to Telegram's 50 MB Bot
API document limit are uploaded directly. Larger installers are uploaded with
the existing Google Drive connection and sent to Telegram as a Drive link.

## Checks

```powershell
flutter analyze
flutter test
flutter build windows --release
flutter build apk --debug
cd serverless\notifications
npm test -- --runInBand
npm run lint
```
