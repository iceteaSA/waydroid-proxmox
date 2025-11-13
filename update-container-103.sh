#!/bin/bash
# Update Container 103 with Fixed WayVNC Startup Script

set -e

CTID=103

echo "Updating container $CTID with fixed startup script..."

# Extract the startup script from install/waydroid-install.sh and deploy to container
pct exec $CTID -- bash -c 'cat > /usr/local/bin/start-waydroid.sh' <<'EOFSCRIPT'
#!/bin/bash
# Start Waydroid with VNC access

set -e

# Setup environment for waydroid user (compositor runs as non-root)
DISPLAY_USER="waydroid"
DISPLAY_UID=$(id -u $DISPLAY_USER)
DISPLAY_GID=$(id -g $DISPLAY_USER)
export DISPLAY_XDG_RUNTIME_DIR="/run/user/$DISPLAY_UID"

# Create runtime directory for waydroid user
mkdir -p "$DISPLAY_XDG_RUNTIME_DIR"
chown $DISPLAY_USER:$DISPLAY_USER "$DISPLAY_XDG_RUNTIME_DIR"
chmod 700 "$DISPLAY_XDG_RUNTIME_DIR"

# Also setup root's XDG_RUNTIME_DIR for Waydroid
export XDG_RUNTIME_DIR=/run/user/0
mkdir -p $XDG_RUNTIME_DIR

# Start DBus session for waydroid user if not running
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    # Start dbus as the waydroid user
    su -c "dbus-launch --sh-syntax" $DISPLAY_USER > /tmp/dbus-session.env
    source /tmp/dbus-session.env
    echo "Started DBus session: $DBUS_SESSION_BUS_ADDRESS"
fi

# Load environment
[ -f /tmp/waydroid-env.sh ] && source /tmp/waydroid-env.sh

# GPU environment variables (will be passed to Sway)
GPU_TYPE="${GPU_TYPE:-software}"
SOFTWARE_RENDERING="${SOFTWARE_RENDERING:-1}"

# Start Sway compositor in headless mode as waydroid user
# NOTE: WayVNC requires a wlroots-based compositor (Sway works, Weston doesn't)
# NOTE: Sway refuses to run as root, so we run as waydroid user
echo "Starting Sway compositor as $DISPLAY_USER in headless mode..."

# Prepare environment for Sway (don't set WAYLAND_DISPLAY - let Sway choose)
SWAY_ENV="XDG_RUNTIME_DIR=$DISPLAY_XDG_RUNTIME_DIR WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1"

# Add GPU environment variables if needed
if [ "$SOFTWARE_RENDERING" != "1" ]; then
    case $GPU_TYPE in
        intel)
            SWAY_ENV="$SWAY_ENV MESA_LOADER_DRIVER_OVERRIDE=iris LIBVA_DRIVER_NAME=iHD"
            ;;
        amd)
            SWAY_ENV="$SWAY_ENV MESA_LOADER_DRIVER_OVERRIDE=radeonsi LIBVA_DRIVER_NAME=radeonsi"
            ;;
    esac
else
    SWAY_ENV="$SWAY_ENV LIBGL_ALWAYS_SOFTWARE=1 WLR_RENDERER_ALLOW_SOFTWARE=1"
fi

# Start Sway as waydroid user in background
su -c "$SWAY_ENV sway" $DISPLAY_USER &
SWAY_PID=$!

# Wait for Sway to create a Wayland socket (dynamically detect which one)
echo "Waiting for Wayland socket creation..."
RETRY_COUNT=0
MAX_RETRIES=30
WAYLAND_DISPLAY=""

while [ -z "$WAYLAND_DISPLAY" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    sleep 1
    RETRY_COUNT=$((RETRY_COUNT + 1))

    # Check for wayland-0, wayland-1, etc.
    for socket in "$DISPLAY_XDG_RUNTIME_DIR"/wayland-*; do
        if [ -S "$socket" ]; then
            WAYLAND_DISPLAY=$(basename "$socket")
            echo "Detected Wayland socket: $WAYLAND_DISPLAY"
            break
        fi
    done

    if [ -z "$WAYLAND_DISPLAY" ] && [ $((RETRY_COUNT % 5)) -eq 0 ]; then
        echo "Still waiting for Wayland socket in $DISPLAY_XDG_RUNTIME_DIR... ($RETRY_COUNT/$MAX_RETRIES)"
    fi
done

# Verify Sway started and socket exists
if ! kill -0 $SWAY_PID 2>/dev/null; then
    echo "ERROR: Sway failed to start"
    exit 1
fi

if [ -z "$WAYLAND_DISPLAY" ]; then
    echo "ERROR: No Wayland socket found in $DISPLAY_XDG_RUNTIME_DIR after ${MAX_RETRIES}s"
    echo "Checking DISPLAY_XDG_RUNTIME_DIR contents:"
    ls -la "$DISPLAY_XDG_RUNTIME_DIR/" || true
    kill $SWAY_PID 2>/dev/null || true
    exit 1
fi

export WAYLAND_DISPLAY
SOCKET_PATH="$DISPLAY_XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
echo "Wayland socket ready at $SOCKET_PATH"

# Make the Wayland socket accessible to root for Waydroid
# Create a symbolic link in root's XDG_RUNTIME_DIR
ln -sf "$SOCKET_PATH" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
chmod 777 "$SOCKET_PATH"

# Start WayVNC with authentication as waydroid user
echo "Starting WayVNC on port 5900 as $DISPLAY_USER..."
# WayVNC will connect to the Wayland socket via WAYLAND_DISPLAY environment variable
# Use nohup to prevent SIGHUP when su exits
WAYVNC_ENV="XDG_RUNTIME_DIR=$DISPLAY_XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
nohup su -c "$WAYVNC_ENV wayvnc 0.0.0.0 5900" $DISPLAY_USER > /dev/null 2>&1 &
sleep 3

# Verify WayVNC started by checking if port 5900 is listening
# Note: We can't check PID because nohup exits immediately
WAYVNC_RETRY=0
WAYVNC_MAX_RETRIES=10
WAYVNC_RUNNING=false
while [ $WAYVNC_RETRY -lt $WAYVNC_MAX_RETRIES ]; do
    if ss -tlnp | grep -q ':5900'; then
        WAYVNC_RUNNING=true
        break
    fi
    sleep 1
    WAYVNC_RETRY=$((WAYVNC_RETRY + 1))
done

if [ "$WAYVNC_RUNNING" = "false" ]; then
    echo "ERROR: WayVNC failed to start (port 5900 not listening)"
    echo "Checking WayVNC requirements:"
    echo "  WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
    echo "  Socket exists: $([ -S "$SOCKET_PATH" ] && echo 'yes' || echo 'no')"
    echo "  Sway running: $(kill -0 $SWAY_PID 2>/dev/null && echo 'yes' || echo 'no')"
    kill $SWAY_PID 2>/dev/null || true
    exit 1
fi

echo "WayVNC started successfully and connected to Sway"

# Initialize Waydroid if needed (this downloads ~450MB on first run)
if [ ! -d "/var/lib/waydroid/overlay" ]; then
    echo "Initializing Waydroid (downloading Android images, ~450MB)..."
    echo "This will take 5-10 minutes on first run..."
    # Run waydroid init as waydroid user
    INIT_ENV="XDG_RUNTIME_DIR=$DISPLAY_XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
    if [ "${USE_GAPPS:-yes}" = "yes" ]; then
        su -c "$INIT_ENV waydroid init -s GAPPS -f" $DISPLAY_USER
    else
        su -c "$INIT_ENV waydroid init -f" $DISPLAY_USER
    fi
fi

# Start Waydroid container as waydroid user
echo "Starting Waydroid container as $DISPLAY_USER..."
WAYDROID_ENV="XDG_RUNTIME_DIR=$DISPLAY_XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
su -c "$WAYDROID_ENV waydroid container start" $DISPLAY_USER

# Start Waydroid session as waydroid user
echo "Starting Waydroid session as $DISPLAY_USER..."
su -c "$WAYDROID_ENV waydroid session start" $DISPLAY_USER &
SESSION_PID=$!

echo "========================================"
echo "Waydroid started successfully!"
echo "VNC: Port 5900"
echo "Display User: $DISPLAY_USER"
echo "Sway PID: $SWAY_PID"
echo "Session PID: $SESSION_PID"
echo "Wayland Socket: $SOCKET_PATH"
echo "Root Access: $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY (symlink)"
echo "========================================"

# Keep the script running and monitor child processes
while true; do
    # Check if critical processes are still running
    if ! kill -0 $SWAY_PID 2>/dev/null; then
        echo "ERROR: Sway compositor died, exiting..."
        exit 1
    fi
    if ! ss -tlnp | grep -q ':5900'; then
        echo "ERROR: WayVNC died (port 5900 not listening), exiting..."
        exit 1
    fi

    sleep 10
done
EOFSCRIPT

# Make it executable
pct exec $CTID -- chmod +x /usr/local/bin/start-waydroid.sh

echo "✓ Startup script updated successfully"

# Stop any running wayvnc and sway processes
echo "Stopping old processes..."
pct exec $CTID -- pkill -9 wayvnc || true
pct exec $CTID -- pkill -9 sway || true
sleep 2

# Restart the service
echo "Restarting waydroid-vnc service..."
pct exec $CTID -- systemctl daemon-reload
pct exec $CTID -- systemctl restart waydroid-vnc.service

# Wait for service to start
echo "Waiting for service to start..."
sleep 15

# Check status
echo ""
echo "=========================================="
echo "SERVICE STATUS:"
echo "=========================================="
pct exec $CTID -- systemctl status waydroid-vnc.service --no-pager -l

echo ""
echo "=========================================="
echo "PORT CHECK:"
echo "=========================================="
pct exec $CTID -- ss -tlnp | grep 5900 || echo "WARNING: Port 5900 not listening yet"

echo ""
echo "=========================================="
echo "PROCESS CHECK:"
echo "=========================================="
pct exec $CTID -- ps aux | grep -E "(sway|wayvnc)" | grep -v grep || echo "No processes found"

echo ""
echo "=========================================="
CONTAINER_IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
echo "Container IP: $CONTAINER_IP"
echo "VNC Connection: vncviewer $CONTAINER_IP:5900"
echo "=========================================="
