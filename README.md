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

## Checks

```powershell
flutter analyze
flutter test
flutter build apk --debug
cd serverless\notifications
npm test -- --runInBand
npm run lint
```
