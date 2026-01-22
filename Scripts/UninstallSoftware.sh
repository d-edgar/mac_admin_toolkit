#!/bin/bash

# This script can delete apps that are sandboxed and live in /Applications
# The first parameter is used to kill the app. It should be the app name or path
# as required by the pkill command.
applicationPath="$4"

if [[ -z "${applicationPath}" ]]; then
    echo "No application specified!"
    exit 1
fi

## Closing Application
echo "Closing application: ${applicationPath}"
pkill "${applicationPath}"

## Removing Application
echo "Removing application: ${applicationPath}"
rm -rf "/Applications/${applicationPath}.app"

exit 0