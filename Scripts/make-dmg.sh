#!/bin/zsh
# Builds the MetriBar disk image: a 660 × 400 pt window with a Liquid Glass style
# background, the app on the left and the Applications shortcut on the right.
#
# Usage: Scripts/make-dmg.sh <MetriBar.app> <output.dmg>
#
# Finder lays out the window, so this needs a logged-in macOS session. On the first
# run macOS asks whether the terminal may control Finder.
# The background comes from Scripts/make-dmg-background.swift; the icon positions
# below must match the constants there.

set -euo pipefail

app="${1:?Usage: Scripts/make-dmg.sh <MetriBar.app> <output.dmg>}"
dmg="${2:?Usage: Scripts/make-dmg.sh <MetriBar.app> <output.dmg>}"
root="${0:A:h:h}"
volume="MetriBar"
mount="/Volumes/$volume"

# Window content size in points and the centers of the two icons.
width=660 height=400
app_x=180 app_y=190
applications_x=480 applications_y=190
icon_size=128
# Finder's window bounds include the title bar (32 pt on macOS 26).
titlebar=32

work=$(mktemp -d)
trap 'hdiutil detach "$mount" -force -quiet 2>/dev/null || true; rm -rf "$work"' EXIT

if [[ -d "$mount" ]]; then
  hdiutil detach "$mount" -force -quiet
fi

staging="$work/staging"
mkdir -p "$staging/.background"
ditto "$app" "$staging/MetriBar.app"
ln -s /Applications "$staging/Applications"
cp "$root/Resources/DiskImage/background.tiff" "$staging/.background/background.tiff"

# The volume icon shows in the Finder sidebar, the Desktop and Get Info.
iconset="$work/AppIcon.iconset"
cp -R "$root/Resources/Assets.xcassets/AppIcon.appiconset" "$iconset"
rm -f "$iconset/Contents.json"
iconutil -c icns "$iconset" -o "$work/VolumeIcon.icns"

rw="$work/rw.dmg"
hdiutil create -volname "$volume" -srcfolder "$staging" -fs HFS+ -format UDRW -ov "$rw" -quiet
hdiutil attach "$rw" -readwrite -noverify -noautoopen -mountpoint "$mount" -quiet
osascript <<EOF
tell application "Finder"
  tell disk "$volume"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set the bounds of container window to {200, 120, $((200 + width)), $((120 + height + titlebar))}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to $icon_size
    set text size of viewOptions to 13
    set label position of viewOptions to bottom
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "MetriBar.app" of container window to {$app_x, $app_y}
    set position of item "Applications" of container window to {$applications_x, $applications_y}
    update without registering applications
    delay 2
    close
  end tell
end tell
EOF

# Finder writes .DS_Store a moment after the window closes.
for _ in {1..20}; do
  [[ -f "$mount/.DS_Store" ]] && break
  sleep 0.5
done
[[ -f "$mount/.DS_Store" ]] || { echo "Finder did not save the window layout" >&2; exit 1; }
# Finder drops the volume icon while it lays out the window, so it is added afterwards.
cp "$work/VolumeIcon.icns" "$mount/.VolumeIcon.icns"
SetFile -a C "$mount"
sync
chmod -Rf go-w "$mount" || true
hdiutil detach "$mount" -quiet

rm -f "$dmg"
hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -o "$dmg" -quiet
echo "Wrote $dmg"
