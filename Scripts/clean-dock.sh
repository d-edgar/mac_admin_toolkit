#!/bin/bash
# macOS 26: set a minimal Dock for the currently logged-in user.
# Run as that user, or as root through your device-management tool after login.
set -euo pipefail

console_user=$(/usr/bin/stat -f '%Su' /dev/console)
case "$console_user" in
  root|loginwindow|_mbsetupuser|'')
    echo 'No regular user is logged in. Run this after the user reaches the desktop.' >&2
    exit 1
    ;;
esac
console_uid=$(/usr/bin/id -u "$console_user")

if [[ "$EUID" -ne 0 && "$EUID" -ne "$console_uid" ]]; then
  echo 'Run as the logged-in user or as root.' >&2
  exit 1
fi

as_user() {
  if [[ "$EUID" -eq 0 ]]; then
    /bin/launchctl asuser "$console_uid" /usr/bin/sudo -H -u "$console_user" "$@"
  else
    "$@"
  fi
}

# Finder is supplied automatically by the Dock; do not add a duplicate.
apps=(
  '/System/Applications/Apps.app'
  '/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app'
  '/System/Applications/Messages.app'
  '/System/Applications/Calendar.app'
  '/System/Applications/App Store.app'
  '/System/Applications/System Settings.app'
)

# Validate all paths before changing any preferences.
entries=()
for app in "${apps[@]}"; do
  if [[ ! -d "$app" ]]; then
    echo "Required app missing: $app. Dock was not changed." >&2
    exit 1
  fi
  # These fixed system paths only require URL-encoding spaces.
  app_url="file://${app// /%20}/"
  entries+=("<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$app_url</string><key>_CFURLStringType</key><integer>15</integer></dict></dict><key>tile-type</key><string>file-tile</string></dict>")
done

as_user /usr/bin/defaults write com.apple.dock persistent-apps -array "${entries[@]}"
# Preserve Downloads and other existing file/folder shortcuts. Trash is automatic.
as_user /usr/bin/defaults write com.apple.dock show-recents -bool false

# Reload only this user's Dock. It restarts automatically.
as_user /usr/bin/killall -u "$console_user" Dock || true
echo "Dock configured for $console_user."
