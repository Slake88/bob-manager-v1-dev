$ErrorActionPreference = "Stop"
Push-Location "apps\mobile"
if (Test-Path "..\..\config\dev.json") {
 flutter run --dart-define-from-file=..\..\config\dev.json
} else {
 flutter run
}
Pop-Location
