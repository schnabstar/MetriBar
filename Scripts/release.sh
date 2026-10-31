#!/bin/zsh
# Builds a Developer ID signed and notarized release of MetriBar into dist/.
# Publishing on GitHub is a separate step, see Docs/release.md.
#
# Usage: Scripts/release.sh <version>       for example 0.11.0
#
# Requirements: a "Developer ID Application" certificate in the keychain and
# notarization credentials stored with
#   xcrun notarytool store-credentials metribar --team-id <team ID>
# Override the profile name with NOTARY_PROFILE.

set -euo pipefail

version="${1:?Usage: Scripts/release.sh <version>}"
profile="${NOTARY_PROFILE:-metribar}"
root="${0:A:h:h}"
build="$root/build/release"
dist="$root/dist"
cd "$root"

marketing=$(xcodebuild -project MetriBar.xcodeproj -scheme MetriBar -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ MARKETING_VERSION = / { print $2; exit }')
if [[ "$version" != "$marketing"* ]]; then
  echo "Version $version does not match MARKETING_VERSION $marketing in project.yml" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "The working tree has uncommitted changes" >&2
  exit 1
fi

rm -rf "$build" && mkdir -p "$build" "$dist"

echo "==> Archiving"
xcodebuild archive -project MetriBar.xcodeproj -scheme MetriBar -configuration Release \
  -archivePath "$build/MetriBar.xcarchive" -allowProvisioningUpdates -quiet

echo "==> Exporting with Developer ID"
xcodebuild -exportArchive -archivePath "$build/MetriBar.xcarchive" -exportPath "$build/export" \
  -exportOptionsPlist Config/ExportOptions.plist -allowProvisioningUpdates -quiet
app="$build/export/MetriBar.app"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$app"
codesign -d --entitlements :- "$app" 2>/dev/null | plutil -p - | grep -q "get-task-allow" && {
  echo "Release build must not contain get-task-allow" >&2
  exit 1
}

echo "==> Notarizing the app"
ditto -c -k --keepParent "$app" "$build/MetriBar.zip"
xcrun notarytool submit "$build/MetriBar.zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"

echo "==> Building the disk image"
staging="$build/dmg"
mkdir -p "$staging"
ditto "$app" "$staging/MetriBar.app"
ln -s /Applications "$staging/Applications"
dmg="$dist/MetriBar-$version.dmg"
rm -f "$dmg"
hdiutil create -volname "MetriBar $version" -srcfolder "$staging" -format UDZO -ov "$dmg" -quiet
identity=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }')
codesign --sign "$identity" --timestamp "$dmg"

echo "==> Notarizing the disk image"
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"

echo "==> Gatekeeper assessment"
spctl --assess --type execute --verbose=2 "$app"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

ditto -c -k --keepParent "$app" "$dist/MetriBar-$version.zip"
(cd "$dist" && shasum -a 256 "MetriBar-$version.dmg" "MetriBar-$version.zip" > "MetriBar-$version.sha256")

echo "==> Done"
ls -l "$dist"
cat "$dist/MetriBar-$version.sha256"
