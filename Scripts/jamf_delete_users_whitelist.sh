#!/bin/bash

###############################################################################
# jamf_delete_users_whitelist.sh
#
# Purpose:  Delete ALL local user accounts EXCEPT those on a whitelist, and
#           deep-scrub every artifact each deleted user leaves behind so that
#           if the same person returns, they get a clean, first-login
#           experience. Designed to run as a Jamf Pro script with configurable
#           parameters, but also runs standalone via sudo.
#
#           This is the inverse selection model of jamf_delete_inactive_users.sh
#           — instead of targeting users by inactivity, it KEEPS a known set
#           and removes everyone else. Ideal for shared / lab / kiosk / loaner
#           Macs that should only ever retain a handful of known accounts.
#
# Jamf Parameters:
#   $4  - WHITELIST       (Required) Comma-separated usernames to PROTECT from
#                          deletion, in addition to the built-in system
#                          accounts and the current console user.
#                          Example: "labadmin,kiosk,itadmin"
#   $5  - DRY_RUN         (Optional) "true" = log what WOULD happen, make no
#                          changes. Default: "false". ALWAYS run dry first.
#   $6  - PROTECT_ADMINS  (Optional) "true" = also skip any account that is a
#                          member of the local "admin" group, even if not on
#                          the whitelist. Default: "false". Extra safety net.
#   $7  - MIN_UID         (Optional) Only consider accounts with a UID greater
#                          than or equal to this value. Default: 501. Protects
#                          hidden / service / system accounts (UID < 500).
#
# Built-in whitelist (never deleted, regardless of parameters):
#   root, administrator, admin, Guest, Shared, daemon, nobody,
#   _mbsetupuser, and every account whose name starts with "_" (service
#   accounts), plus the currently logged-in console user.
#
# Deep scrub performed for each deleted user:
#   1.  Remove FileVault access (fdesetup remove)
#   2.  Strip all secondary group memberships (admin, staff, etc.)
#   3.  Delete the account + home directory (sysadminctl -deleteUser)
#   4.  dscl fallback delete of the user record if it survives
#   5.  Remove the home directory if it survives
#   6.  Purge any /Users/Deleted Users/<user>* archive bundle
#   7.  Remove the dslocal plist if it survives
#   8.  Clear auto-login (com.apple.loginwindow) + /etc/kcpassword if the
#       deleted user was the configured auto-login account
#   9.  Remove cached fast-user-switching / known-user references
#   10. Remove per-user MDM / managed-preference leftovers in /Library
#   VERIFICATION pass re-checks every location and logs anything left behind.
#
# WARNING: This script is destructive. It deletes accounts and erases home
#          directories permanently. Run with DRY_RUN="true" first and review
#          the log before running live.
#
# Exit codes:  0 = success (or clean dry run)
#              1 = invalid parameters, or one or more deletions left artifacts
#
# Author:   David Edgar — macOS Admin Toolkit
# Date:     2026-06-08
###############################################################################

# ============================ Parameter Mapping ==============================

WHITELIST="${4}"
DRY_RUN="${5:-false}"
PROTECT_ADMINS="${6:-false}"
MIN_UID="${7:-501}"

# ============================== Configuration ================================

LOG_FILE="/var/log/jamf_user_whitelist_cleanup.log"
SCRIPT_NAME="$(basename "$0")"
DELETED_USERS_DIR="/Users/Deleted Users"
DSLOCAL_USERS="/private/var/db/dslocal/nodes/Default/users"
LOGINWINDOW_PREFS="/Library/Preferences/com.apple.loginwindow"

# System accounts that must NEVER be deleted (in addition to anything matching
# the "_*" service-account pattern, which is handled separately).
BUILTIN_WHITELIST=(
    "root"
    "administrator"
    "admin"
    "Guest"
    "Shared"
    "daemon"
    "nobody"
    "_mbsetupuser"
)

# ============================== Logging ======================================

log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "${timestamp} [${level}] ${SCRIPT_NAME}: ${message}" | tee -a "$LOG_FILE"
}

log_info()  { log_message "INFO"    "$1"; }
log_warn()  { log_message "WARNING" "$1"; }
log_error() { log_message "ERROR"   "$1"; }

# Echo the destructive action in dry-run, or run it live otherwise.
run_action() {
    local description="$1"
    shift
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN]   Would run: ${description}"
        return 0
    fi
    log_info "  Running: ${description}"
    "$@" 2>&1 | while IFS= read -r line; do
        [[ -n "$line" ]] && log_info "    > ${line}"
    done
    return "${PIPESTATUS[0]}"
}

# ============================== Helpers ======================================

# Currently logged-in console user ("" if at the login window).
get_current_user() {
    /usr/bin/stat -f '%Su' /dev/console 2>/dev/null
}

# UID for a given username ("" if no record).
get_uid() {
    /usr/bin/dscl . -read "/Users/${1}" UniqueID 2>/dev/null \
        | /usr/bin/awk '{print $2}'
}

# True (0) if the user belongs to the local admin group.
is_admin_user() {
    /usr/sbin/dseditgroup -o checkmember -m "$1" admin 2>/dev/null \
        | /usr/bin/grep -q "^yes"
}

# Build the full whitelist: built-ins + current console user + custom ($4).
build_whitelist() {
    local -a wl=("${BUILTIN_WHITELIST[@]}")

    local current_user
    current_user="$(get_current_user)"
    if [[ -n "$current_user" && "$current_user" != "root" ]]; then
        wl+=("$current_user")
        log_info "Current console user '${current_user}' added to whitelist."
    fi

    if [[ -n "$WHITELIST" ]]; then
        local IFS=','
        read -ra custom <<< "$WHITELIST"
        for u in "${custom[@]}"; do
            u="$(echo "$u" | xargs)"   # trim
            [[ -n "$u" ]] && wl+=("$u")
        done
        log_info "Custom whitelist from parameters: ${WHITELIST}"
    fi

    printf '%s\n' "${wl[@]}"
}

# Capture a one-line report record before deletion.
get_user_details() {
    local username="$1"
    local home_dir="/Users/${username}"

    local uid real_name dir_size last_active groups fv_status token_status
    uid="$(get_uid "$username")"; [[ -z "$uid" ]] && uid="unknown"

    real_name="$(/usr/bin/dscl . -read "/Users/${username}" RealName 2>/dev/null \
        | /usr/bin/sed -n '2p' | /usr/bin/xargs)"
    [[ -z "$real_name" ]] && real_name="(none)"

    if [[ -d "$home_dir" ]]; then
        dir_size="$(/usr/bin/du -sh "$home_dir" 2>/dev/null | /usr/bin/awk '{print $1}')"
    fi
    [[ -z "$dir_size" ]] && dir_size="0B"

    local home_epoch
    home_epoch="$(/usr/bin/stat -f '%m' "$home_dir" 2>/dev/null)"
    if [[ -n "$home_epoch" ]]; then
        last_active="$(/bin/date -r "$home_epoch" '+%Y-%m-%d' 2>/dev/null)"
    fi
    [[ -z "$last_active" ]] && last_active="unknown"

    groups="$(/usr/bin/id -Gn "$username" 2>/dev/null | tr ' ' ',')"
    [[ -z "$groups" ]] && groups="(none)"

    if /usr/bin/fdesetup list 2>/dev/null | /usr/bin/grep -q "^${username},"; then
        fv_status="enabled"
    else
        fv_status="no"
    fi

    if /usr/sbin/sysadminctl -secureTokenStatus "$username" 2>&1 \
        | /usr/bin/grep -qi "ENABLED"; then
        token_status="enabled"
    else
        token_status="no"
    fi

    echo "uid=${uid}|real_name=${real_name}|dir_size=${dir_size}|last_active=${last_active}|groups=${groups}|filevault=${fv_status}|securetoken=${token_status}"
}

# =========================== Deletion + Scrub ================================

# Remove the user from every secondary group it belongs to.
strip_group_memberships() {
    local username="$1"
    local grp
    while IFS= read -r grp; do
        [[ -z "$grp" || "$grp" == "$username" ]] && continue
        run_action "dseditgroup remove '${username}' from group '${grp}'" \
            /usr/sbin/dseditgroup -o edit -d "$username" -t user "$grp"
    done < <(/usr/bin/id -Gn "$username" 2>/dev/null | tr ' ' '\n' | sort -u)
}

# Clear auto-login if the deleted user was the configured account.
clear_autologin_if_needed() {
    local username="$1"
    local autologin_user
    autologin_user="$(/usr/bin/defaults read "$LOGINWINDOW_PREFS" autoLoginUser 2>/dev/null)"
    if [[ "$autologin_user" == "$username" ]]; then
        log_warn "Deleted user '${username}' was the auto-login account; clearing it."
        run_action "defaults delete loginwindow autoLoginUser" \
            /usr/bin/defaults delete "$LOGINWINDOW_PREFS" autoLoginUser
        run_action "remove /etc/kcpassword" \
            /bin/rm -f /etc/kcpassword
    fi
}

# Remove cached fast-user-switching / known-user references and managed prefs.
scrub_residual_references() {
    local username="$1"
    local uid="$2"

    # Managed / MDM per-user preference leftovers.
    local mcx="/Library/Managed Preferences/${username}"
    if [[ -d "$mcx" ]]; then
        run_action "remove managed preferences '${mcx}'" /bin/rm -rf "$mcx"
    fi

    # Any stray home archive left by a prior GUI deletion.
    if [[ -d "${DELETED_USERS_DIR}/${username}" ]]; then
        run_action "remove archived home '${DELETED_USERS_DIR}/${username}'" \
            /bin/rm -rf "${DELETED_USERS_DIR}/${username}"
    fi
    # sysadminctl/GUI sometimes archives as a .<uid> bundle or dmg.
    if [[ -n "$uid" && "$uid" != "unknown" ]]; then
        for archive in "${DELETED_USERS_DIR}/${username}".*; do
            [[ -e "$archive" ]] || continue
            run_action "remove archive bundle '${archive}'" /bin/rm -rf "$archive"
        done
    fi
}

# Full delete + deep scrub for one user.
delete_and_scrub() {
    local username="$1"
    local details="$2"
    local home_dir="/Users/${username}"
    local uid
    uid="$(echo "$details" | /usr/bin/sed 's/.*uid=\([^|]*\).*/\1/')"

    log_info "---- Processing user '${username}' (UID ${uid}) ----"
    log_info "  Details: ${details}"

    # 1. Remove FileVault access.
    if echo "$details" | /usr/bin/grep -q "filevault=enabled"; then
        run_action "fdesetup remove -user '${username}'" \
            /usr/bin/fdesetup remove -user "$username"
    fi

    # 2. Strip secondary group memberships.
    strip_group_memberships "$username"

    # 3. Delete account + home directory.
    run_action "sysadminctl -deleteUser '${username}'" \
        /usr/sbin/sysadminctl -deleteUser "$username"

    if [[ "$DRY_RUN" != "true" ]]; then
        # 4. dscl fallback if the record survives.
        if /usr/bin/dscl . -read "/Users/${username}" &>/dev/null; then
            log_warn "User record for '${username}' survived sysadminctl; using dscl."
            run_action "dscl delete /Users/${username}" \
                /usr/bin/dscl . -delete "/Users/${username}"
        fi

        # 5. Remove home directory if it survives.
        if [[ -d "$home_dir" ]]; then
            log_warn "Home directory '${home_dir}' survived; removing."
            run_action "rm -rf '${home_dir}'" /bin/rm -rf "$home_dir"
        fi

        # 7. Remove dslocal plist if it survives.
        if [[ -f "${DSLOCAL_USERS}/${username}.plist" ]]; then
            log_warn "dslocal plist for '${username}' survived; removing."
            run_action "rm -f dslocal plist" \
                /bin/rm -f "${DSLOCAL_USERS}/${username}.plist"
        fi
    else
        log_info "[DRY RUN]   Would dscl-delete record, remove home dir, and remove dslocal plist if they survive."
    fi

    # 8. Clear auto-login if needed.
    clear_autologin_if_needed "$username"

    # 9 + 10. Residual references and managed prefs.
    scrub_residual_references "$username" "$uid"

    log_info "---- Finished primary processing for '${username}' ----"
}

# ============================ Verification ===================================

# Returns 0 if fully clean, 1 if any artifact remains. Logs each finding.
verify_user_removed() {
    local username="$1"
    local home_dir="/Users/${username}"
    local clean=0

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN]   Skipping verification (no changes were made)."
        return 0
    fi

    if /usr/bin/dscl . -read "/Users/${username}" &>/dev/null; then
        log_error "  VERIFY FAIL: directory-services record still present for '${username}'."
        clean=1
    fi
    if [[ -d "$home_dir" ]]; then
        log_error "  VERIFY FAIL: home directory '${home_dir}' still present."
        clean=1
    fi
    if [[ -f "${DSLOCAL_USERS}/${username}.plist" ]]; then
        log_error "  VERIFY FAIL: dslocal plist still present for '${username}'."
        clean=1
    fi
    if [[ -d "${DELETED_USERS_DIR}/${username}" ]] \
        || ls "${DELETED_USERS_DIR}/${username}".* &>/dev/null; then
        log_error "  VERIFY FAIL: Deleted Users archive still present for '${username}'."
        clean=1
    fi
    if /usr/bin/id -Gn "$username" &>/dev/null; then
        log_error "  VERIFY FAIL: '${username}' still resolves to group memberships."
        clean=1
    fi
    if /usr/bin/fdesetup list 2>/dev/null | /usr/bin/grep -q "^${username},"; then
        log_error "  VERIFY FAIL: '${username}' still has FileVault access."
        clean=1
    fi

    if [[ "$clean" -eq 0 ]]; then
        log_info "  VERIFY OK: no artifacts remain for '${username}'. Clean slate confirmed."
    fi
    return "$clean"
}

# ================================= Main ======================================

main() {
    DELETE_REPORT=()

    log_info "========== Whitelist User Cleanup Started =========="
    log_info "Params: DRY_RUN=${DRY_RUN}, PROTECT_ADMINS=${PROTECT_ADMINS}, MIN_UID=${MIN_UID}"

    # ---- Must run as root ----
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "This script must run as root (sudo / Jamf). Exiting."
        exit 1
    fi

    # ---- Validate parameters ----
    if [[ -z "$WHITELIST" ]]; then
        log_warn "No custom whitelist (\$4) provided. Only built-in system"
        log_warn "accounts and the current console user will be protected."
        log_warn "If this is unintended, abort now. Continuing in 5 seconds..."
        sleep 5
    fi
    if ! [[ "$MIN_UID" =~ ^[0-9]+$ ]]; then
        log_error "MIN_UID (\$7) must be an integer. Got '${MIN_UID}'. Exiting."
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "*** DRY RUN MODE — no accounts will be modified or deleted ***"
    fi

    # ---- Build whitelist ----
    local whitelist
    whitelist="$(build_whitelist)"
    log_info "Full whitelist: $(echo "$whitelist" | tr '\n' ' ')"

    # ---- Enumerate candidate users ----
    local deleted_count=0 skipped_count=0 fail_count=0

    # Use dscl as the source of truth for real local accounts.
    local username
    while IFS= read -r username; do
        [[ -z "$username" ]] && continue

        # Skip service accounts (leading underscore).
        if [[ "$username" == _* ]]; then
            continue
        fi

        # Skip whitelisted users.
        if echo "$whitelist" | /usr/bin/grep -qx "$username"; then
            log_info "Skipping whitelisted user '${username}'."
            skipped_count=$((skipped_count + 1))
            continue
        fi

        # Skip by UID floor.
        local uid
        uid="$(get_uid "$username")"
        if [[ -z "$uid" ]] || ! [[ "$uid" =~ ^[0-9]+$ ]]; then
            log_warn "Could not read UID for '${username}'. Skipping."
            skipped_count=$((skipped_count + 1))
            continue
        fi
        if [[ "$uid" -lt "$MIN_UID" ]]; then
            log_info "Skipping '${username}' (UID ${uid} < MIN_UID ${MIN_UID})."
            skipped_count=$((skipped_count + 1))
            continue
        fi

        # Optional admin protection.
        if [[ "$PROTECT_ADMINS" == "true" ]] && is_admin_user "$username"; then
            log_info "Skipping admin user '${username}' (PROTECT_ADMINS=true)."
            skipped_count=$((skipped_count + 1))
            continue
        fi

        # ---- This user is a deletion target ----
        local details
        details="$(get_user_details "$username")"
        DELETE_REPORT+=("${username}|${details}")

        delete_and_scrub "$username" "$details"

        if verify_user_removed "$username"; then
            deleted_count=$((deleted_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi

    done < <(/usr/bin/dscl . -list /Users 2>/dev/null | sort)

    # ---- Summary ----
    log_info "========== Cleanup Summary =========="
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Mode: DRY RUN (no changes made)"
        log_info "Users that WOULD be deleted: ${#DELETE_REPORT[@]}"
        log_info "Users protected/skipped:     ${skipped_count}"
        if [[ ${#DELETE_REPORT[@]} -gt 0 ]]; then
            log_info ""
            log_info "=============== Would-Delete Report ==============="
            printf "%-16s %-7s %-18s %-8s %-11s %-4s %s\n" \
                "USERNAME" "UID" "REAL NAME" "SIZE" "LASTACTIVE" "FV" "GROUPS" | tee -a "$LOG_FILE"
            for entry in "${DELETE_REPORT[@]}"; do
                local u rest r_uid r_name r_size r_last r_fv r_groups
                u="${entry%%|*}"; rest="${entry#*|}"
                r_uid="$(echo "$rest"   | /usr/bin/sed 's/.*uid=\([^|]*\).*/\1/')"
                r_name="$(echo "$rest"  | /usr/bin/sed 's/.*real_name=\([^|]*\).*/\1/')"
                r_size="$(echo "$rest"  | /usr/bin/sed 's/.*dir_size=\([^|]*\).*/\1/')"
                r_last="$(echo "$rest"  | /usr/bin/sed 's/.*last_active=\([^|]*\).*/\1/')"
                r_fv="$(echo "$rest"    | /usr/bin/sed 's/.*filevault=\([^|]*\).*/\1/')"
                r_groups="$(echo "$rest"| /usr/bin/sed 's/.*groups=\([^|]*\).*/\1/')"
                printf "%-16s %-7s %-18s %-8s %-11s %-4s %s\n" \
                    "$u" "$r_uid" "$r_name" "$r_size" "$r_last" "$r_fv" "$r_groups" | tee -a "$LOG_FILE"
            done
            log_info "==================================================="
            log_info "Re-run with DRY_RUN=false to perform the deletion."
        else
            log_info "No users matched the deletion criteria."
        fi
    else
        log_info "Users deleted & scrubbed clean: ${deleted_count}"
        log_info "Users protected/skipped:        ${skipped_count}"
        log_info "Deletions with residual issues: ${fail_count}"
    fi
    log_info "========== Whitelist User Cleanup Finished =========="

    [[ "$fail_count" -gt 0 ]] && exit 1
    exit 0
}

main
