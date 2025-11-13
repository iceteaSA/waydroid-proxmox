#!/bin/bash
# FINAL WayVNC fix - use config file explicitly

set -e

CTID=103

echo "=== FINAL WayVNC Authentication Fix ==="
echo ""

echo "Step 1: Stop service and kill processes..."
pct exec "$CTID" -- systemctl stop waydroid-vnc.service
sleep 2
pct exec "$CTID" -- pkill -9 wayvnc || true
pct exec "$CTID" -- pkill -9 sway || true
sleep 3
echo "✓ Processes killed"
echo ""

echo "Step 2: Create proper WayVNC config with explicit no-auth..."
pct exec "$CTID" -- bash <<'EOF'
# Clean everything
rm -rf /home/waydroid/.config/wayvnc/*

# Create config directory
mkdir -p /home/waydroid/.config/wayvnc

# Create config file with explicit settings
cat > /home/waydroid/.config/wayvnc/config <<'ENDCONFIG'
address=0.0.0.0
port=5900
enable_auth=false
ENDCONFIG

chown -R waydroid:waydroid /home/waydroid/.config/wayvnc
chmod 644 /home/waydroid/.config/wayvnc/config

echo "✓ Config created with enable_auth=false"
cat /home/waydroid/.config/wayvnc/config
EOF
echo ""

echo "Step 3: Update startup script to use -C flag..."
pct exec "$CTID" -- bash <<'EOF'
# Backup current script
cp /usr/local/bin/start-waydroid.sh /usr/local/bin/start-waydroid.sh.backup

# Update the wayvnc command to use -C flag
sed -i 's|wayvnc 0\.0\.0\.0 5900|wayvnc -C /home/waydroid/.config/wayvnc/config|g' /usr/local/bin/start-waydroid.sh

echo "✓ Updated startup script"
echo "Changed line:"
grep "wayvnc -C" /usr/local/bin/start-waydroid.sh || echo "ERROR: Change failed!"
EOF
echo ""

echo "Step 4: Restart service..."
pct exec "$CTID" -- systemctl start waydroid-vnc.service
echo "Waiting 20 seconds..."
sleep 20
echo ""

echo "=== VERIFICATION ==="
echo ""

echo "Service status:"
pct exec "$CTID" -- systemctl status waydroid-vnc.service --no-pager | head -15
echo ""

echo "Port 5900:"
pct exec "$CTID" -- ss -tlnp | grep 5900
echo ""

echo "WayVNC process command:"
pct exec "$CTID" -- bash -c 'cat /proc/$(pgrep wayvnc | head -1)/cmdline | tr "\0" " "' 2>/dev/null || echo "Process not found"
echo ""

CONTAINER_IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
echo "=== TRY CONNECTING NOW ==="
echo "Container IP: $CONTAINER_IP"
echo "Command: vncviewer $CONTAINER_IP:5900"
echo ""
echo "If it still fails, check the WayVNC log:"
echo "pct exec $CTID -- cat /var/log/waydroid-wayvnc.log"
