#!/bin/bash
# Detailed WayVNC diagnostic

set -e

CTID=103

echo "=== WayVNC Detailed Diagnostics ==="
echo ""

echo "1. WayVNC Version:"
pct exec "$CTID" -- wayvnc --version 2>&1 || echo "Could not get version"
echo ""

echo "2. WayVNC Config File:"
pct exec "$CTID" -- cat /home/waydroid/.config/wayvnc/config 2>/dev/null || echo "No config file"
echo ""

echo "3. WayVNC Process Details:"
pct exec "$CTID" -- ps aux | grep -E "[w]ayvnc"
echo ""

echo "4. WayVNC Command Line (from process):"
pct exec "$CTID" -- bash -c 'cat /proc/$(pgrep wayvnc)/cmdline | tr "\0" " "' 2>/dev/null || echo "Could not get cmdline"
echo ""

echo "5. Check ALL wayvnc config locations:"
pct exec "$CTID" -- bash <<'EOF'
echo "Checking /home/waydroid/.config/wayvnc/:"
ls -la /home/waydroid/.config/wayvnc/ 2>/dev/null || echo "Directory doesn't exist"

echo ""
echo "Checking /root/.config/wayvnc/:"
ls -la /root/.config/wayvnc/ 2>/dev/null || echo "Directory doesn't exist"

echo ""
echo "Checking /etc/wayvnc/:"
ls -la /etc/wayvnc/ 2>/dev/null || echo "Directory doesn't exist"

echo ""
echo "Searching for ANY config files:"
find /home /root /etc -name "*wayvnc*" -o -name "*.ini" -o -name "config" 2>/dev/null | grep -i vnc || echo "No VNC-related files found"
EOF
echo ""

echo "6. WayVNC Log Files:"
pct exec "$CTID" -- bash <<'EOF'
echo "=== /var/log/waydroid-wayvnc.log ==="
if [ -f /var/log/waydroid-wayvnc.log ]; then
    tail -20 /var/log/waydroid-wayvnc.log
else
    echo "File doesn't exist"
fi

echo ""
echo "=== Checking for other wayvnc logs ==="
find /var/log /tmp /home/waydroid -name "*vnc*" -o -name "*wayvnc*" 2>/dev/null || echo "No other log files"
EOF
echo ""

echo "7. Test: Run WayVNC manually in foreground:"
echo "Stopping service first..."
pct exec "$CTID" -- systemctl stop waydroid-vnc.service
sleep 3

echo "Running wayvnc manually to see actual output..."
pct exec "$CTID" -- timeout 5 su - waydroid -c "XDG_RUNTIME_DIR=/run/user/995 WAYLAND_DISPLAY=wayland-1 wayvnc --help" 2>&1 || echo "Help output shown"
echo ""

echo "8. Checking WayVNC default security:"
pct exec "$CTID" -- bash <<'EOF'
# Check if wayvnc has compiled-in security requirements
strings $(which wayvnc) | grep -i "auth\|security\|password" | head -20 || echo "No auth strings found"
EOF
echo ""

echo "=== Diagnostic Complete ==="
echo ""
echo "Restarting service..."
pct exec "$CTID" -- systemctl start waydroid-vnc.service
