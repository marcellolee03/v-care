```bash
#!/bin/bash

# Security and error handling
set -euo pipefail

# --- Pre-requisites and validation ---
# Check for root privileges
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# --- Global Variables ---
JSP_FILE_TO_DELETE="/openvasvt241992671.jsp" # Specific file identified in the vulnerability report

# --- Functions ---

# Function to find web.xml files in common Tomcat installation paths on Debian
find_web_xml_files() {
    local -a web_xml_paths=()
    local potential_patterns=(
        "/etc/tomcat*/web.xml"
        "/var/lib/tomcat*/conf/web.xml"
        "/usr/share/tomcat*/conf/web.xml"
    )

    for pattern in "${potential_patterns[@]}"; do
        for f in $pattern; do
            if [[ -f "$f" ]]; then
                # Add to array only if not already present (for distinct paths)
                local found=0
                for existing_path in "${web_xml_paths[@]}"; do
                    if [[ "$existing_path" == "$f" ]]; then
                        found=1
                        break
                    fi
                done
                if [[ "$found" -eq 0 ]]; then
                    web_xml_paths+=("$f")
                fi
            fi
        done
    done

    if [[ ${#web_xml_paths[@]} -eq 0 ]]; then
        echo "Error: No web.xml files found in common Tomcat locations." >&2
        return 1
    fi
    printf "%s\n" "${web_xml_paths[@]}" # Print each path on a new line
}

# Function to restart a Tomcat service
restart_tomcat_service() {
    local service_name="$1"
    # Check if the service unit exists
    if systemctl list-units --type=service --all | grep -q "${service_name}.service"; then
        if systemctl is-active --quiet "$service_name"; then
            systemctl restart "$service_name" >/dev/null 2>&1 || {
                echo "Error: Failed to restart Tomcat service '$service_name'." >&2
                return 1
            }
        else
            # Service exists but is not active, no need to restart, but inform
            echo "Warning: Tomcat service '$service_name' is not active. Skipping restart." >&2
        fi
    else
        # Service unit does not exist
        echo "Warning: Tomcat service '$service_name' does not exist. Skipping restart." >&2
    fi
    return 0
}

# --- Main Logic ---

# 1. Clean up the uploaded JSP file
# Search common Tomcat webapps directories for the specific malicious JSP file
FOUND_JSP_FILES=false
for webapp_root_dir in "/var/lib/tomcat*" "/usr/share/tomcat*"; do
    # Use find to locate 'webapps' directories under these roots
    # -maxdepth 2 to prevent excessive searching
    find "$webapp_root_dir" -maxdepth 2 -type d -name "webapps" 2>/dev/null | while IFS= read -r webapp_dir; do
        TARGET_FILE="${webapp_dir}${JSP_FILE_TO_DELETE}"
        if [[ -f "$TARGET_FILE" ]]; then
            echo "Found uploaded JSP file: $TARGET_FILE. Deleting..." >&2
            if rm -f "$TARGET_FILE"; then
                FOUND_JSP_FILES=true
            else
                echo "Error: Failed to delete $TARGET_FILE." >&2
            fi
        fi
    done
done
# No warning if file not found, as it might have been cleaned up previously.

# 2. Modify web.xml for each detected Tomcat instance
WEB_XML_FILES=()
# Read output of find_web_xml_files into an array, splitting by newline
while IFS= read -r line; do
    WEB_XML_FILES+=("$line")
done < <(find_web_xml_files)

if [[ ${#WEB_XML_FILES[@]} -eq 0 ]]; then
    echo "Error: No Tomcat web.xml configuration files found. Mitigation cannot be applied." >&2
    exit 1
fi

CHANGES_MADE=false
RESTART_SERVICES=()

for web_xml_path in "${WEB_XML_FILES[@]}"; do
    # Extract Tomcat service name (e.g., tomcat7, tomcat8) from path for potential restart
    if [[ "$web_xml_path" =~ (tomcat[0-9]+) ]]; then
        tomcat_service="${BASH_REMATCH[1]}"
        # Add service to list for restart if not already present
        if [[ ! " ${RESTART_SERVICES[@]} " =~ " ${tomcat_service} " ]]; then
            RESTART_SERVICES+=("$tomcat_service")
        fi
    else
        echo "Warning: Could not determine Tomcat service name for '$web_xml_path'. Manual restart may be required." >&2
    fi

    # Check if the 'readonly' parameter for the 'default' servlet is already explicitly set to 'false'.
    # This ensures idempotency: if already mitigated, do nothing.
    # The grep pattern is designed to be robust to whitespace.
    if grep -qE '<servlet-name>default</servlet-name>' "$web_xml_path" && \
       grep -qE '<param-name>[[:space:]]*readonly[[:space:]]*</param-name>[[:space:]]*<param-value>[[:space:]]*false[[:space:]]*</param-value>' "$web_xml_path"; then
        continue # Already mitigated, skip to next file
    fi

    # If not already 'false', check if 'readonly' parameter is set to 'true' and change it to 'false'.
    if grep -qE '<servlet-name>default</servlet-name>' "$web_xml_path" && \
       grep -qE '<param-name>[[:space:]]*readonly[[:space:]]*</param-name>[[:space:]]*<param-value>[[:space:]]*true[[:space:]]*</param-value>' "$web_xml_path"; then
        # Use sed to replace 'true' with 'false' within the readonly param-value.
        # This sed command works on a range, finds the 'readonly' param-name, then the next line (param-value)
        # and substitutes 'true' with 'false'. The '.bak' creates a backup which is then removed.
        if sed -i.bak -E '/<servlet-name>default<\/servlet-name>/,/<\/servlet>/ {
            /<param-name>[[:space:]]*readonly[[:space:]]*<\/param-name>/{
                n; # Read the next line into pattern space (expected: <param-value>...)
                s/(<param-value>)[[:space:]]*true[[:space:]]*(<\/param-value>)/\1false\2/
                b # Skip to end of current script to prevent further processing for this line
            }
        }' "$web_xml_path"; then
            CHANGES_MADE=true
        else
            echo "Error: Sed failed to modify 'readonly' parameter in '$web_xml_path'." >&2
            # Attempt to restore from backup if sed failed, though -i.bak usually implies success
            mv "${web_xml_path}.bak" "$web_xml_path" 2>/dev/null || true
            continue
        fi
        rm -f "${web_xml_path}.bak" # Clean up successful backup file
    else
        # The 'readonly' parameter is either missing or has an unexpected value.
        # Insert the 'readonly' parameter with value 'false' explicitly before the closing </servlet> tag.
        if sed -i.bak -E '/<servlet-name>default<\/servlet-name>/,/<\/servlet>/ {
            /<\/servlet>/i\
            <init-param>\
                <param-name>readonly</param-name>\
                <param-value>false</param-value>\
            </init-param>
        }' "$web_xml_path"; then
            CHANGES_MADE=true
        else
            echo "Error: Sed failed to add 'readonly' parameter in '$web_xml_path'." >&2
            # Attempt to restore from backup if sed failed
            mv "${web_xml_path}.bak" "$web_xml_path" 2>/dev/null || true
            continue
        fi
        rm -f "${web_xml_path}.bak" # Clean up successful backup file
    fi
done

# 3. Restart affected Tomcat services if any configuration changes were made
if [[ "$CHANGES_MADE" = true ]]; then
    for service in "${RESTART_SERVICES[@]}"; do
        restart_tomcat_service "$service" || true # Continue with other services even if one fails
    done
fi

exit 0
```