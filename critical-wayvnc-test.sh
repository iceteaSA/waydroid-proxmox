#!/bin/bash
# Critical diagnostic to determine if WayVNC 0.5.0 supports enable_auth option

set -e
CTID=103

echo "========================================"
echo "CRITICAL WayVNC 0.5.0 Capability Test"
echo "========================================"
echo ""

echo "=== TEST 1: WayVNC Version ==="
pct exec "$CTID" -- wayvnc --version 2>&1
echo ""

echo "=== TEST 2: WayVNC Help Output (checking for -C flag) ==="
pct exec "$CTID" -- wayvnc --help 2>&1 | head -40
echo ""

echo "=== TEST 3: Does 'enable_auth' string exist in binary? ==="
echo "This is THE SMOKING GUN test - if no output, option doesn't exist!"
pct exec "$CTID" -- bash -c 'strings $(which wayvnc) | grep -i "enable_auth"' 2>&1 || echo ">>> NOT FOUND - enable_auth option does NOT exist in this version! <<<"
echo ""

echo "=== TEST 4: Current Config File Content ==="
pct exec "$CTID" -- cat /home/waydroid/.config/wayvnc/config 2>&1
echo ""

echo "=== TEST 5: Run WayVNC Manually to See Actual Output ==="
echo "Stopping service..."
pct exec "$CTID" -- systemctl stop waydroid-vnc.service
sleep 3

echo ""
echo "Test 5a: Running WayVNC WITH -C flag (current approach):"
pct exec "$CTID" -- bash <<'INNER'
export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-1
timeout 8 su -c "XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 wayvnc -C /home/waydroid/.config/wayvnc/config -v 0.0.0.0 5900" waydroid 2>&1 || true
INNER

echo ""
echo "Test 5b: Running WayVNC WITHOUT config (plain command):"
pct exec "$CTID" -- bash <<'INNER'
export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-1
timeout 8 su -c "XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 wayvnc 0.0.0.0 5900" waydroid 2>&1 || true
INNER

echo ""
echo "Restarting service..."
pct exec "$CTID" -- systemctl start waydroid-vnc.service
sleep 5

echo ""
echo "=== TEST 6: What Security Types is WayVNC Offering? ==="
echo "Attempting VNC connection to capture security type negotiation..."
timeout 5 vncviewer -SecurityTypes None 10.1.3.136:5900 2>&1 || true

echo ""
echo "========================================"
echo "DIAGNOSTIC COMPLETE"
echo "========================================"
echo ""
echo "KEY FINDINGS:"
echo "1. If TEST 3 shows 'NOT FOUND' -> enable_auth option doesn't exist in WayVNC 0.5.0"
echo "2. If TEST 5a/5b show parse errors -> config file syntax not supported"
echo "3. If TEST 6 shows 'No matching security types' -> WayVNC requires auth regardless of config"
echo ""
echo "SOLUTIONS:"
echo "A. Use password auth (quick): echo 'password123' > /home/waydroid/.config/wayvnc/password"
echo "B. Upgrade to WayVNC 0.8.0+ (proper): Downloads from wayvnc GitHub releases"
echo "C. Try different VNC client: vncviewer -SecurityTypes VeNCrypt,TLSNone,None 10.1.3.136:5900"
