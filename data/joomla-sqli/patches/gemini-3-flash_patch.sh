```bash
#!/bin/bash
# Senior System Security Engineer - Joomla SQLi/Logic Bypass Mitigation
# Target: CVE-2019-19846 (Joomla! 2.5.0 - 3.9.13)
# Context: Debian 8 (jessie), Root, Joomla 3.4.2

set -euo pipefail

# Verify root privileges
if [ "$EUID" -ne 0 ]; then
    exit 1
fi

# Define the target component relative path
# CVE-2019-19846 resides in the user reset model where email comparison is insufficient
TARGET_PARTIAL="components/com_users/models/reset.php"

# Find Joomla installations and apply the surgical patch
# We search common web roots and fallback to root if necessary
find /var/www /var/lib /var/www/html / -maxdepth 6 -name "reset.php" -path "*/$TARGET_PARTIAL" 2>/dev/null | while read -r J_FILE; do

    # Idempotency check: Ensure the patch hasn't already been applied
    if grep -q "\$user = \$db->loadObject();" "$J_FILE" && ! grep -q "strcasecmp" "$J_FILE"; then
        
        # Surgical Mitigation:
        # Injects a strict PHP string comparison (strcasecmp) after the database lookup.
        # This prevents the SQL injection/logic bypass where database collations (like utf8mb4_unicode_ci)
        # might treat different email addresses as equivalent, allowing unauthorized password resets.
        
        sed -i '/\$user = \$db->loadObject();/a \ \ \ \ \ \ \ \ if ($user && strcasecmp($user->email, $data['email']) !== 0) { $user = false; }' "$J_FILE"
        
    fi
done

exit 0
```