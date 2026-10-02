#!/bin/zsh
# Archive FreeVela and upload it to TestFlight with an App Store Connect API key.
# Needs ios/asc.env (gitignored) defining ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID.
# Bump CFBundleVersion in project.yml before each upload.
set -euo pipefail
cd "$(dirname "$0")"
source ./asc.env

out="${TMPDIR:-/tmp}/freevela-upload"
rm -rf "$out"
auth=(-allowProvisioningUpdates
      -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

xcodegen generate -q
xcodebuild -project FreeVela.xcodeproj -scheme FreeVela -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$out/FreeVela.xcarchive" \
  "${auth[@]}" archive | grep -E 'error:|ARCHIVE'
xcodebuild -exportArchive -archivePath "$out/FreeVela.xcarchive" \
  -exportOptionsPlist ExportOptions.plist -exportPath "$out/export" \
  "${auth[@]}" 2>&1 | grep -E 'rror|Upload succeeded|EXPORT'
