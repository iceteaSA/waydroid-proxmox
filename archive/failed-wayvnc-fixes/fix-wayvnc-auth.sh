#!/bin/bash
# Quick fix for WayVNC authentication issue in container 103

set -e

CTID=103

echo "Fixing WayVNC authentication for container $CTID..."

# Remove old auth files and ensure no-auth mode
pct exec "$CTID" -- bash <<'EOF'
# Remove old password files
rm -f /home/waydroid/.config/wayvnc/password 2>/dev/null || true
rm -f /root/.config/wayvnc/password 2>/dev/null || true
rm -f /root/vnc-password.txt 2>/dev/null || true

# Create minimal config with no authentication
mkdir -p /home/waydroid/.config/wayvnc
cat > /home/waydroid/.config/wayvnc/config <<'ENDCONFIG'
address=0.0.0.0
port=5900
ENDCONFIG

chown -R waydroid:waydroid /home/waydroid/.config/wayvnc
chmod 644 /home/waydroid/.config/wayvnc/config

echo "✓ Removed authentication files"
echo "✓ Created no-auth config"

# Restart service
systemctl restart waydroid-vnc.service

echo "Waiting 15 seconds for service to start..."
sleep 15

# Verify
systemctl status waydroid-vnc.service --no-pager || true
ss -tlnp | grep 5900 || echo "Port 5900 not listening!"

echo ""
echo "Container IP: $(hostname -I | awk '{print $1}')"
echo "Try connecting now: vncviewer $(hostname -I | awk '{print $1}'):5900"
EOF

echo "Fix complete!"
