# macOS Admin Toolkit

A collection of **Jamf Pro Extension Attributes** and **shell scripts** for managing and monitoring macOS fleets. Includes purpose-built EAs for tracking **Microsoft Defender for Endpoint (MDE)** health, along with scripts for application management, user permissions, system configuration, LDAP-based user lookups, and more.

Use these to build **Smart Groups** and **Advanced Searches** in Jamf Pro that dynamically flag out-of-compliance Macs — whether that's network protection stopped, real-time protection disabled, outdated engine versions, or pending OS updates.

---

## Table of Contents

- [MDE Extension Attributes](#mde-extension-attributes)
  - [Why These Exist](#why-these-exist)
  - [EA Reference](#ea-reference)
  - [Usage in Jamf Pro](#usage-in-jamf-pro)
  - [Smart Group Examples](#smart-group-examples)
  - [Requirements](#requirements)
- [Scripts](#scripts)
  - [MDE Scripts](#mde-scripts)
  - [Application Management](#application-management)
  - [User Permissions](#user-permissions)
  - [User Account Management](#user-account-management)
  - [System Configuration](#system-configuration)
  - [Jamf Integration](#jamf-integration)
  - [LDAP & User Lookup](#ldap--user-lookup)
  - [Login Window](#login-window)
- [References](#references)
- [Contributing](#contributing)
- [License](#license)

---

## MDE Extension Attributes

### Why These Exist

When Microsoft Defender for Endpoint was first deployed to our Jamf-managed fleet, there were **no built-in Extension Attributes or reporting tools** available to track MDE health within Jamf Pro. These EAs were written from scratch to fill that gap, giving us visibility into Defender's operational status directly from the Jamf console.

All EAs live in the `ExtensionAttributes/` folder. Each script queries the [`mdatp`](https://learn.microsoft.com/microsoft-365/security/defender-endpoint/mac-install-manually) CLI tool and returns values inside `<result>…</result>` tags for Jamf Pro to consume.

### EA Reference

| Script | Jamf EA Name | Data Type | Returns |
|---|---|---|---|
| `mde_healthy.sh` | MDE: Healthy | String | `true`, `false`, `Not Installed`, `Unknown` |
| `mde_rtpenabled.sh` | MDE: RTP Enabled | String | `true`, `false`, `Not Installed`, `Unknown` |
| `mde_rtpavailable.sh` | MDE: RTP Available | String | `true`, `false`, `Not Installed`, `Unknown` |
| `mde_rtpsybsystem.sh` | MDE: RTP Subsystem | String | Subsystem name (e.g. `endpoint_security_extension`), `Not Installed`, `Unknown` |
| `MDE_NetworkProtectionStatus.sh` | MDE: Network Protection | String | `Status: [status] \| Enforcement: [level]`, `Not Installed` |
| `MDE_TamperProtectionStatus.sh` | MDE: Tamper Protection | String | `block`, `audit`, `disabled`, `Not Installed`, `Unknown` |
| `MDE_EDROnboarded.sh` | MDE: EDR Onboarded | String | `true`, `false`, `Not Installed`, `Unknown` |
| `MDE_EngineVersion.sh` | MDE: Engine Version | String | Version string (e.g. `1.1.25060.3000`), `Not Installed`, `Unknown` |
| `mde_appversion.sh` | MDE: App Version | String | Version string (e.g. `101.23.45.6`), `Not Installed`, `Unknown` |
| `mde_dlp_status.sh` | MDE: DLP Status | String | `enabled`, `disabled`, `unknown`, `Not Installed` |
| `mde_full_disk_access_status.sh` | MDE: Full Disk Access | String | `true`, `false`, `Not Installed`, `Unknown` |
| `mde_health_issues.sh` | MDE: Health Issues | String | `None` or JSON array of issues, `Not Installed`, `Unknown` |
| `macOSUpdateStatus.sh` | macOS Update Status | String | `Current: [ver] \| Available: [updates]` or `Current: [ver] \| Up to Date` |
| `JamfConnectLoginInstalled.sh` | Jamf Connect Login | String | `Installed`, `Not Installed` |

**Note on `JamfConnectLoginInstalled.sh`:** This checks specifically for **Jamf Connect Login** (the login window component), not Jamf Connect itself. Jamf Connect can be present on a machine without Jamf Connect Login being installed. The EA looks for the `JamfConnectLogin.bundle` under `/Library/Security/SecurityAgentPlugins/` and returns the version if found.

**Note on `MDE_EDROnboarded.sh`:** This script uses three fallback methods to detect onboarding status for compatibility across different MDE versions — it checks the `is_onboarded` field first, then falls back to checking for a non-empty `org_id`, and finally looks for "onboard" in the EDR details output.

**Note on `macOSUpdateStatus.sh`:** This EA is not MDE-specific but is included here for general fleet visibility. It uses a 120-second timeout on `softwareupdate` to prevent the EA from hanging during inventory collection.

### Usage in Jamf Pro

1. In **Jamf Pro → Settings → Computer Management → Extension Attributes**, create a new EA.
2. Paste the script into the "Script" section.
3. Set the **Data Type** to *String* for all EAs listed above.
4. Run `sudo jamf recon` on a test Mac to populate values and verify results appear in the computer record.

### Smart Group Examples

| Smart Group Purpose | EA | Criteria |
|---|---|---|
| Macs with network protection stopped | MDE: Network Protection | contains `stopped` |
| Macs with RTP disabled | MDE: RTP Enabled | equals `false` |
| Macs not onboarded to EDR | MDE: EDR Onboarded | equals `false` or `Unknown` |
| Macs without full disk access | MDE: Full Disk Access | equals `false` |
| Unhealthy MDE installations | MDE: Healthy | equals `false` |
| Macs with tamper protection off | MDE: Tamper Protection | equals `disabled` |
| Macs with pending OS updates | macOS Update Status | does not contain `Up to Date` |

### Requirements

- macOS with **Microsoft Defender for Endpoint** installed
- `mdatp` binary available at `/usr/local/bin/mdatp` (or in `$PATH`)
- Jamf Pro with permission to create and assign Extension Attributes

---

## Scripts

The scripts in the `Scripts/` folder are a collection of work developed, adapted, and refined for use with Jamf Pro. Some originated from community sources; the majority have been significantly modified to work properly in our environment.

### How Jamf Script Parameters Work

When you upload a script to **Jamf Pro → Settings → Computer Management → Scripts**, some scripts expect input values at runtime. Jamf reserves Parameters 1–3 internally (mount point, computer name, and username), so custom inputs start at **Parameter 4**.

To configure these in Jamf Pro:

1. Go to the script's **Options** tab.
2. Under **Parameter Labels**, enter a descriptive label for each parameter the script uses (e.g. `Application Name (Do not put .app)` for Parameter 4).
3. When you add the script to a **Policy**, Jamf will display those labels as text fields so the admin running the policy knows exactly what to fill in.

Scripts in this repo that require parameters are marked below with a **Jamf Parameter Labels** section showing exactly what to enter on the Options tab.

### MDE Scripts

#### mde_networkprotection_block.sh

Sets MDE network protection enforcement level to **block** mode and updates Jamf inventory afterward.

**Parameters:** None

**What it does:**

1. Runs `mdatp config network-protection enforcement-level --value block`
2. On success, runs `jamf recon` to sync the updated status to Jamf Pro
3. Exits with code 1 if either step fails

**Use case:** Deploy via Jamf policy to enforce network protection across your fleet, or scope to a Smart Group of machines where network protection is not currently set to block.

---

### Application Management

#### UninstallSoftware.sh

Safely removes an application from `/Applications` with input validation and path traversal protection.

**Parameters:**

- `$4` — Application name (e.g. `Google Chrome`)

**Jamf Parameter Labels (Options tab):**

| Parameter | Label |
|---|---|
| Parameter 4 | `Application Name (Do not put .app)` |

**What it does:**

1. Validates the parameter and rejects input containing `/` or `..` to prevent deletion outside `/Applications`
2. Checks that `/Applications/{name}.app` exists
3. Attempts to close the running app via `pkill`
4. Removes the app bundle and verifies deletion

**Exit codes:** 0 = success, 1 = invalid parameter, 2 = app not found, 3 = removal failed

---

#### UninstallSoftwareByVersion.sh

Removes an application **only if** its installed version matches a specified target version. Useful for removing a known-bad version while leaving newer versions intact.

**Parameters:**

- `$4` — Application name (e.g. `Google Chrome`)
- `$5` — Target version to match (e.g. `120.0.6099.129`)

**Jamf Parameter Labels (Options tab):**

| Parameter | Label |
|---|---|
| Parameter 4 | `Application Name (Do not put .app)` |
| Parameter 5 | `Target Version to Uninstall (e.g. 120.0.6099.129)` |

**What it does:**

1. Reads the installed version from `Info.plist` (`CFBundleShortVersionString`)
2. Compares it to the target version — only proceeds if they match exactly
3. Closes and removes the app, then verifies deletion

**Exit codes:** 0 = success, 1 = invalid parameter, 2 = app not found, 3 = can't read version, 4 = version mismatch, 5 = removal failed

---

#### ResetGoogleChromeScreenCapture.sh

Resets Chrome's screen capture TCC permissions. Addresses an issue introduced in Chrome v110 where screen capture prompts stopped appearing.

**Parameters:** None

**What it does:** Runs `tccutil reset ScreenCapture com.google.Chrome` to clear the permission entry so the user is re-prompted.

---

#### UninstallandInstallRemoteAssistantJamf.sh

Uninstalls the Jamf Remote Assist tool and reinstalls it from the local JamfDaemon package.

**Parameters:** None

**What it does:**

1. Removes `/Library/Application Support/JAMF/Remote Assist/`
2. Reinstalls from the JamfDaemon bundle using the macOS `installer` command

---

#### RemoveSelfServiceDockItem.sh

Removes the "Self Service" Dock item from all local user accounts. Created for upgrades where `Self Service.app` is being removed or relocated and the Dock shortcut would otherwise point to a missing app.

**Parameters:** None

**What it does:**

1. Enumerates all local user accounts (skips system/service accounts)
2. For each user, reads their Dock plist and searches `persistent-apps` for a "Self Service" entry using PlistBuddy
3. Removes the matching entry if found
4. If the user is currently logged in, restarts their Dock immediately so the change is visible right away; for other users, the change applies at their next login

**Dependencies:** None — uses only built-in macOS tools (`dscl`, `PlistBuddy`, `killall`).

---

### User Permissions

#### LocalAdminRights.sh

Grants **temporary admin rights** (15 minutes) to the currently logged-in user via Self Service, then automatically demotes them back to standard user.

**Parameters:** None

**What it does:**

1. Displays a usage policy warning dialog
2. Elevates the user to the admin group
3. Creates a LaunchDaemon that fires after 900 seconds to remove admin rights, collect system logs from the past 30 minutes, and clean up after itself

**Use case:** Deploy as a Self Service policy so users can temporarily elevate for tasks like installing printers or approved software without a permanent admin account.

---

#### AddUser_lpadmin.sh

Allows non-admin users to add and manage printers without requiring admin credentials.

**Parameters:** None

**What it does:** Modifies the macOS authorization database to allow printer operations and adds all users to the `lpadmin` and `_lpadmin` groups.

---

#### AllowUser_ModifyWiFi.sh

Allows non-admin users to modify WiFi network settings.

**Parameters:** None

**What it does:** Modifies the authorization database entries for `system.preferences.network` and `system.services.systemconfiguration.network` to allow non-admin access.

---

#### EditTimeUsersScript.sh

Allows non-admin users to change date, time, and timezone settings.

**Parameters:** None

**What it does:** Modifies authorization database entries for `system.preferences`, `system.preferences.dateandtime.changetimezone`, and `system.preferences.datetime`.

---

#### EditTimeMachineScript.sh

Allows non-admin users to access and configure Time Machine backup settings.

**Parameters:** None

**What it does:** Modifies authorization database entries for `system.preferences` and `system.preferences.timemachine`.

---

### User Account Management

#### jamf_delete_inactive_users.sh

Deletes local user accounts (and their home directories) that have been inactive for a configurable number of days. Supports two detection methods, custom exclusion lists, and a dry-run mode for safe testing.

**Parameters:**

- `$4` — **Days Threshold** *(Required)* — Number of inactive days before an account is deleted (e.g. `90`)
- `$5` — **Detection Method** *(Optional, default: `folder`)* — How to determine last activity:
  - `folder` — Uses the home folder's last modification date. Simple and reliable.
  - `login` — Parses actual console login records via the `last` command. Falls back to `folder` if no login record is found.
- `$6` — **Extra Exclusions** *(Optional)* — Comma-separated list of usernames to protect from deletion, in addition to the built-in exclusions (e.g. `labuser,kiosk,sharedacct`)
- `$7` — **Dry Run** *(Optional, default: `false`)* — Set to `true` to log what *would* be deleted without actually removing anything. Always run in dry-run mode first to verify targeting.

**Jamf Parameter Labels (Options tab):**

| Parameter | Label |
|---|---|
| Parameter 4 | `Days Inactive Before Deletion (e.g. 90)` |
| Parameter 5 | `Detection Method: folder (default) or login` |
| Parameter 6 | `Extra Excluded Users (comma-separated, optional)` |
| Parameter 7 | `Dry Run: true or false (default: false)` |

**Parameter Examples (copy-paste into Jamf policy fields):**

| Parameter | Example Value | What It Does |
|---|---|---|
| Parameter 4 | `90` | Deletes users inactive for 90+ days |
| Parameter 4 | `30` | More aggressive — deletes after 30 days of inactivity |
| Parameter 4 | `180` | Conservative — only deletes after 6 months |
| Parameter 5 | `folder` | Checks the home folder's last modification timestamp (default, works on all Macs) |
| Parameter 5 | `login` | Checks actual console login records via `last`; falls back to folder if no record found |
| Parameter 5 | *(leave blank)* | Defaults to `folder` |
| Parameter 6 | `labuser,kiosk` | Protects the `labuser` and `kiosk` accounts from deletion |
| Parameter 6 | `sharedacct` | Protects a single shared account |
| Parameter 6 | `trainee1,trainee2,labuser` | Protects multiple accounts — separate with commas, no spaces |
| Parameter 6 | *(leave blank)* | No extra exclusions beyond the built-in list |
| Parameter 7 | `true` | **Dry run** — logs everything that *would* be deleted but makes no changes. Always start here. |
| Parameter 7 | `false` | **Live mode** — actually deletes inactive accounts |
| Parameter 7 | *(leave blank)* | Defaults to `false` (live mode) |

**Common Jamf policy configurations:**

*Dry-run audit of 90-day inactive users on shared lab Macs:*

| Parameter | Value |
|---|---|
| Parameter 4 | `90` |
| Parameter 5 | `folder` |
| Parameter 6 | `labuser,kiosk` |
| Parameter 7 | `true` |

*Production cleanup — delete users inactive 90+ days, protect shared accounts:*

| Parameter | Value |
|---|---|
| Parameter 4 | `90` |
| Parameter 5 | `folder` |
| Parameter 6 | `labuser,kiosk` |
| Parameter 7 | `false` |

*Login-based detection for hotdesking environments:*

| Parameter | Value |
|---|---|
| Parameter 4 | `60` |
| Parameter 5 | `login` |
| Parameter 6 | *(leave blank)* |
| Parameter 7 | `true` |

**Built-in exclusions (always protected):** `root`, `administrator`, `Guest`, `Shared`, `_mbsetupuser`, `daemon`, `nobody`, and the currently logged-in console user.

**What it does:**

1. Validates the days threshold parameter and detection method
2. Builds a combined exclusion list from built-in accounts, the current console user, and any custom exclusions from `$6`
3. Enumerates all home directories under `/Users/` and checks each against Directory Services
4. For each non-excluded user, calculates inactive days using the chosen detection method
5. If the user exceeds the threshold, deletes the account via `sysadminctl -deleteUser` (with a `dscl` fallback) and removes the home directory
6. Logs all actions to `/var/log/jamf_user_cleanup.log` and prints a summary of deleted, skipped, and errored accounts

**Exit codes:** 0 = success (all targeted accounts cleaned up), 1 = one or more errors occurred or missing required parameter

**Recommended deployment:**

1. Upload the script to Jamf Pro and fill in the parameter labels above
2. Create a policy scoped to your target machines
3. Set Parameter 7 to `true` (dry run) and run against a test group first
4. Review `/var/log/jamf_user_cleanup.log` on the test machines to confirm correct targeting
5. Once verified, set Parameter 7 to `false` and deploy to production

---

### System Configuration

#### ChangeNameScript.sh

Renames the Mac using its serial number with a configurable prefix and updates Jamf inventory.

**Parameters:** None

**What it does:**

1. Reads the serial number from `system_profiler`
2. Sets `HostName`, `LocalHostName`, and `ComputerName` to `{Prefix}{SerialNumber}`
3. Runs `jamf recon` to sync the new name

**Customization:** Edit the prefix string in the script (currently `CNU`) to match your organization's naming convention.

---

#### SetAssetTagJamf.sh

Tags the current Mac as a loaner device in Jamf inventory.

**Parameters:** None

**What it does:** Runs `jamf recon` with `-assetTag "Loaner"` (skips app/font/plugin scans for speed). Modify the tag value as needed.

---

#### SetTimeZone.sh

Sets the system timezone and enables network time synchronization.

**Parameters:** None

**What it does:**

1. Sets timezone to `America/New_York`
2. Configures `time.apple.com` as the NTP server
3. Enables network time sync

**Customization:** Change the timezone string to match your location. The script includes a commented-out command to list all available timezones.

---

#### InstallRosettaIfNeeded.sh

Installs Rosetta 2 on Apple Silicon Macs if it's not already present.

**Parameters:** None

**What it does:**

1. Checks macOS version (requires 11+)
2. Detects processor type — skips if Intel
3. Checks for existing Rosetta installation via the `oahd` LaunchDaemon
4. If not installed, runs `softwareupdate --install-rosetta --agree-to-license`

---

#### WebLinkDesktopCreation.sh

Creates a Google Drive shortcut on the logged-in user's desktop.

**Parameters:** None

**What it does:** Creates a `.webloc` file at `~/Desktop/GoogleDrive.webloc` pointing to `https://drive.google.com/drive/home`. Modify the URL and filename to create shortcuts to other web destinations.

---

### Jamf Integration

#### CustomTriggerEvent4.sh

Triggers a Jamf custom event from within another policy, enabling policy chaining.

**Parameters:**

- `$4` — Custom event name to trigger (e.g. `install_printer`)

**Jamf Parameter Labels (Options tab):**

| Parameter | Label |
|---|---|
| Parameter 4 | `Custom Event Name (e.g. install_printer)` |

**What it does:** Runs `jamf policy -event {eventName}`. Useful for chaining policies together — for example, a prestage enrollment triggers a custom event that installs printers, which in turn triggers driver installation.

---

### LDAP & User Lookup

#### jamf_ldap_user_lookup.sh

> **Highlighted Script** — This is one of the more powerful utilities in the toolkit. If your environment uses **Jamf Connect** for authentication, you may have noticed that the User and Location fields in Jamf Pro inventory records are often empty or stale. Jamf Connect handles login but doesn't automatically populate department, email, phone, or position data in inventory. This script bridges that gap by leveraging the **Jamf Pro API's built-in LDAP integration** to look up the currently logged-in user, pull their directory attributes, and write them directly into the computer's inventory record — all without any additional infrastructure. Set it as a recurring policy at check-in and every Mac in your fleet stays up to date with accurate user data from your directory.

Automatically populates a computer's User and Location fields in Jamf Pro by performing an LDAP lookup for the currently logged-in user. Designed to run as a recurring policy at check-in so that department, email, phone, position, and real name stay current without manual entry.

**Parameters:**

- `$4` — Jamf Pro URL (e.g. `https://yourinstance.jamfcloud.com`)
- `$5` — API Client ID
- `$6` — API Client Secret
- `$7` — LDAP Server ID (default: `1`)
- `$8` — Email domain suffix for LDAP lookup (e.g. `@cnu.edu`). If your LDAP directory requires a full `user@domain` format instead of just the short macOS username, set this parameter and it will be appended automatically.

**Jamf Parameter Labels (Options tab):**

| Parameter | Label |
|---|---|
| Parameter 4 | `Jamf Pro URL (e.g. https://yourinstance.jamfcloud.com)` |
| Parameter 5 | `API Client ID` |
| Parameter 6 | `API Client Secret` |
| Parameter 7 | `LDAP Server ID (default: 1)` |
| Parameter 8 | `Email Domain Suffix (e.g. @cnu.edu, optional)` |

**Required API Client permissions:** Read Computers, Update Computers, Read LDAP Servers, Read Users. Create an API Role and API Client under Settings > API Roles and Clients.

**What it does:**

1. Authenticates to the Jamf Pro API using OAuth client credentials
2. Identifies the current console user and looks up the computer's Jamf Pro ID via serial number
3. If an email domain suffix is configured, appends it to the short username so the LDAP query uses the full `user@domain` format
4. Queries the LDAP server through the Classic API to retrieve the user's email, department, real name, phone, and position
5. Updates the computer's Location record in Jamf Pro with the LDAP data, using XML-escaped values to prevent injection from special characters
6. Invalidates the API token on exit via a cleanup trap (covers all exit paths including errors)

**Why this matters for Jamf Connect environments:** Jamf Connect handles authentication at the macOS login window but does not sync directory attributes into Jamf Pro inventory. This means fields like department, email, and position can remain blank indefinitely — making Smart Groups, scoping, and reporting based on user data unreliable. This script solves that by running at every check-in and keeping those fields current from your LDAP directory, with zero manual effort.

**Dependencies:** None beyond what ships with macOS — all JSON parsing uses `plutil` and `awk` (no Python or Xcode Command Line Tools required).

**Logging:** All activity is logged to `/var/log/jamf_ldap_lookup.log`. Sensitive PII (email, phone, etc.) is not written to the log — only success/failure status.

**Exit codes:** 0 = success or no user logged in, 1 = missing parameters, failed authentication, or failed lookup

---

### Login Window

#### remove_PolicyBanner.sh

Removes the macOS login window policy banner (`PolicyBanner.rtfd`) and forgets its package receipt.

**Parameters:** None

**What it does:**

1. Deletes `/Library/Security/PolicyBanner.rtfd` if it exists
2. Runs `pkgutil --forget policybanner.rtfd` to clear the installer receipt so macOS no longer tracks the package

**Use case:** Deploy via Jamf policy when decommissioning a login banner that was previously installed via a package. Handles cases where the banner or receipt has already been removed.

---

## References

- [Microsoft Docs – Defender for Endpoint on macOS](https://learn.microsoft.com/microsoft-365/security/defender-endpoint/mac-whatsnew)
- [Jamf Pro – Extension Attributes](https://learn.jamf.com/bundle/jamf-pro-documentation-current/page/Computer_Extension_Attributes.html)

---

## Contributing

Pull requests are welcome! If you'd like to add more fields, fix scripts, or extend functionality, please open an issue or submit a PR.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
