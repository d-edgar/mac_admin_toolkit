#!/bin/bash

# Removes the "Self Service" Dock item from all user accounts.
# Uses PlistBuddy to edit each user's Dock plist directly — no external dependencies.
# Designed to run as a Jamf policy before or after an upgrade where Self Service.app
# is being removed or relocated.

appLabel="Self Service"

# Get list of user home directories (skip system/service accounts)
userList=$(/usr/bin/dscl . -list /Users NFSHomeDirectory | awk '$2 ~ /^\/Users\// {print $1}')

if [[ -z "${userList}" ]]; then
    echo "No local user accounts found."
    exit 0
fi

for userName in ${userList}; do
    userHome=$(/usr/bin/dscl . -read "/Users/${userName}" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    dockPlist="${userHome}/Library/Preferences/com.apple.dock.plist"

    if [[ ! -f "${dockPlist}" ]]; then
        echo "No Dock plist found for ${userName}, skipping."
        continue
    fi

    # Search persistent-apps for the Self Service entry
    itemRemoved=false
    index=0

    while true; do
        entry=$(/usr/libexec/PlistBuddy -c "Print persistent-apps:${index}:tile-data:file-label" "${dockPlist}" 2>/dev/null)
        exitCode=$?

        # Break when we've gone past the last entry
        if [[ ${exitCode} -ne 0 ]]; then
            break
        fi

        if [[ "${entry}" == "${appLabel}" ]]; then
            echo "Removing '${appLabel}' from Dock for user: ${userName} (index ${index})"
            /usr/libexec/PlistBuddy -c "Delete persistent-apps:${index}" "${dockPlist}"
            itemRemoved=true
            # Don't increment index since array shifted down
            continue
        fi

        ((index++))
    done

    if [[ "${itemRemoved}" == true ]]; then
        # If this is the currently logged-in user, restart their Dock to apply immediately
        currentUser=$(scutil --get ConsoleUser 2>/dev/null)
        if [[ "${userName}" == "${currentUser}" ]]; then
            echo "Restarting Dock for logged-in user: ${userName}"
            sudo -u "${userName}" killall Dock 2>/dev/null
        else
            echo "Dock updated for ${userName}. Changes will apply at next login."
        fi
    else
        echo "No '${appLabel}' Dock item found for ${userName}."
    fi
done

echo "Dock cleanup complete."
exit 0
