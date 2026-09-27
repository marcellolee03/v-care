```bash
#!/bin/bash
set -euo pipefail

# This script mitigates CVE-2012-0874 and CVE-2013-4810 by disabling
# unauthenticated access to JBoss EJBInvokerServlet and JMXInvokerServlet.
# It does this by renaming 'invoker.war' files found in common JBoss deployment
# locations to 'invoker.war.disabled'.

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Define common JBoss Application Server installation base paths.
# The script will search for 'invoker.war' within these directories.
# If JBoss is installed in a non-standard location, these paths may need adjustment.
JBOSS_INSTALL_PATHS=(
    "/opt/jboss"
    "/usr/local/jboss"
    "/var/lib/jboss"
    "/usr/share/jboss"
)

# Flag to track if any invoker.war file was found and successfully disabled.
ANY_INVOKER_DISABLED=false

# Function to disable an invoker.war file by renaming it.
# This function is idempotent: it will only rename the file if it exists,
# and will do nothing if the '.disabled' version already exists.
# Arguments:
#   $1: The full path to the 'invoker.war' file to be disabled.
disable_invoker_war() {
    local war_path="$1"
    local disabled_path="${war_path}.disabled"

    # Check if the original .war file exists
    if [[ -f "$war_path" ]]; then
        # Rename the file to disable it.
        if mv "$war_path" "$disabled_path"; then
            ANY_INVOKER_DISABLED=true
        else
            echo "Error: Failed to rename '$war_path' to '$disabled_path'." >&2
            exit 1
        fi
    # If the original .war file does not exist, it might already be disabled or removed.
    # In this case, no action is needed, ensuring idempotency.
    fi
}

# Iterate through the defined common JBoss installation paths.
for jboss_base_path in "${JBOSS_INSTALL_PATHS[@]}"; do
    if [[ -d "$jboss_base_path" ]]; then
        # Search for 'invoker.war' files within typical JBoss 'server/*/deploy/' structures.
        # This pattern is common for JBoss AS 4.x, 5.x, and 6.x.
        find "$jboss_base_path" -type f -path "*/server/*/deploy/invoker.war" 2>/dev/null | while read -r war_file; do
            if [[ -n "$war_file" ]]; then
                disable_invoker_war "$war_file"
            fi
        done
    fi
done

# After attempting mitigation, provide feedback to the user.
if ! $ANY_INVOKER_DISABLED; then
    echo "Warning: No 'invoker.war' files were found or required disabling in common JBoss installation paths." >&2
    echo "If JBoss is installed in a non-standard location, manual intervention may be required." >&2
    exit 0 # Exit successfully as no actionable vulnerability was found in expected locations.
else
    # Mitigation successfully applied to one or more instances.
    echo "Mitigation applied: JBoss 'invoker.war' files have been disabled." >&2
    echo "Please restart your JBoss Application Server for the changes to take full effect." >&2
    exit 0
fi
```