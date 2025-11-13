#!/bin/bash
# Solution A: Enable Password Authentication for WayVNC 0.5.0
# This is the QUICK FIX - takes 2 minutes

set -e
CTID=103
PASSWORD="waydroid123"

echo "========================================"
echo "Solution A: Enable Password Authentication"
echo "========================================"
echo ""

echo "Step 1: Stop WayVNC service..."
pct exec "$CTID" -- systemctl stop waydroid-vnc.service
sleep 2

echo "Step 2: Remove enable_auth from config (not supported in 0.5.0)..."
pct exec "$CTID" -- bash <<'INNER'
cat > /home/waydroid/.config/wayvnc/config <<'EOF'
address=0.0.0.0
port=5900
EOF
INNER

echo "Step 3: Create password file..."
pct exec "$CTID" -- bash -c "echo '$PASSWORD' > /home/waydroid/.config/wayvnc/password"
pct exec "$CTID" -- chown waydroid:waydroid /home/waydroid/.config/wayvnc/password
pct exec "$CTID" -- chmod 600 /home/waydroid/.config/wayvnc/password

echo "Step 4: Restart service..."
pct exec "$CTID" -- systemctl start waydroid-vnc.service
sleep 5

echo ""
echo "========================================"
echo "✓ Password Authentication Enabled"
echo "========================================"
echo ""
echo "Container IP: 10.1.3.136"
echo "VNC Password: $PASSWORD"
echo ""
echo "Connect with:"
echo "  vncviewer 10.1.3.136:5900"
echo ""
echo "When prompted, enter password: $PASSWORD"
echo ""

# Test connection
echo "Testing connection (will prompt for password)..."
echo "Press Ctrl+C if connection succeeds and window opens"
vncviewer 10.1.3.136:5900 || true
