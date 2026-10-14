```bash
#!/bin/bash
# MITIGATION SCRIPT: Harden PostgreSQL SSL/TLS configuration against weak cipher suites.
# This script targets CVE-2013-2566, CVE-2015-2808, CVE-2015-4000 by disabling weak
# SSL/TLS cipher suites (specifically TLS_RSA_WITH_SEED_CBC_SHA) and enforcing
# a minimum TLS protocol version for PostgreSQL.
#
# Requirements:
# - Run as root.
# - PostgreSQL service installed and running on port 5432.
# - Systemd as init system (common on Pop!_OS).
# - Uses native POSIX-compliant commands.
# - Idempotent: Can be run multiple times without adverse effects.
# - Silent on success, reports errors via stderr.

set -euo pipefail

# --- Configuration Variables ---
# Recommended secure cipher string for PostgreSQL (OpenSSL format).
# Excludes known weak ciphers and protocols like RC4, MD5, SEED, 3DES, DES, LOW, EXP, CAMELLIA, DSS, SRP, PSK.
# 'HIGH' generally includes AES128 and AES256, without explicit exclusion.
# Explicitly excluding 'SEED' addresses the reported vulnerability (TLS_RSA_WITH_SEED_CBC_SHA).
NEW_SSL_CIPHERS="HIGH:!aNULL:!MD5:!RC4:!SEED:!CAMELLIA:!DSS:!SRP:!PSK:!EXP:!LOW:!DES:!3DES"

# Ensure a minimum protocol version of TLSv1.2.
# This helps prevent fallback to older, weaker TLS versions.
NEW_SSL_MIN_PROTOCOL_VERSION="TLSv1.2"

# --- Functions ---

# Function to report errors to stderr and exit
error_report() {
    echo "ERROR: $1" >&2
    exit 1
}

# Function to ensure script is run with root privileges
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        error_report "This script must be run as root."
    fi
}

# Function to find the active postgresql.conf file
find_pg_conf() {
    local pg_data_dir
    local pg_conf_file

    # Attempt to find the PostgreSQL data directory from running processes.
    # This assumes a standard PostgreSQL installation where -D specifies the data directory.
    # We use `head -n 1` to target the first found instance in case multiple are running.
    pg_data_dir=$(ps aux | grep -E '^postgres.*-D\s+[^[:space:]]+' | grep -v grep | head -n 1 | sed -E 's/.*-D\s+([^[:space:]]+).*/\1/')

    if [[ -n "$pg_data_dir" ]]; then
        pg_conf_file="${pg_data_dir}/postgresql.conf"
    else
        # Fallback to common Debian/Ubuntu paths if no running process found
        # (e.g., if PostgreSQL is stopped or process listing fails).
        # This is less reliable but covers common installation patterns.
        if ls /etc/postgresql/*/main/postgresql.conf > /dev/null 2>&1; then
            # Take the first one found, assuming a primary instance or the most recent version.
            # Using find with -quit to be efficient and minimalist.
            pg_conf_file=$(find /etc/postgresql -name postgresql.conf -print -quit)
        fi
    fi

    echo "$pg_conf_file" # Output the path, which will be captured by the caller
}

# Function to update a configuration parameter in a file
# Arguments: file_path, parameter_name, new_value
update_config_param() {
    local file="$1"
    local param="$2"
    local new_value="$3"

    # Check if the parameter exists and is already set to the new value (idempotent check)
    # The regex handles potential whitespace around '=' and quotes.
    if grep -qE "^[[:space:]]*${param}[[:space:]]*=[[:space:]]*'${new_value}'[[:space:]]*(#.*)?$" "$file"; then
        return 0 # Already correctly configured, do nothing
    fi

    # Check if the parameter exists (commented or uncommented)
    if grep -qE "^#?[[:space:]]*${param}[[:space:]]*=" "$file"; then
        # Replace existing line (commented or uncommented) with the new value.
        # Captures leading whitespace and the parameter name/equals part, then replaces the rest.
        sed -i -E "s|^#?([[:space:]]*${param}[[:space:]]*=).*|\1 '${new_value}'|" "$file"
    else
        # Parameter not found, append it to the end of the file.
        # This ensures the setting is applied even if not present.
        echo "${param} = '${new_value}'" >> "$file"
    fi
}

# --- Main Script Execution ---

check_root

# Determine the path to postgresql.conf
PG_CONF_FILE=$(find_pg_conf)

if [[ -z "$PG_CONF_FILE" ]]; then
    error_report "Failed to determine the path to postgresql.conf. Please ensure PostgreSQL is installed and running, or specify the path manually."
fi

# Ensure the config file exists before attempting to modify it
if [[ ! -f "$PG_CONF_FILE" ]]; then
    error_report "PostgreSQL configuration file not found at '$PG_CONF_FILE'."
fi

# Apply the ssl_ciphers configuration
update_config_param "$PG_CONF_FILE" "ssl_ciphers" "$NEW_SSL_CIPHERS"

# Apply the ssl_min_protocol_version configuration
update_config_param "$PG_CONF_FILE" "ssl_min_protocol_version" "$NEW_SSL_MIN_PROTOCOL_VERSION"

# Restart PostgreSQL service to apply the configuration changes
# Check if the service is active to avoid attempting to restart an inactive service.
if systemctl is-active --quiet postgresql; then
    if ! systemctl restart postgresql; then
        error_report "Failed to restart PostgreSQL service. Configuration updated, but manual intervention may be required to restart the service."
    fi
else
    echo "PostgreSQL service is not currently active. Configuration updated, but the service was not restarted. It will apply on next start." >&2
fi

exit 0
```