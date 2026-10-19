```bash
#!/bin/bash
set -euo pipefail

# Ensure the script is run as root
if [[ "$EUID" -ne 0 ]]; then
    echo "Error: This script must be run as root to perform system updates." >&2
    exit 1
fi

# Function to safely retrieve the installed Jenkins version
get_jenkins_version() {
    local version_info
    version_info=$(dpkg -s jenkins 2>/dev/null | grep '^Version:' | awk '{print $2}')
    if [[ -z "$version_info" ]]; then
        echo "Error: Jenkins package information could not be retrieved. Is Jenkins installed via APT?" >&2
        exit 1
    fi
    echo "$version_info"
}

# Function to check if the current Jenkins version is fixed or newer
# Returns 0 if fixed/newer, 1 if vulnerable
is_version_fixed() {
    local current_version=$1
    local fixed_major="2"
    local fixed_minor="276" # Corresponds to 2.276 (and implicitly 2.263.3 LTS)

    # Extract major and minor version components
    local current_major=$(echo "$current_version" | cut -d'.' -f1)
    local current_minor=$(echo "$current_version" | cut -d'.' -f2)

    # Perform numerical comparison
    if [[ "$current_major" -gt "$fixed_major" ]]; then
        return 0 # Current major is newer
    elif [[ "$current_major" -eq "$fixed_major" ]]; then
        if [[ "$current_minor" -ge "$fixed_minor" ]]; then
            return 0 # Current minor is equal or newer
        fi
    fi
    return 1 # Current version is older and thus vulnerable
}

# --- Main script execution ---

current_jenkins_version=$(get_jenkins_version)

# Check if the current version is already fixed
if is_version_fixed "$current_jenkins_version"; then
    # Script is idempotent: if already fixed, do nothing and exit silently.
    exit 0
else
    # The current Jenkins version is vulnerable, proceed with upgrade
    echo "Detected vulnerable Jenkins version ($current_jenkins_version). Attempting upgrade..." >&2

    # Update package lists
    if ! apt-get update > /dev/null; then
        echo "Error: Failed to update apt package lists. Check network connectivity or repository configuration." >&2
        exit 1
    fi

    # Upgrade the Jenkins package to the latest available version
    # DEBIAN_FRONTEND=noninteractive prevents prompts during installation
    # -y automatically confirms installation
    # --only-upgrade ensures only the Jenkins package is upgraded
    if ! DEBIAN_FRONTEND=noninteractive apt-get -y install --only-upgrade jenkins > /dev/null; then
        echo "Error: Failed to upgrade Jenkins package. Check apt logs for details." >&2
        exit 1
    fi

    # Verify the upgrade by checking the new Jenkins version
    local new_jenkins_version
    new_jenkins_version=$(get_jenkins_version)

    if is_version_fixed "$new_jenkins_version"; then
        # Upgrade successful and version is now fixed. Exit silently as per requirements.
        exit 0
    else
        echo "Error: Jenkins upgrade completed, but the version is still vulnerable ($new_jenkins_version)." >&2
        echo "Manual intervention may be required to resolve the issue." >&2
        exit 1
    fi
fi
```