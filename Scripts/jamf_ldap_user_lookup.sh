#!/bin/bash
###############################################################################
# jamf_ldap_user_lookup.sh
#
# Purpose:  Runs on Mac endpoints via Jamf Pro policy (recurring check in).
#           Gets the currently logged in user, performs an LDAP lookup via
#           the Jamf Pro API, and updates the computer's User and Location
#           fields with department, email, phone, position, etc.
#
# Deploy:   Upload to Jamf Pro as a script, attach to a recurring policy
#           scoped to all managed Macs (once per day or at check in).
#
# Parameters (set in Jamf Pro policy):
#   $4  - Jamf Pro URL (e.g. https://yourinstance.jamfcloud.com)
#   $5  - API Client ID
#   $6  - API Client Secret
#   $7  - LDAP Server ID (default: 1)
#   $8  - Email domain suffix for LDAP lookup (e.g. @cnu.edu)
#         If set, appended to the short username so the LDAP query
#         uses "user@domain" instead of just "user".
#
# Auth:     Uses API Client credentials (client_id / client_secret).
#           Create an API Role and API Client in Jamf Pro with these
#           minimum permissions:
#             - Read Computers
#             - Update Computers
#             - Read LDAP Servers
#             - Read Users
#
# Notes:    Uses Classic API for LDAP server lookup (no Jamf Pro API
#           equivalent exists yet) and Jamf Pro API for computer inventory.
###############################################################################

# =============================================================================
# CONFIGURATION — Set via Jamf Pro script parameters
# =============================================================================

# Jamf Pro URL (no trailing slash)
JAMF_PRO_URL="${4}"

# API Client credentials (create under Settings > API Roles and Clients)
CLIENT_ID="${5}"
CLIENT_SECRET="${6}"

# LDAP Server ID in Jamf Pro (find under Settings > LDAP Servers; the number
# at the end of the URL when you click your LDAP connection is the ID)
LDAP_SERVER_ID="${7:-1}"

# Email domain suffix (e.g. @cnu.edu) — appended to short username for LDAP lookup
LDAP_DOMAIN_SUFFIX="${8}"

# Logging
LOG_FILE="/var/log/jamf_ldap_lookup.log"

# Track whether we have a token (for the cleanup trap)
API_TOKEN=""

# =============================================================================
# PARAMETER VALIDATION
# =============================================================================

if [[ -z "${JAMF_PRO_URL}" ]]; then
    echo "ERROR: Parameter 4 (Jamf Pro URL) is required." >&2
    exit 1
fi

if [[ -z "${CLIENT_ID}" ]]; then
    echo "ERROR: Parameter 5 (API Client ID) is required." >&2
    exit 1
fi

if [[ -z "${CLIENT_SECRET}" ]]; then
    echo "ERROR: Parameter 6 (API Client Secret) is required." >&2
    exit 1
fi

# Strip any trailing slash from the URL
JAMF_PRO_URL="${JAMF_PRO_URL%/}"

# =============================================================================
# FUNCTIONS
# =============================================================================

log_message() {
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "${timestamp} | $1" >> "${LOG_FILE}"
}

# Escape special characters for safe XML embedding
xml_escape() {
    local str="$1"
    str="${str//&/&amp;}"
    str="${str//</&lt;}"
    str="${str//>/&gt;}"
    str="${str//\"/&quot;}"
    str="${str//\'/&apos;}"
    echo "${str}"
}

# Cleanup handler — invalidates token on any exit if one was obtained
cleanup() {
    if [[ -n "${API_TOKEN}" && "${API_TOKEN}" != "null" ]]; then
        /usr/bin/curl \
            --silent \
            --request POST \
            --url "${JAMF_PRO_URL}/api/v1/auth/invalidate-token" \
            --header "Authorization: Bearer ${API_TOKEN}" \
            > /dev/null 2>&1
        log_message "API token invalidated."
    fi
    log_message "========== LDAP User Lookup Script Completed =========="
}

# Register the cleanup trap so the token is always invalidated
trap cleanup EXIT

# Get bearer token using API Client credentials
get_api_token() {
    local response
    response=$( /usr/bin/curl \
        --silent \
        --request POST \
        --url "${JAMF_PRO_URL}/api/oauth/token" \
        --header "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "client_id=${CLIENT_ID}" \
        --data-urlencode "client_secret=${CLIENT_SECRET}" \
        --data-urlencode "grant_type=client_credentials" \
    )

    # Parse the access token from JSON response
    API_TOKEN=$( /usr/bin/plutil -extract access_token raw -o - - <<< "${response}" 2>/dev/null )

    if [[ -z "${API_TOKEN}" || "${API_TOKEN}" == "null" ]]; then
        log_message "ERROR: Failed to obtain API token. Check client credentials."
        API_TOKEN=""
        exit 1
    fi

    log_message "Successfully obtained API token."
}

# Get the currently logged in console user
get_current_user() {
    CURRENT_USER=$( /usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }' )

    if [[ -z "${CURRENT_USER}" || "${CURRENT_USER}" == "root" ]]; then
        log_message "No standard user currently logged in. Exiting."
        exit 0
    fi

    log_message "Current console user: ${CURRENT_USER}"

    # Build the LDAP lookup name — append domain suffix if provided
    if [[ -n "${LDAP_DOMAIN_SUFFIX}" ]]; then
        LDAP_LOOKUP_USER="${CURRENT_USER}${LDAP_DOMAIN_SUFFIX}"
    else
        LDAP_LOOKUP_USER="${CURRENT_USER}"
    fi

    log_message "LDAP lookup user: ${LDAP_LOOKUP_USER}"
}

# Get the Jamf Pro computer ID using the serial number
get_computer_id() {
    local serial_number
    serial_number=$( /usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Serial Number/ { print $NF }' )

    if [[ -z "${serial_number}" ]]; then
        log_message "ERROR: Could not determine serial number."
        exit 1
    fi

    log_message "Serial number: ${serial_number}"

    # Use Jamf Pro API to get computer inventory by serial number
    local response
    response=$( /usr/bin/curl \
        --silent \
        --request GET \
        --url "${JAMF_PRO_URL}/api/v1/computers-inventory?section=GENERAL&filter=hardware.serialNumber==%22${serial_number}%22" \
        --header "Authorization: Bearer ${API_TOKEN}" \
        --header "Accept: application/json" \
    )

    COMPUTER_ID=$( echo "${response}" | /usr/bin/python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    if results:
        print(results[0].get('id', ''))
except:
    pass
" 2>/dev/null )

    if [[ -z "${COMPUTER_ID}" ]]; then
        log_message "ERROR: Could not find computer ID for serial ${serial_number}."
        exit 1
    fi

    log_message "Jamf Pro computer ID: ${COMPUTER_ID}"
}

# Perform LDAP lookup for the current user via Classic API
# Parses all attributes in a single python3 call for efficiency
ldap_user_lookup() {
    local response
    response=$( /usr/bin/curl \
        --silent \
        --request GET \
        --url "${JAMF_PRO_URL}/JSSResource/ldapservers/id/${LDAP_SERVER_ID}/user/${LDAP_LOOKUP_USER}" \
        --header "Authorization: Bearer ${API_TOKEN}" \
        --header "Accept: application/json" \
    )

    # Parse all LDAP attributes in one python3 invocation
    local parsed
    parsed=$( echo "${response}" | /usr/bin/python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    users = data.get('ldap_users', [])
    if users:
        u = users[0]
        print(u.get('email', ''))
        print(u.get('department', ''))
        print(u.get('realname', u.get('full_name', '')))
        print(u.get('phone', u.get('phone_number', '')))
        print(u.get('position', u.get('title', '')))
    else:
        for _ in range(5):
            print('')
except:
    for _ in range(5):
        print('')
" 2>/dev/null )

    # Read the five lines into variables
    LDAP_EMAIL=$(    sed -n '1p' <<< "${parsed}" )
    LDAP_DEPARTMENT=$( sed -n '2p' <<< "${parsed}" )
    LDAP_REALNAME=$( sed -n '3p' <<< "${parsed}" )
    LDAP_PHONE=$(    sed -n '4p' <<< "${parsed}" )
    LDAP_POSITION=$( sed -n '5p' <<< "${parsed}" )

    if [[ -z "${LDAP_EMAIL}" && -z "${LDAP_DEPARTMENT}" ]]; then
        log_message "WARNING: LDAP lookup returned no usable data for user ${LDAP_LOOKUP_USER}."
        exit 0
    fi

    log_message "LDAP lookup succeeded for ${LDAP_LOOKUP_USER}."
}

# Update the computer record's User and Location with LDAP data
update_computer_record() {
    # Escape all values for safe XML embedding
    local safe_user safe_realname safe_email safe_dept safe_phone safe_position
    safe_user=$(     xml_escape "${CURRENT_USER}" )
    safe_realname=$( xml_escape "${LDAP_REALNAME}" )
    safe_email=$(    xml_escape "${LDAP_EMAIL}" )
    safe_dept=$(     xml_escape "${LDAP_DEPARTMENT}" )
    safe_phone=$(    xml_escape "${LDAP_PHONE}" )
    safe_position=$( xml_escape "${LDAP_POSITION}" )

    local xml_payload="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<computer>
    <location>
        <username>${safe_user}</username>
        <real_name>${safe_realname}</real_name>
        <email_address>${safe_email}</email_address>
        <department>${safe_dept}</department>
        <phone>${safe_phone}</phone>
        <position>${safe_position}</position>
    </location>
</computer>"

    local http_code
    http_code=$( /usr/bin/curl \
        --silent \
        --output /dev/null \
        --write-out "%{http_code}" \
        --request PUT \
        --url "${JAMF_PRO_URL}/JSSResource/computers/id/${COMPUTER_ID}/subset/Location" \
        --header "Authorization: Bearer ${API_TOKEN}" \
        --header "Content-Type: application/xml" \
        --data "${xml_payload}" \
    )

    if [[ "${http_code}" == "201" || "${http_code}" == "200" ]]; then
        log_message "SUCCESS: Updated computer ${COMPUTER_ID} with LDAP data for ${CURRENT_USER}."
    else
        log_message "ERROR: Failed to update computer ${COMPUTER_ID}. HTTP status: ${http_code}"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

log_message "========== LDAP User Lookup Script Started =========="

# Step 1: Get API token
get_api_token

# Step 2: Determine current logged in user
get_current_user

# Step 3: Get this computer's Jamf Pro ID
get_computer_id

# Step 4: Perform LDAP lookup for the current user
ldap_user_lookup

# Step 5: Update the computer record with LDAP data
update_computer_record

# Cleanup (token invalidation) happens automatically via the EXIT trap

exit 0
