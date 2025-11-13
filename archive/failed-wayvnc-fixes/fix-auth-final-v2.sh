#!/bin/bash
set -e
CTID=103

echo "=== Checking for password files that override enable_auth=false ==="

echo "Checking waydroid user home directory:"
pct exec "$CTID" -- find /home/waydroid -name "*password*" -o -name "*passwd*" 2>/dev/null || echo "No password files found"

echo ""
echo "Checking XDG_RUNTIME_DIR:"
pct exec "$CTID" -- find /run/user/1000 -name "*password*" -o -name "*passwd*" 2>/dev/null || echo "No password files found"

echo ""
echo "Checking for .wayvnc directory:"
pct exec "$CTID" -- find /home/waydroid -type d -name "*wayvnc*" -exec ls -la {} \; 2>/dev/null || echo "No wayvnc dirs"

echo ""
echo "=== Removing ALL password/auth files ==="
pct exec "$CTID" -- bash <<'INNER'
rm -f /home/waydroid/.config/wayvnc/password 2>/dev/null || true
rm -f /home/waydroid/.config/wayvnc/rsa_*.pem 2>/dev/null || true
rm -f /home/waydroid/.config/wayvnc/*.pem 2>/dev/null || true
rm -f /home/waydroid/.wayvnc_password 2>/dev/null || true
rm -f /run/user/1000/.wayvnc_password 2>/dev/null || true
echo "✓ All auth files removed"
INNER

echo ""
echo "=== Recreating config with ONLY enable_auth=false ==="
pct exec "$CTID" -- bash <<'INNER'
cat > /home/waydroid/.config/wayvnc/config <<'CONFIG'
enable_auth=false
CONFIG
chown waydroid:waydroid /home/waydroid/.config/wayvnc/config
chmod 644 /home/waydroid/.config/wayvnc/config
echo "✓ Config created"
cat /home/waydroid/.config/wayvnc/config
INNER

echo ""
echo "=== Restarting service ==="
pct exec "$CTID" -- systemctl stop waydroid-vnc.service
sleep 3
pct exec "$CTID" -- pkill -9 wayvnc || true
sleep 2
pct exec "$CTID" -- systemctl start waydroid-vnc.service
sleep 5

echo ""
echo "=== Verification ==="
pct exec "$CTID" -- systemctl status waydroid-vnc.service --no-pager | head -20

echo ""
echo "Port 5900:"
pct exec "$CTID" -- ss -tlnp | grep 5900 || echo "NOT LISTENING!"

echo ""
echo "WayVNC command line:"
pct exec "$CTID" -- ps aux | grep wayvnc | grep -v grep || echo "NOT RUNNING!"

echo ""
echo "=== TRY CONNECTING NOW ==="
echo "vncviewer 10.1.3.136:5900"
