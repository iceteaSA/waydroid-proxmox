#!/bin/bash
# FINAL FIX for Container 103 WayVNC Issue
# This script has extensive logging and fixes BOTH sway and wayvnc SIGHUP issues

set -e

CTID=103
LOGFILE="/tmp/fix-container-103-$(date +%Y%m%d-%H%M%S).log"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log "=========================================="
log "STARTING FIX FOR CONTAINER $CTID"
log "Log file: $LOGFILE"
log "=========================================="

log "Step 1: Stop existing services and processes"
pct exec $CTID -- systemctl stop waydroid-vnc.service 2>&1 | tee -a "$LOGFILE" || log "Service already stopped"
pct exec $CTID -- pkill -9 wayvnc 2>&1 | tee -a "$LOGFILE" || log "No wayvnc to kill"
pct exec $CTID -- pkill -9 sway 2>&1 | tee -a "$LOGFILE" || log "No sway to kill"
sleep 3
log "✓ Cleanup complete"
log ""

log "Step 2: Deploying fixed startup script to /usr/local/bin/start-waydroid.sh"
pct exec $CTID -- bash -c 'cat > /usr/local/bin/start-waydroid.sh' <<'EOFSCRIPT'
#!/bin/bash
# Start Waydroid with VNC access
# FIXED VERSION - prevents SIGHUP for both sway and wayvnc

set -e

# Logging function
log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

log "=== Starting Waydroid VNC Service ==="

# Setup environment for waydroid user (compositor runs as non-root)
DISPLAY_USER="waydroid"
DISPLAY_UID=$(id -u $DISPLAY_USER)
DISPLAY_GID=$(id -g $DISPLAY_USER)
export DISPLAY_XDG_RUNTIME_DIR="/run/user/$DISPLAY_UID"

log "Display user: $DISPLAY_USER (UID: $DISPLAY_UID)"

# Create runtime directory for waydroid user
mkdir -p "$DISPLAY_XDG_RUNTIME_DIR"
chown $DISPLAY_USER:$DISPLAY_USER "$DISPLAY_XDG_RUNTIME_DIR"
chmod 700 "$DISPLAY_XDG_RUNTIME_DIR"
log "Created runtime directory: $DISPLAY_XDG_RUNTIME_DIR"

# Also setup root's XDG_RUNTIME_DIR for Waydroid
export XDG_RUNTIME_DIR=/run/user/0
mkdir -p $XDG_RUNTIME_DIR
log "Created root runtime directory: $XDG_RUNTIME_DIR"

# Load environment
[ -f /tmp/waydroid-env.sh ] && source /tmp/waydroid-env.sh

# GPU environment variables
GPU_TYPE="${GPU_TYPE:-software}"
SOFTWARE_RENDERING="${SOFTWARE_RENDERING:-1}"
log "GPU Type: $GPU_TYPE, Software Rendering: $SOFTWARE_RENDERING"

# Start Sway compositor in headless mode as waydroid user
log "Starting Sway compositor as $DISPLAY_USER in headless mode..."

# Prepare environment for Sway
SWAY_ENV="XDG_RUNTIME_DIR=$DISPLAY_XDG_RUNTIME_DIR WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1"

# Add GPU environment variables if needed
if [ "$SOFTWARE_RENDERING" != "1" ]; then
    case $GPU_TYPE in
        intel)
            SWAY_ENV="$SWAY_ENV MESA_LOADER_DRIVER_OVERRIDE=iris LIBVA_DRIVER_NAME=iHD"
            log "Using Intel GPU drivers"
            ;;
        amd)
            SWAY_ENV="$SWAY_ENV MESA_LOADER_DRIVER_OVERRIDE=radeonsi LIBVA_DRIVER_NAME=radeonsi"
            log "Using AMD GPU drivers"
            ;;
    esac
else
    SWAY_ENV="$SWAY_ENV LIBGL_ALWAYS_SOFTWARE=1 WLR_RENDERER_ALLOW_SOFTWARE=1"
    log "Using software rendering"
fi

# Start Sway with nohup to prevent SIGHUP
log "Launching Sway with nohup..."
nohup su -c "$SWAY_ENV sway" $DISPLAY_USER > /tmp/sway.log 2>&1 &
sleep 2

# Wait for Sway to create a Wayland socket
log "Waiting for Wayland socket creation..."
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
            log "✓ Detected Wayland socket: $WAYLAND_DISPLAY"
            break
        fi
    done

    if [ -z "$WAYLAND_DISPLAY" ] && [ $((RETRY_COUNT % 5)) -eq 0 ]; then
        log "Still waiting for Wayland socket... ($RETRY_COUNT/$MAX_RETRIES)"
    fi
done

# Verify Sway is running
SWAY_RUNNING=$(pgrep -u $DISPLAY_USER sway || echo "")
if [ -z "$SWAY_RUNNING" ]; then
    log "ERROR: Sway process not found"
    log "Sway log contents:"
    cat /tmp/sway.log 2>/dev/null || log "No sway log"
    exit 1
fi
log "✓ Sway is running (PID: $SWAY_RUNNING)"

if [ -z "$WAYLAND_DISPLAY" ]; then
    log "ERROR: No Wayland socket found after ${MAX_RETRIES}s"
    log "Contents of $DISPLAY_XDG_RUNTIME_DIR:"
    ls -la "$DISPLAY_XDG_RUNTIME_DIR/" || true
    exit 1
fi

export WAYLAND_DISPLAY
SOCKET_PATH="$DISPLAY_XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
log "✓ Wayland socket ready at $SOCKET_PATH"

# Make the Wayland socket accessible to root for Waydroid
ln -sf "$SOCKET_PATH" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
chmod 777 "$SOCKET_PATH"
log "✓ Created symlink for root access"

# Start WayVNC with nohup to prevent SIGHUP
log "Starting WayVNC on port 5900 as $DISPLAY_USER..."
WAYVNC_ENV="XDG_RUNTIME_DIR=$DISPLAY_XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
nohup su -c "$WAYVNC_ENV wayvnc 0.0.0.0 5900" $DISPLAY_USER > /tmp/wayvnc.log 2>&1 &
sleep 3

# Verify WayVNC started by checking port
log "Verifying WayVNC is listening on port 5900..."
WAYVNC_RETRY=0
WAYVNC_MAX_RETRIES=10
WAYVNC_RUNNING=false
while [ $WAYVNC_RETRY -lt $WAYVNC_MAX_RETRIES ]; do
    if ss -tlnp | grep -q ':5900'; then
        WAYVNC_RUNNING=true
        log "✓ Port 5900 is listening"
        break
    fi
    sleep 1
    WAYVNC_RETRY=$((WAYVNC_RETRY + 1))
done

if [ "$WAYVNC_RUNNING" = "false" ]; then
    log "ERROR: WayVNC failed to start (port 5900 not listening)"
    log "WayVNC requirements check:"
    log "  WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
    log "  Socket exists: $([ -S "$SOCKET_PATH" ] && echo 'yes' || echo 'no')"
    log "  Sway running: $(pgrep -u $DISPLAY_USER sway > /dev/null && echo 'yes' || echo 'no')"
    log "WayVNC log contents:"
    cat /tmp/wayvnc.log 2>/dev/null || log "No wayvnc log"
    exit 1
fi

log "✓ WayVNC started successfully"

# Initialize Waydroid if needed
if [ ! -d "/var/lib/waydroid/overlay" ]; then
    log "Initializing Waydroid (first run - this takes 5-10 minutes)..."
    INIT_ENV="XDG_RUNTIME_DIR=$DISPLAY_XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
    if [ "${USE_GAPPS:-yes}" = "yes" ]; then
        su -c "$INIT_ENV waydroid init -s GAPPS -f" $DISPLAY_USER 2>&1 | tee /tmp/waydroid-init.log
    else
        su -c "$INIT_ENV waydroid init -f" $DISPLAY_USER 2>&1 | tee /tmp/waydroid-init.log
    fi
    log "✓ Waydroid initialized"
fi

# Start Waydroid container
log "Starting Waydroid container..."
WAYDROID_ENV="XDG_RUNTIME_DIR=$DISPLAY_XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
su -c "$WAYDROID_ENV waydroid container start" $DISPLAY_USER 2>&1 | tee /tmp/waydroid-container.log
log "✓ Waydroid container started"

# Start Waydroid session
log "Starting Waydroid session..."
nohup su -c "$WAYDROID_ENV waydroid session start" $DISPLAY_USER > /tmp/waydroid-session.log 2>&1 &
sleep 5
log "Waydroid session started"

log "========================================"
log "✓✓✓ ALL SERVICES STARTED SUCCESSFULLY ✓✓✓"
log "========================================"
log "VNC Port: 5900"
log "Display User: $DISPLAY_USER"
log "Wayland Socket: $SOCKET_PATH"
log "========================================"

# Monitor critical processes
log "Entering monitoring loop..."
while true; do
    # Check Sway
    if ! pgrep -u $DISPLAY_USER sway > /dev/null; then
        log "ERROR: Sway compositor died"
        log "Last lines of sway log:"
        tail -20 /tmp/sway.log 2>/dev/null || log "No sway log"
        exit 1
    fi

    # Check WayVNC
    if ! ss -tlnp | grep -q ':5900'; then
        log "ERROR: WayVNC died (port 5900 not listening)"
        log "Last lines of wayvnc log:"
        tail -20 /tmp/wayvnc.log 2>/dev/null || log "No wayvnc log"
        exit 1
    fi

    sleep 10
done
EOFSCRIPT

log "✓ Startup script deployed"
log ""

log "Step 3: Making script executable"
pct exec $CTID -- chmod +x /usr/local/bin/start-waydroid.sh 2>&1 | tee -a "$LOGFILE"
log "✓ Script is executable"
log ""

log "Step 4: Reloading systemd"
pct exec $CTID -- systemctl daemon-reload 2>&1 | tee -a "$LOGFILE"
log "✓ Systemd reloaded"
log ""

log "Step 5: Starting waydroid-vnc service"
pct exec $CTID -- systemctl start waydroid-vnc.service 2>&1 | tee -a "$LOGFILE" || log "WARNING: Service start may have issues, checking..."
log "Waiting 20 seconds for services to stabilize..."
sleep 20
log ""

log "=========================================="
log "VERIFICATION"
log "=========================================="

log "Service Status:"
pct exec $CTID -- systemctl status waydroid-vnc.service --no-pager -l 2>&1 | tee -a "$LOGFILE" || true
log ""

log "Port 5900 Status:"
pct exec $CTID -- ss -tlnp | grep 5900 2>&1 | tee -a "$LOGFILE" || log "WARNING: Port 5900 not listening!"
log ""

log "Sway Processes:"
pct exec $CTID -- ps aux | grep -E "[s]way" 2>&1 | tee -a "$LOGFILE" || log "No sway processes"
log ""

log "WayVNC Processes:"
pct exec $CTID -- ps aux | grep -E "[w]ayvnc" 2>&1 | tee -a "$LOGFILE" || log "No wayvnc processes"
log ""

log "Last 30 lines of service log:"
pct exec $CTID -- journalctl -u waydroid-vnc.service -n 30 --no-pager 2>&1 | tee -a "$LOGFILE"
log ""

log "=========================================="
CONTAINER_IP=$(pct exec $CTID -- hostname -I | awk '{print $1}' 2>/dev/null || echo "UNKNOWN")
log "Container IP: $CONTAINER_IP"
log "VNC Connection: vncviewer $CONTAINER_IP:5900"
log "Full log saved to: $LOGFILE"
log "=========================================="
log "FIX COMPLETE"
log "=========================================="
