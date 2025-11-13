#!/bin/bash
# Test Different Methods to Disable WayVNC Authentication
# Run this after investigation to try various approaches

set -e

CTID=103

echo "========================================"
echo "Testing WayVNC No-Auth Methods"
echo "========================================"
echo ""

echo "Stopping service and killing processes..."
pct exec "$CTID" -- systemctl stop waydroid-vnc.service 2>/dev/null || true
pct exec "$CTID" -- pkill -9 wayvnc 2>/dev/null || true
sleep 3

# Get Wayland environment
ENV_CMD='
DISPLAY_UID=$(id -u waydroid)
DISPLAY_XDG_RUNTIME_DIR="/run/user/$DISPLAY_UID"
WAYLAND_DISPLAY=""
for socket in "$DISPLAY_XDG_RUNTIME_DIR"/wayland-*; do
    if [ -S "$socket" ]; then
        WAYLAND_DISPLAY=$(basename "$socket")
        break
    fi
done
if [ -z "$WAYLAND_DISPLAY" ]; then
    echo "ERROR: No Wayland socket found"
    exit 1
fi
export XDG_RUNTIME_DIR="$DISPLAY_XDG_RUNTIME_DIR"
export WAYLAND_DISPLAY="$WAYLAND_DISPLAY"
echo "Using: XDG_RUNTIME_DIR=$DISPLAY_XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
'

echo "=== METHOD 1: Command-line Only (No Config) ==="
echo "Testing: wayvnc 0.0.0.0 5900"
pct exec "$CTID" -- bash -c "$ENV_CMD
timeout 8 su - waydroid -c \"wayvnc 0.0.0.0 5900 2>&1\" || true
" &
sleep 5
pct exec "$CTID" -- ss -tlnp | grep 5900 && echo "SUCCESS: Port listening" || echo "FAILED: Port not listening"
pct exec "$CTID" -- pkill -9 wayvnc 2>/dev/null || true
sleep 2
echo ""

echo "=== METHOD 2: Using Config File with -C Flag ==="
echo "Config content:"
pct exec "$CTID" -- cat /home/waydroid/.config/wayvnc/config
echo ""
echo "Testing: wayvnc -C /home/waydroid/.config/wayvnc/config"
pct exec "$CTID" -- bash -c "$ENV_CMD
timeout 8 su - waydroid -c \"wayvnc -C /home/waydroid/.config/wayvnc/config 2>&1\" || true
" &
sleep 5
pct exec "$CTID" -- ss -tlnp | grep 5900 && echo "SUCCESS: Port listening" || echo "FAILED: Port not listening"
pct exec "$CTID" -- pkill -9 wayvnc 2>/dev/null || true
sleep 2
echo ""

echo "=== METHOD 3: Config with Explicit Address/Port ==="
echo "Testing: wayvnc -C /home/waydroid/.config/wayvnc/config 0.0.0.0 5900"
pct exec "$CTID" -- bash -c "$ENV_CMD
timeout 8 su - waydroid -c \"wayvnc -C /home/waydroid/.config/wayvnc/config 0.0.0.0 5900 2>&1\" || true
" &
sleep 5
pct exec "$CTID" -- ss -tlnp | grep 5900 && echo "SUCCESS: Port listening" || echo "FAILED: Port not listening"
pct exec "$CTID" -- pkill -9 wayvnc 2>/dev/null || true
sleep 2
echo ""

echo "=== METHOD 4: Create Password and Use Auth ==="
echo "Creating password file..."
pct exec "$CTID" -- bash -c '
mkdir -p /home/waydroid/.config/wayvnc
echo "testpass123" > /home/waydroid/.config/wayvnc/password
chown -R waydroid:waydroid /home/waydroid/.config/wayvnc
chmod 600 /home/waydroid/.config/wayvnc/password
echo "Password file created: testpass123"
'

echo "Updating config to include password_file..."
pct exec "$CTID" -- bash -c 'cat > /home/waydroid/.config/wayvnc/config <<CFGEOF
address=0.0.0.0
port=5900
password_file=/home/waydroid/.config/wayvnc/password
CFGEOF
cat /home/waydroid/.config/wayvnc/config
'

echo ""
echo "Testing with password auth..."
pct exec "$CTID" -- bash -c "$ENV_CMD
timeout 8 su - waydroid -c \"wayvnc -C /home/waydroid/.config/wayvnc/config 2>&1\" || true
" &
sleep 5
pct exec "$CTID" -- ss -tlnp | grep 5900 && echo "SUCCESS: Port listening (try password: testpass123)" || echo "FAILED: Port not listening"
pct exec "$CTID" -- pkill -9 wayvnc 2>/dev/null || true
sleep 2
echo ""

echo "=== METHOD 5: Try Different Config Syntax ==="
echo "Testing alternate config formats..."

# Test 1: YAML-style
pct exec "$CTID" -- bash -c 'cat > /tmp/wayvnc-test1.config <<CFGEOF
address: 0.0.0.0
port: 5900
enable_auth: false
CFGEOF
'
echo "Format 1 (YAML style): enable_auth: false"
pct exec "$CTID" -- bash -c "$ENV_CMD
timeout 8 su - waydroid -c \"wayvnc -C /tmp/wayvnc-test1.config 2>&1\" || true
" &
sleep 5
pct exec "$CTID" -- ss -tlnp | grep 5900 && echo "SUCCESS: Port listening" || echo "FAILED: Port not listening"
pct exec "$CTID" -- pkill -9 wayvnc 2>/dev/null || true
sleep 2

# Test 2: No auth line
pct exec "$CTID" -- bash -c 'cat > /tmp/wayvnc-test2.config <<CFGEOF
address=0.0.0.0
port=5900
CFGEOF
'
echo ""
echo "Format 2 (no auth line at all):"
pct exec "$CTID" -- bash -c "$ENV_CMD
timeout 8 su - waydroid -c \"wayvnc -C /tmp/wayvnc-test2.config 2>&1\" || true
" &
sleep 5
pct exec "$CTID" -- ss -tlnp | grep 5900 && echo "SUCCESS: Port listening" || echo "FAILED: Port not listening"
pct exec "$CTID" -- pkill -9 wayvnc 2>/dev/null || true
sleep 2
echo ""

echo "=== METHOD 6: Check if VNC Client Issue ==="
echo "Starting WayVNC one more time and testing connection..."
pct exec "$CTID" -- bash -c "$ENV_CMD
nohup su - waydroid -c \"wayvnc 0.0.0.0 5900 > /tmp/wayvnc.log 2>&1 &\" &
sleep 5
ss -tlnp | grep 5900
"

CONTAINER_IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
echo ""
echo "Port status:"
pct exec "$CTID" -- ss -tlnp | grep 5900 || echo "Not listening"
echo ""
echo "WayVNC output:"
pct exec "$CTID" -- cat /tmp/wayvnc.log 2>/dev/null || echo "No log"
echo ""

echo "Try connecting now with: vncviewer $CONTAINER_IP:5900"
echo "If you get 'No matching security types', WayVNC 0.5.0 may not support no-auth mode"
echo ""
echo "Press Ctrl+C to stop, or wait 30 seconds..."
sleep 30

pct exec "$CTID" -- pkill -9 wayvnc 2>/dev/null || true
echo ""
echo "========================================"
echo "Test Complete"
echo "========================================"
echo ""
echo "RESULTS SUMMARY:"
echo "- Method that worked: [observe which one had port listening]"
echo "- If none worked, WayVNC 0.5.0 may require authentication"
echo "- Check /tmp/wayvnc.log for error messages"
echo ""
echo "Restarting service..."
pct exec "$CTID" -- systemctl start waydroid-vnc.service 2>/dev/null || true
