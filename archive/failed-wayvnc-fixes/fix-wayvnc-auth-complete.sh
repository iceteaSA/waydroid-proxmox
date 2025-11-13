#!/bin/bash
# Complete fix for WayVNC authentication - kills old processes and restarts cleanly

set -e

CTID=103

echo "=== Complete WayVNC Authentication Fix ==="
echo ""

# Step 1: Stop service and kill all processes
echo "Step 1: Stopping service and killing all WayVNC/Sway processes..."
pct exec "$CTID" -- systemctl stop waydroid-vnc.service
sleep 2
pct exec "$CTID" -- pkill -9 wayvnc || true
pct exec "$CTID" -- pkill -9 sway || true
sleep 3
echo "✓ All processes killed"
echo ""

# Step 2: Clean up config files
echo "Step 2: Cleaning up all auth-related files..."
pct exec "$CTID" -- bash <<'EOF'
# Remove ALL password/auth files
rm -rf /home/waydroid/.config/wayvnc/* 2>/dev/null || true
rm -rf /root/.config/wayvnc/* 2>/dev/null || true
rm -f /root/vnc-password.txt 2>/dev/null || true

# Create clean directories
mkdir -p /home/waydroid/.config/wayvnc

# Create minimal no-auth config
cat > /home/waydroid/.config/wayvnc/config <<'ENDCONFIG'
address=0.0.0.0
port=5900
ENDCONFIG

# Set permissions
chown -R waydroid:waydroid /home/waydroid/.config/wayvnc
chmod 644 /home/waydroid/.config/wayvnc/config

echo "✓ Clean config created"
cat /home/waydroid/.config/wayvnc/config
EOF
echo ""

# Step 3: Restart service
echo "Step 3: Starting waydroid-vnc service..."
pct exec "$CTID" -- systemctl start waydroid-vnc.service
echo "Waiting 20 seconds for startup..."
sleep 20
echo ""

# Step 4: Verification
echo "=== VERIFICATION ==="
echo ""

echo "Service Status:"
pct exec "$CTID" -- systemctl status waydroid-vnc.service --no-pager -l || true
echo ""

echo "Port 5900 Status:"
pct exec "$CTID" -- ss -tlnp | grep 5900 || echo "ERROR: Port not listening!"
echo ""

echo "WayVNC Processes:"
pct exec "$CTID" -- ps aux | grep -E "[w]ayvnc" || echo "No wayvnc processes"
echo ""

echo "WayVNC Log (last 10 lines):"
pct exec "$CTID" -- tail -10 /var/log/waydroid-wayvnc.log 2>/dev/null || echo "No log file"
echo ""

CONTAINER_IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
echo "=== CONNECTION INFO ==="
echo "Container IP: $CONTAINER_IP"
echo "Connect with: vncviewer $CONTAINER_IP:5900"
echo "NO PASSWORD - just press Enter when prompted"
echo ""
echo "Fix complete!"
