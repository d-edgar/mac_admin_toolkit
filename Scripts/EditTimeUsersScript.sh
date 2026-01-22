# Allows any user to change the date and time on their Mac.

security authorizationdb write system.preferences allow
/usr/bin/security authorizationdb write system.preferences.dateandtime.changetimezone allow
/usr/bin/security authorizationdb write system.preferences.datetime authenticate-session-owner-or-admin