#!/usr/bin/env bash
#
# WayVNC Debug Script for LXC Container 103
# Run from Proxmox host to diagnose WayVNC startup issues
#
# Usage: ./debug-wayvnc.sh [container_id]
#

CTID="${1:-103}"

echo "========================================"
echo "WayVNC Debug Script for CT $CTID"
echo "========================================"
echo ""

# Test 1: Check if wayvnc binary exists and is executable
echo "[1/8] Checking if wayvnc binary exists..."
pct exec $CTID -- bash -c 'which wayvnc && ls -l $(which wayvnc) && file $(which wayvnc)'
echo ""

# Test 2: Check wayvnc version and help
echo "[2/8] Testing wayvnc binary execution..."
pct exec $CTID -- bash -c 'wayvnc --version 2>&1 || echo "Version check failed: $?"'
pct exec $CTID -- bash -c 'wayvnc --help 2>&1 | head -20'
echo ""

# Test 3: Check waydroid user environment
echo "[3/8] Checking waydroid user setup..."
pct exec $CTID -- bash -c 'id waydroid && groups waydroid'
pct exec $CTID -- bash -c 'ls -la /home/waydroid/.config/wayvnc/ 2>&1'
echo ""

# Test 4: Check Wayland socket
echo "[4/8] Checking Wayland socket..."
pct exec $CTID -- bash -c 'DISPLAY_UID=$(id -u waydroid); ls -la /run/user/$DISPLAY_UID/ 2>&1 | grep wayland'
echo ""

# Test 5: Check WayVNC config files
echo "[5/8] Checking WayVNC configuration..."
pct exec $CTID -- bash -c 'cat /home/waydroid/.config/wayvnc/config 2>&1'
pct exec $CTID -- bash -c 'ls -la /home/waydroid/.config/wayvnc/password 2>&1 && echo "Password file exists"'
echo ""

# Test 6: Test running wayvnc manually with verbose output
echo "[6/8] Testing WayVNC startup manually (5 second test)..."
pct exec $CTID -- bash -c '
DISPLAY_USER="waydroid"
DISPLAY_UID=$(id -u $DISPLAY_USER)
export DISPLAY_XDG_RUNTIME_DIR="/run/user/$DISPLAY_UID"

# Find Wayland socket
WAYLAND_DISPLAY=""
for socket in "$DISPLAY_XDG_RUNTIME_DIR"/wayland-*; do
    if [ -S "$socket" ]; then
        WAYLAND_DISPLAY=$(basename "$socket")
        echo "Found Wayland socket: $WAYLAND_DISPLAY at $socket"
        break
    fi
done

if [ -z "$WAYLAND_DISPLAY" ]; then
    echo "ERROR: No Wayland socket found in $DISPLAY_XDG_RUNTIME_DIR"
    exit 1
fi

# Try to run wayvnc as waydroid user with full environment
echo "Running: su -c \"XDG_RUNTIME_DIR=$DISPLAY_XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY wayvnc 0.0.0.0 5900\" $DISPLAY_USER"
timeout 5 su -c "XDG_RUNTIME_DIR=$DISPLAY_XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY wayvnc 0.0.0.0 5900" $DISPLAY_USER 2>&1 || true
'
echo ""

# Test 7: Check if authentication can be disabled
echo "[7/8] Testing WayVNC without authentication..."
pct exec $CTID -- bash -c '
# Backup config
cp /home/waydroid/.config/wayvnc/config /home/waydroid/.config/wayvnc/config.backup 2>/dev/null || true

# Create minimal config without auth
cat > /tmp/wayvnc-test.config <<EOF
address=0.0.0.0
port=5900
enable_auth=false
max_rate=60
EOF

DISPLAY_USER="waydroid"
DISPLAY_UID=$(id -u $DISPLAY_USER)
export DISPLAY_XDG_RUNTIME_DIR="/run/user/$DISPLAY_UID"

WAYLAND_DISPLAY=""
for socket in "$DISPLAY_XDG_RUNTIME_DIR"/wayland-*; do
    if [ -S "$socket" ]; then
        WAYLAND_DISPLAY=$(basename "$socket")
        break
    fi
done

if [ -n "$WAYLAND_DISPLAY" ]; then
    echo "Testing with config file: /tmp/wayvnc-test.config (no auth)"
    timeout 5 su -c "XDG_RUNTIME_DIR=$DISPLAY_XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY wayvnc -C /tmp/wayvnc-test.config 0.0.0.0 5900" $DISPLAY_USER 2>&1 || true
fi
'
echo ""

# Test 8: Check library dependencies
echo "[8/8] Checking WayVNC library dependencies..."
pct exec $CTID -- bash -c 'ldd $(which wayvnc) 2>&1 | grep -i "not found" || echo "All libraries found"'
echo ""

echo "========================================"
echo "Debug Complete"
echo "========================================"
echo ""
echo "Next Steps:"
echo "1. Review the output above for errors"
echo "2. If wayvnc starts in test 6/7, the issue is with the systemd service"
echo "3. If wayvnc shows 'not found' libraries, install missing packages"
echo "4. If authentication is the issue, try running with enable_auth=false"
echo ""
