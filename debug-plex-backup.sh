#!/usr/bin/env bash

# Debug script for Plex backup systemd issue
# Usage: ./debug-plex-backup.sh

set -e

echo "=== Plex Backup Debug Investigation ==="
echo

# 1. Check systemd service unit files
echo "1. Checking systemd service unit files:"
echo "   Looking for restic-backups-plex* services..."
find /etc/systemd/system -name "*restic-backups-plex*" -type f 2>/dev/null | while read -r file; do
    echo "   Found: $file"
    echo "   Content:"
    cat "$file" | head -20
    echo "   ---"
done

# 2. Check systemd-analyze for unit validation
echo
echo "2. Running systemd-analyze verify on backup services:"
for service in $(systemctl list-unit-files --type=service | grep -E "restic-backups-plex" | awk '{print $1}'); do
    echo "   Verifying: $service"
    systemd-analyze verify "$service" 2>&1 || echo "   ❌ Verification failed"
done

# 3. Check NixOS-generated systemd units
echo
echo "3. Checking NixOS-generated systemd units:"
NIXOS_UNITS=$(find /nix/store -path "*/etc/systemd/system/*restic-backups-plex*" 2>/dev/null | head -5)
if [ -n "$NIXOS_UNITS" ]; then
    echo "$NIXOS_UNITS" | while read -r unit; do
        echo "   NixOS unit: $unit"
        cat "$unit" | head -10
        echo "   ---"
    done
else
    echo "   No NixOS units found in /nix/store"
fi

# 4. Check systemd unit naming rules
echo
echo "4. Checking systemd unit naming validation:"
echo "   Testing unit name validation..."
python3 -c "
import re
import sys

def validate_unit_name(name):
    # Based on systemd unit naming rules
    # Valid characters: a-z, A-Z, 0-9, -, _, \, @, .
    # Must not start with dot or hyphen
    # Must not end with dot
    pattern = r'^[a-zA-Z0-9_\\\\@][a-zA-Z0-9_\\\\@.-]*[a-zA-Z0-9_\\\\@]$'
    if re.match(pattern, name):
        return True
    return False

test_names = [
    'restic-backups-plex.service',
    'restic-backups-plex_srv_backup_plex.service',
    'restic-backups-plex.timer',
    'restic-backups-plex_srv_backup_plex.timer'
]

for name in test_names:
    valid = validate_unit_name(name)
    print(f'   {name}: {\"✅ Valid\" if valid else \"❌ Invalid\"}')
"

# 5. Check journal logs for systemd errors
echo
echo "5. Checking recent systemd journal logs for unit validation errors:"
journalctl -u systemd --since "1 hour ago" --grep "Unit.*not valid" -n 20 || echo "   No recent validation errors found"

# 6. Check active restic backup services
echo
echo "6. Checking active restic backup services:"
systemctl list-units --type=service --state=active | grep -E "restic-backups" || echo "   No active restic backup services"

# 7. Check SHB restic module configuration
echo
echo "7. Checking SHB restic module instantiation:"
echo "   Looking for restic configuration in /nix/store..."
find /nix/store -name "*.nix" -path "*/modules/blocks/restic.nix" 2>/dev/null | head -1 | xargs cat | grep -A 10 -B 10 "systemd.services" || echo "   Could not find restic module"

echo
echo "=== Debug Investigation Complete ==="