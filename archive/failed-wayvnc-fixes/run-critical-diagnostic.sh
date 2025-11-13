#!/bin/bash
echo "=== CRITICAL TEST: Does WayVNC 0.5.0 support enable_auth option? ==="
echo ""

echo "1. WayVNC Version:"
ssh root@proxmox "pct exec 103 -- wayvnc --version" 2>&1
echo ""

echo "2. WayVNC Help (checking for -C and config options):"
ssh root@proxmox "pct exec 103 -- wayvnc --help" 2>&1 | head -30
echo ""

echo "3. Does 'enable_auth' exist in the WayVNC binary?"
ssh root@proxmox "pct exec 103 -- bash -c 'strings \$(which wayvnc) | grep -i enable_auth'" 2>&1 || echo "NOT FOUND - Option doesn't exist!"
echo ""

echo "4. Current config file content:"
ssh root@proxmox "pct exec 103 -- cat /home/waydroid/.config/wayvnc/config" 2>&1
echo ""

echo "5. Run WayVNC manually with verbose output:"
ssh root@proxmox "pct exec 103 -- bash" <<'INNER'
systemctl stop waydroid-vnc.service
sleep 2
export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-1
echo "Starting WayVNC with -C flag and timeout..."
timeout 5 su -c "XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 wayvnc -C /home/waydroid/.config/wayvnc/config -v 0.0.0.0 5900" waydroid 2>&1 || true
echo ""
echo "Starting WayVNC WITHOUT config file..."
timeout 5 su -c "XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 wayvnc 0.0.0.0 5900" waydroid 2>&1 || true
systemctl start waydroid-vnc.service
INNER
