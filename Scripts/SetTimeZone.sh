#!/bin/bash

# Set the timezone
systemsetup -settimezone America/New_York

# Set the timeservers
systemsetup -setnetworktimeserver time.apple.com

# Enables the Mac to set its clock using the network time server(s)
systemsetup -setusingnetworktime on

# The below command will list all available timezones
# systemsetup -listtimezones