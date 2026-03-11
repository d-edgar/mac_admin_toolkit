#!/bin/bash

# Extension Attribute: Rosetta (Intel) Applications
# Data Type: String
# Input Type: Script
#
# Lists applications installed on the device that are Intel-only (x86_64)
# and therefore require Rosetta 2 to run on Apple Silicon Macs.
# Useful for tracking migration readiness to Apple Silicon.
#
# On Intel Macs, reports "N/A - Intel Mac" since Rosetta is not relevant.
#
# Example output:
#   "Microsoft Word 16.70, Google Chrome 120.0, Adobe Photoshop 24.1 (3 Intel apps)"
#   "None"
#   "N/A - Intel Mac"

# Determine CPU architecture
arch=$(/usr/bin/arch)

if [[ "${arch}" != "arm64" ]]; then
    echo "<result>N/A - Intel Mac</result>"
    exit 0
fi

# Find Intel-only apps in /Applications (including subdirectories)
intelApps=()

while IFS= read -r -d '' appBundle; do
    # Get the executable path from the Info.plist
    execName=$(/usr/bin/defaults read "${appBundle}/Contents/Info" CFBundleExecutable 2>/dev/null)
    if [[ -z "${execName}" ]]; then
        continue
    fi

    execPath="${appBundle}/Contents/MacOS/${execName}"
    if [[ ! -f "${execPath}" ]]; then
        continue
    fi

    # Check the architectures of the binary
    archInfo=$(/usr/bin/lipo -archs "${execPath}" 2>/dev/null)
    if [[ -z "${archInfo}" ]]; then
        continue
    fi

    # Intel-only: contains x86_64 (or i386) but NOT arm64
    if echo "${archInfo}" | /usr/bin/grep -qE "(x86_64|i386)" && ! echo "${archInfo}" | /usr/bin/grep -q "arm64"; then
        appName=$(/usr/bin/defaults read "${appBundle}/Contents/Info" CFBundleName 2>/dev/null)
        if [[ -z "${appName}" ]]; then
            # Fallback to the .app folder name
            appName=$(/usr/bin/basename "${appBundle}" .app)
        fi

        shortVersion=$(/usr/bin/defaults read "${appBundle}/Contents/Info" CFBundleShortVersionString 2>/dev/null)
        if [[ -n "${shortVersion}" ]]; then
            intelApps+=("${appName} ${shortVersion}")
        else
            intelApps+=("${appName}")
        fi
    fi
done < <(/usr/bin/find /Applications -maxdepth 3 -name "*.app" -print0 2>/dev/null)

appCount=${#intelApps[@]}

if [[ ${appCount} -eq 0 ]]; then
    echo "<result>None</result>"
    exit 0
fi

# Sort the list alphabetically
IFS=$'\n' sortedApps=($(sort <<<"${intelApps[*]}")); unset IFS

# Join into comma-separated string
appList=$(printf "%s, " "${sortedApps[@]}")
appList="${appList%, }"

echo "<result>${appList} (${appCount} Intel apps)</result>"
exit 0
