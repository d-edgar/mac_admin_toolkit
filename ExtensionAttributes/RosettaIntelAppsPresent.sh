#!/bin/bash

# Extension Attribute: Rosetta (Intel) Apps Present
# Data Type: String
# Input Type: Script
#
# Reports whether any Intel-only (x86_64) applications are installed
# on the device. Designed for use in Smart Groups to quickly identify
# machines that still have Intel apps requiring Rosetta 2.
#
# Example output:
#   "Intel Apps Present"
#   "None"
#   "N/A - Intel Mac"

# Determine CPU architecture
arch=$(/usr/bin/arch)

if [[ "${arch}" != "arm64" ]]; then
    echo "<result>N/A - Intel Mac</result>"
    exit 0
fi

# Scan /Applications for any Intel-only binary
while IFS= read -r -d '' appBundle; do
    execName=$(/usr/bin/defaults read "${appBundle}/Contents/Info" CFBundleExecutable 2>/dev/null)
    if [[ -z "${execName}" ]]; then
        continue
    fi

    execPath="${appBundle}/Contents/MacOS/${execName}"
    if [[ ! -f "${execPath}" ]]; then
        continue
    fi

    archInfo=$(/usr/bin/lipo -archs "${execPath}" 2>/dev/null)
    if [[ -z "${archInfo}" ]]; then
        continue
    fi

    # Intel-only: contains x86_64 (or i386) but NOT arm64
    if echo "${archInfo}" | /usr/bin/grep -qE "(x86_64|i386)" && ! echo "${archInfo}" | /usr/bin/grep -q "arm64"; then
        echo "<result>Intel Apps Present</result>"
        exit 0
    fi
done < <(/usr/bin/find /Applications -maxdepth 3 -name "*.app" -print0 2>/dev/null)

echo "<result>None</result>"
exit 0
