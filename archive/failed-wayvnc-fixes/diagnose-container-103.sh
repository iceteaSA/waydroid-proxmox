#!/bin/bash
# Comprehensive diagnostic script for container 103
# This pulls ALL relevant logs and status information

set +e  # Don't exit on errors - we want to collect all info

CTID=103
echo "=========================================="
echo "DIAGNOSTIC REPORT FOR CONTAINER $CTID"
echo "Time: $(date)"
echo "=========================================="
echo ""

echo "=========================================="
echo "1. CONTAINER STATUS"
echo "=========================================="
pct status $CTID
echo ""

echo "=========================================="
echo "2. WAYDROID-VNC SERVICE STATUS"
echo "=========================================="
pct exec $CTID -- systemctl status waydroid-vnc.service --no-pager -l
echo ""

echo "=========================================="
echo "3. LAST 100 LINES OF SERVICE LOGS"
echo "=========================================="
pct exec $CTID -- journalctl -u waydroid-vnc.service -n 100 --no-pager
echo ""

echo "=========================================="
echo "4. CURRENT STARTUP SCRIPT"
echo "=========================================="
echo "--- /usr/local/bin/start-waydroid.sh ---"
pct exec $CTID -- cat /usr/local/bin/start-waydroid.sh
echo ""

echo "=========================================="
echo "5. SYSTEMD SERVICE FILE"
echo "=========================================="
echo "--- /etc/systemd/system/waydroid-vnc.service ---"
pct exec $CTID -- cat /etc/systemd/system/waydroid-vnc.service
echo ""

echo "=========================================="
echo "6. PORT 5900 STATUS"
echo "=========================================="
pct exec $CTID -- ss -tlnp | grep 5900 || echo "Port 5900 NOT listening"
echo ""

echo "=========================================="
echo "7. RUNNING PROCESSES"
echo "=========================================="
echo "--- Sway processes ---"
pct exec $CTID -- ps aux | grep -E "sway" | grep -v grep || echo "No sway processes"
echo ""
echo "--- WayVNC processes ---"
pct exec $CTID -- ps aux | grep -E "wayvnc" | grep -v grep || echo "No wayvnc processes"
echo ""
echo "--- Waydroid processes ---"
pct exec $CTID -- ps aux | grep -E "waydroid" | grep -v grep || echo "No waydroid processes"
echo ""

echo "=========================================="
echo "8. WAYDROID USER INFO"
echo "=========================================="
pct exec $CTID -- id waydroid 2>/dev/null || echo "waydroid user does not exist"
pct exec $CTID -- ls -la /run/user/\$(id -u waydroid 2>/dev/null) 2>/dev/null || echo "No runtime dir for waydroid user"
echo ""

echo "=========================================="
echo "9. WAYLAND SOCKETS"
echo "=========================================="
pct exec $CTID -- bash -c 'for dir in /run/user/*/; do echo "=== $dir ==="; ls -la "$dir"wayland-* 2>/dev/null || echo "No wayland sockets"; done'
echo ""

echo "=========================================="
echo "10. RECENT SYSTEM ERRORS"
echo "=========================================="
pct exec $CTID -- journalctl -p err -n 50 --no-pager
echo ""

echo "=========================================="
echo "DIAGNOSTIC COMPLETE"
echo "=========================================="
