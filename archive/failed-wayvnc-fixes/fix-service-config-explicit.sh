#!/bin/bash
# Explicitly configure service to use WayVNC config file with minimal settings

set -e
CTID=103

echo "=== Step 1: Create MINIMAL config with ONLY enable_auth ==="
pct exec "$CTID" -- bash <<'INNER'
mkdir -p /home/waydroid/.config/wayvnc
cat > /home/waydroid/.config/wayvnc/config <<'EOF'
enable_auth=false
EOF
chown waydroid:waydroid /home/waydroid/.config/wayvnc/config
chmod 644 /home/waydroid/.config/wayvnc/config
echo "Config created:"
cat /home/waydroid/.config/wayvnc/config
INNER

echo ""
echo "=== Step 2: Update startup script to EXPLICITLY use -C flag ==="
pct exec "$CTID" -- bash <<'INNER'
# Find the startup script
if [ -f /usr/local/bin/start-waydroid.sh ]; then
    SCRIPT=/usr/local/bin/start-waydroid.sh
elif [ -f /usr/bin/start-waydroid.sh ]; then
    SCRIPT=/usr/bin/start-waydroid.sh
else
    echo "ERROR: Cannot find start-waydroid.sh"
    exit 1
fi

echo "Found startup script: $SCRIPT"
echo ""
echo "Current wayvnc command:"
grep "wayvnc" "$SCRIPT" | grep -v "^#" || echo "Not found"

# Update to use explicit -C flag with config file, removing address and port from command line
sed -i 's|wayvnc.*0\.0\.0\.0.*5900|wayvnc -C /home/waydroid/.config/wayvnc/config 0.0.0.0 5900|g' "$SCRIPT"

echo ""
echo "Updated wayvnc command:"
grep "wayvnc" "$SCRIPT" | grep -v "^#"
INNER

echo ""
echo "=== Step 3: Check service file ==="
pct exec "$CTID" -- bash <<'INNER'
if [ -f /etc/systemd/system/waydroid-vnc.service ]; then
    echo "Service file exists:"
    cat /etc/systemd/system/waydroid-vnc.service
else
    echo "No service file found"
fi
INNER

echo ""
echo "=== Step 4: Reload systemd and restart service ==="
pct exec "$CTID" -- systemctl daemon-reload
pct exec "$CTID" -- systemctl stop waydroid-vnc.service
sleep 3
pct exec "$CTID" -- pkill -9 wayvnc || true
sleep 2
pct exec "$CTID" -- systemctl start waydroid-vnc.service
sleep 5

echo ""
echo "=== Step 5: Verify process command line ==="
pct exec "$CTID" -- bash <<'INNER'
echo "WayVNC process:"
ps aux | grep wayvnc | grep -v grep

echo ""
echo "Full command line:"
cat /proc/$(pgrep wayvnc)/cmdline | tr '\0' ' '
echo ""
INNER

echo ""
echo "=== Step 6: Check port 5900 ==="
pct exec "$CTID" -- ss -tlnp | grep 5900

echo ""
echo "========================================"
echo "Configuration complete"
echo "========================================"
echo ""
echo "Try connecting: vncviewer 10.1.3.136:5900"
echo ""
echo "If still 'No matching security types', try TigerVNC with VeNCrypt:"
echo "  vncviewer -SecurityTypes=VeNCrypt,X509Plain 10.1.3.136:5900"
