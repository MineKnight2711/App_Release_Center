# Runs the QA Desk vault rules tests on the Firestore emulator, port 8095.
# Needs the Firebase CLI and Java; touches no real Firebase project.
#   powershell -ExecutionPolicy Bypass -File test\firestore\run_rules_test.ps1
$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot\..\.."
$work = Join-Path ([IO.Path]::GetTempPath()) 'amc-firestore-rules-test'
New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item "$root\firestore.rules" $work -Force
Copy-Item "$PSScriptRoot\qa_vault_rules_test.mjs" $work -Force
$config = '{"firestore":{"rules":"firestore.rules"},' +
  '"emulators":{"firestore":{"host":"127.0.0.1","port":8095},"ui":{"enabled":false}}}'
[IO.File]::WriteAllText("$work\firebase.json", $config)
Push-Location $work
try {
  firebase emulators:exec --only firestore --project demo-amc-rules `
    "node --test qa_vault_rules_test.mjs"
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Pop-Location
}
