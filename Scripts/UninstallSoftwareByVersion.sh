#!/bin/bash

# This script can delete apps that are sandboxed and live in /Applications.
# It checks the installed version before uninstalling — only removes the app
# if the installed version matches the specified version.
#
# Jamf Parameters:
#   $4 - Application name (e.g. "Google Chrome") — used by pkill and to locate the .app bundle
#   $5 - Version number to match (e.g. "120.0.6099.129") — compared against CFBundleShortVersionString

applicationPath="$4"
targetVersion="$5"

if [[ -z "${applicationPath}" ]]; then
    echo "No application specified!"
    exit 1
fi

if [[ -z "${targetVersion}" ]]; then
    echo "No version number specified!"
    exit 1
fi

# Reject paths with directory traversal to prevent accidental deletion outside /Applications
if [[ "${applicationPath}" == *"/"* || "${applicationPath}" == *".."* ]]; then
    echo "Invalid application name: must be a plain app name, not a path."
    exit 1
fi

appBundle="/Applications/${applicationPath}.app"

# Verify the app exists
if [[ ! -d "${appBundle}" ]]; then
    echo "Application not found: ${appBundle}"
    exit 0
fi

# Read the installed version from the app's Info.plist
installedVersion=$(/usr/bin/defaults read "${appBundle}/Contents/Info" CFBundleShortVersionString 2>/dev/null)

if [[ -z "${installedVersion}" ]]; then
    echo "Could not determine installed version for ${applicationPath}."
    exit 1
fi

echo "Installed version: ${installedVersion}"
echo "Target version:    ${targetVersion}"

# Compare versions — only uninstall if they match
if [[ "${installedVersion}" != "${targetVersion}" ]]; then
    echo "Version mismatch. Installed version (${installedVersion}) does not match target (${targetVersion}). Skipping uninstall."
    exit 0
fi

echo "Version match confirmed. Proceeding with uninstall."

## Closing Application (non-fatal if app is not running)
echo "Closing application: ${applicationPath}"
pkill "${applicationPath}" || echo "Application not running, skipping kill."

## Removing Application
echo "Removing application: ${appBundle}"
rm -rf "${appBundle}"

echo "Successfully uninstalled ${applicationPath} version ${targetVersion}."
exit 0
