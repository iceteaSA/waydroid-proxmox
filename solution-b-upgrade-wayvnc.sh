#!/bin/bash
# Solution B: Upgrade WayVNC to latest version (0.8.0+)
# This is the PROPER FIX - takes 15-20 minutes

set -e
CTID=103

echo "========================================"
echo "Solution B: Upgrade WayVNC to 0.8.0+"
echo "========================================"
echo ""

echo "WARNING: This will compile WayVNC from source"
echo "Estimated time: 15-20 minutes"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted"
    exit 1
fi

echo "Step 1: Stop WayVNC service..."
pct exec "$CTID" -- systemctl stop waydroid-vnc.service
sleep 2

echo "Step 2: Install build dependencies..."
pct exec "$CTID" -- bash <<'INNER'
apt-get update
apt-get install -y \
    build-essential \
    meson \
    ninja-build \
    pkg-config \
    libdrm-dev \
    libgbm-dev \
    libpixman-1-dev \
    libturbojpeg0-dev \
    libaml-dev \
    libpam0g-dev \
    libxkbcommon-dev \
    libjansson-dev \
    libgnutls28-dev \
    git
INNER

echo "Step 3: Clone and build neatvnc (dependency)..."
pct exec "$CTID" -- bash <<'INNER'
cd /tmp
rm -rf neatvnc
git clone https://github.com/any1/neatvnc.git
cd neatvnc
git checkout v0.8.1
meson build
ninja -C build
ninja -C build install
ldconfig
INNER

echo "Step 4: Clone and build WayVNC..."
pct exec "$CTID" -- bash <<'INNER'
cd /tmp
rm -rf wayvnc
git clone https://github.com/any1/wayvnc.git
cd wayvnc
git checkout v0.8.0
meson build
ninja -C build
ninja -C build install
ldconfig
INNER

echo "Step 5: Verify new version..."
NEW_VERSION=$(pct exec "$CTID" -- wayvnc --version 2>&1)
echo "New WayVNC version: $NEW_VERSION"

echo "Step 6: Update config with enable_auth=false..."
pct exec "$CTID" -- bash <<'INNER'
cat > /home/waydroid/.config/wayvnc/config <<'EOF'
address=0.0.0.0
port=5900
enable_auth=false
EOF
chown waydroid:waydroid /home/waydroid/.config/wayvnc/config
chmod 644 /home/waydroid/.config/wayvnc/config
INNER

echo "Step 7: Remove password file if exists..."
pct exec "$CTID" -- rm -f /home/waydroid/.config/wayvnc/password || true

echo "Step 8: Restart service..."
pct exec "$CTID" -- systemctl start waydroid-vnc.service
sleep 5

echo ""
echo "========================================"
echo "✓ WayVNC Upgraded Successfully"
echo "========================================"
echo ""
echo "New version: $NEW_VERSION"
echo "Container IP: 10.1.3.136"
echo ""
echo "Connect with (NO PASSWORD):"
echo "  vncviewer 10.1.3.136:5900"
echo ""

# Test connection
echo "Testing connection..."
vncviewer 10.1.3.136:5900 || true
