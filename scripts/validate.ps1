$ErrorActionPreference = "Stop"
Push-Location "apps\mobile"
flutter pub get
flutter analyze
flutter test
Pop-Location
