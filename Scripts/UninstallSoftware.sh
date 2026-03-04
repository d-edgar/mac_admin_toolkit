#!/bin/bash

# This script can delete apps that are sandboxed and live in /Applications
# The first parameter is used to kill the app. It should be the app name or path
# as required by the pkill command.
#
# Exit Codes:
#   0 - Successfully uninstalled the application
#   1 - Invalid or missing parameter
#   2 - Application not found in /Applications
#   3 - Failed to remove the application

applicationPath="$4"

if [[ -z "${applicationPath}" ]]; then
    echo "No application specified!"
    exit 1
fi

# Reject paths with directory traversal to prevent accidental deletion outside /Applications
if [[ "${applicationPath}" == *"/"* || "${applicationPath}" == *".."* ]]; then
    echo "Invalid application name: must be a plain app name, not a path."
    exit 1
fi

appBundle="/Applications/${applicationPath}.app"

# Verify the app exists before attempting removal
if [[ ! -d "${appBundle}" ]]; then
    echo "Application not found: ${appBundle}"
    exit 2
fi

## Closing Application (non-fatal if app is not running)
echo "Closing application: ${applicationPath}"
pkill "${applicationPath}" || echo "Application not running, skipping kill."

## Removing Application
echo "Removing application: ${appBundle}"
rm -rf "${appBundle}"

# Verify removal was successful
if [[ -d "${appBundle}" ]]; then
    echo "Failed to remove ${appBundle}."
    exit 3
fi

echo "Successfully uninstalled ${applicationPath}."
exit 0
