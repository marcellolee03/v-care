```bash
#!/bin/bash
set -euo pipefail

# Semantic variable names
JBOSS_COMMON_ROOTS=("/opt" "/usr/local" "/var/lib")
INVOKER_SERVLET_WAR="invoker.war"
DISABLED_SUFFIX=".disabled"

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root to modify system files." >&2
    exit 1
fi

# Function to find and disable invoker.war
# This function is designed to be idempotent: it renames 'invoker.war' to 'invoker.war.disabled'
# and does nothing if the file is already named 'invoker.war.disabled'.
disable_invoker_war() {
    local search_path="$1"
    
    # Use find to locate 'invoker.war' files within typical JBoss/WildFly deployment structures.
    # The vulnerability specifically targets JBoss EJB/JMXInvokerServlets, which are often
    # part of an 'invoker.war' deployment in older JBoss AS versions.
    # -print0 and read -r -d $'\0' handle filenames with spaces correctly, though less common here.
    find "$search_path" -type f -name "$INVOKER_SERVLET_WAR" -print0 2>/dev/null | while IFS= read -r -d $'\0' invoker_war_path; do
        local disabled_path="${invoker_war_path}${DISABLED_SUFFIX}"
        
        # Check if the invoker.war is already disabled (renamed to .disabled)
        if [ -f "$disabled_path" ]; then
            # Already disabled, no action needed for idempotency
            continue
        fi

        # Perform the disabling by renaming the .war file
        if mv "$invoker_war_path" "$disabled_path"; then
            : # Silent on success
        else
            echo "Error: Failed to rename '$invoker_war_path' to '$disabled_path'. Check permissions or disk space." >&2
        fi
    done
}

found_any_invoker=false
# Iterate through common JBoss/application server root directories
for root_dir in "${JBOSS_COMMON_ROOTS[@]}"; do
    if [ -d "$root_dir" ]; then
        # Check if any invoker.war exists under the current root_dir before processing
        if find "$root_dir" -type f -name "$INVOKER_SERVLET_WAR" -print -quit 2>/dev/null; then
            found_any_invoker=true
            disable_invoker_war "$root_dir"
        fi
    fi
done

# If no invoker.war files were found, report a warning.
if ! $found_any_invoker; then
    echo "Warning: No '${INVOKER_SERVLET_WAR}' found in common JBoss/application server deployment locations ('${JBOSS_COMMON_ROOTS[*]}')." >&2
    echo "         The vulnerability might not apply to this system, or the JBoss installation path differs from expected." >&2
    echo "         Manual verification of application server configuration may be required." >&2
fi

# Script is silent on success, error messages go to stderr.
```