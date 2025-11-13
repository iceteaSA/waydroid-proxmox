#!/bin/bash
# Comprehensive WayVNC Authentication Investigation Script
# This will determine why WayVNC is requiring auth despite config changes

set -e

CTID=103

echo "========================================"
echo "WayVNC Authentication Investigation"
echo "========================================"
echo ""

echo "=== STEP 1: Read Current Config File ==="
echo "Location: /home/waydroid/.config/wayvnc/config"
pct exec "$CTID" -- cat /home/waydroid/.config/wayvnc/config 2>&1 || echo "ERROR: Config file not found!"
echo ""

echo "=== STEP 2: Check File Permissions ==="
pct exec "$CTID" -- ls -la /home/waydroid/.config/wayvnc/config 2>&1 || echo "ERROR: Cannot stat file"
echo ""

echo "=== STEP 3: Check ALL Possible Config Locations ==="
pct exec "$CTID" -- bash <<'INNER'
echo "Checking /home/waydroid/.config/wayvnc/:"
ls -la /home/waydroid/.config/wayvnc/ 2>/dev/null || echo "  Directory doesn't exist"

echo ""
echo "Checking /etc/wayvnc/:"
ls -la /etc/wayvnc/ 2>/dev/null || echo "  Directory doesn't exist"

echo ""
echo "Checking /etc/wayvnc/:"
ls -la /etc/wayvnc/ 2>/dev/null || echo "  Directory doesn't exist"

echo ""
echo "Checking XDG_CONFIG_HOME:"
echo "  XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-not set}"
if [ -n "$XDG_CONFIG_HOME" ]; then
    ls -la "$XDG_CONFIG_HOME/wayvnc/" 2>/dev/null || echo "  No wayvnc dir in XDG_CONFIG_HOME"
fi

echo ""
echo "Searching for ANY wayvnc config files:"
find /home /root /etc -name "config" -path "*/wayvnc/*" 2>/dev/null || echo "  No config files found"
INNER
echo ""

echo "=== STEP 4: Check Current WayVNC Process ==="
echo "Process details:"
pct exec "$CTID" -- ps aux | grep -E "[w]ayvnc" || echo "  No wayvnc process running"
echo ""

echo "Command line from /proc:"
pct exec "$CTID" -- bash -c 'WAYVNC_PID=$(pgrep wayvnc 2>/dev/null | head -1); if [ -n "$WAYVNC_PID" ]; then cat /proc/$WAYVNC_PID/cmdline | tr "\0" " " | sed "s/ $/\n/"; else echo "  No wayvnc process"; fi'
echo ""

echo "=== STEP 5: Check WayVNC Version and Supported Options ==="
pct exec "$CTID" -- wayvnc --version 2>&1
echo ""
pct exec "$CTID" -- wayvnc --help 2>&1 | head -50
echo ""

echo "=== STEP 6: Check Service Status and Logs ==="
echo "Service status:"
pct exec "$CTID" -- systemctl status waydroid-vnc.service --no-pager -l 2>&1 | head -30 || echo "  Service not found or not using systemd"
echo ""

echo "Checking log file at /var/log/waydroid-wayvnc.log:"
pct exec "$CTID" -- bash <<'INNER'
if [ -f /var/log/waydroid-wayvnc.log ]; then
    echo "File exists. Size: $(stat -c%s /var/log/waydroid-wayvnc.log) bytes"
    echo "Permissions: $(stat -c%A /var/log/waydroid-wayvnc.log)"
    echo "Owner: $(stat -c%U:%G /var/log/waydroid-wayvnc.log)"
    echo ""
    echo "Last 30 lines:"
    tail -30 /var/log/waydroid-wayvnc.log
    if [ ! -s /var/log/waydroid-wayvnc.log ]; then
        echo "WARNING: Log file is EMPTY (0 bytes)"
    fi
else
    echo "ERROR: Log file does not exist!"
fi
INNER
echo ""

echo "=== STEP 7: Check Startup Script ==="
echo "Current startup script:"
pct exec "$CTID" -- cat /usr/local/bin/start-waydroid.sh 2>/dev/null || echo "  Startup script not found"
echo ""

echo "=== STEP 8: Stop Service and Test WayVNC Manually ==="
echo "Stopping service..."
pct exec "$CTID" -- systemctl stop waydroid-vnc.service 2>/dev/null || echo "  (Service may not be running)"
sleep 2

echo "Killing any remaining processes..."
pct exec "$CTID" -- pkill -9 wayvnc 2>/dev/null || true
sleep 2

echo ""
echo "Testing WayVNC with verbose output (15 second test)..."
pct exec "$CTID" -- bash <<'INNER'
DISPLAY_UID=$(id -u waydroid)
DISPLAY_XDG_RUNTIME_DIR="/run/user/$DISPLAY_UID"

# Find Wayland socket
WAYLAND_DISPLAY=""
for socket in "$DISPLAY_XDG_RUNTIME_DIR"/wayland-*; do
    if [ -S "$socket" ]; then
        WAYLAND_DISPLAY=$(basename "$socket")
        echo "Found Wayland socket: $WAYLAND_DISPLAY"
        break
    fi
done

if [ -z "$WAYLAND_DISPLAY" ]; then
    echo "ERROR: No Wayland socket found!"
    exit 1
fi

echo ""
echo "Running: XDG_RUNTIME_DIR=$DISPLAY_XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY wayvnc -C /home/waydroid/.config/wayvnc/config -v"
echo ""

# Run as waydroid user with timeout
timeout 15 su - waydroid -c "XDG_RUNTIME_DIR=$DISPLAY_XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY wayvnc -C /home/waydroid/.config/wayvnc/config -v 2>&1" || echo ""
echo ""
echo "(Test ended after 15 seconds)"
INNER
echo ""

echo "=== STEP 9: Test Without Config File ==="
echo "Testing WayVNC with command-line args only (no config file)..."
pct exec "$CTID" -- bash <<'INNER'
DISPLAY_UID=$(id -u waydroid)
DISPLAY_XDG_RUNTIME_DIR="/run/user/$DISPLAY_UID"

WAYLAND_DISPLAY=""
for socket in "$DISPLAY_XDG_RUNTIME_DIR"/wayland-*; do
    if [ -S "$socket" ]; then
        WAYLAND_DISPLAY=$(basename "$socket")
        break
    fi
done

if [ -n "$WAYLAND_DISPLAY" ]; then
    echo "Running: wayvnc 0.0.0.0 5900"
    timeout 10 su - waydroid -c "XDG_RUNTIME_DIR=$DISPLAY_XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY wayvnc 0.0.0.0 5900 2>&1" || echo ""
    echo ""
    echo "(Test ended after 10 seconds)"
fi
INNER
echo ""

echo "=== STEP 10: Check WayVNC Binary for Compiled Defaults ==="
echo "Checking for authentication-related strings in binary:"
pct exec "$CTID" -- strings /bin/wayvnc 2>/dev/null | grep -i "auth\|security\|password\|enable_auth" | head -30 || echo "  Could not read binary"
echo ""

echo "=== STEP 11: Check for TLS/Security Settings ==="
pct exec "$CTID" -- bash <<'INNER'
echo "Checking for TLS-related files:"
find /home/waydroid/.config/wayvnc /etc/wayvnc /etc/wayvnc -name "*.pem" -o -name "*.crt" -o -name "*.key" 2>/dev/null || echo "  No TLS files found"
INNER
echo ""

echo "=== STEP 12: Test Connection from Container ==="
echo "Checking if port 5900 is listening:"
pct exec "$CTID" -- ss -tlnp | grep 5900 || echo "  Port 5900 is NOT listening"
echo ""

echo "========================================"
echo "Investigation Complete"
echo "========================================"
echo ""
echo "NEXT STEPS:"
echo "1. Check the verbose output from Step 8 for any errors"
echo "2. Look for 'security-type' or 'enable_auth' messages"
echo "3. Compare behavior with/without config file (Steps 8 vs 9)"
echo "4. Check if log file is truly empty despite redirect"
echo ""
echo "Restarting service..."
pct exec "$CTID" -- systemctl start waydroid-vnc.service 2>/dev/null || echo "  Could not start service"
echo ""
echo "Script complete."
