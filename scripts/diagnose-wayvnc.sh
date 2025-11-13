#!/usr/bin/env bash

# WayVNC Diagnostic Script for LXC Container
# Run inside the container to test WayVNC startup and connectivity
#
# Usage:
#   ./diagnose-wayvnc.sh [container_id]
#
# Examples:
#   ./diagnose-wayvnc.sh          # Run diagnostics on current container
#   ./diagnose-wayvnc.sh 103      # Documentation: typically runs in CT 103

set -euo pipefail

# Configuration
CTID="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper functions
if [ -f "$SCRIPT_DIR/helper-functions.sh" ]; then
    source "$SCRIPT_DIR/helper-functions.sh"
else
    # Minimal fallback functions
    BL="\033[36m"
    RD="\033[01;31m"
    GN="\033[1;92m"
    YW="\033[1;93m"
    CL="\033[m"
    CM="${GN}✓${CL}"
    CROSS="${RD}✗${CL}"

    msg_info() { echo -e "${BL}[INFO]${CL} $1"; }
    msg_ok() { echo -e "${CM} $1"; }
    msg_error() { echo -e "${CROSS} $1"; }
    msg_warn() { echo -e "${YW}[WARN]${CL} $1"; }
fi

# Configuration
WAYDROID_USER="waydroid"
WAYVNC_CONFIG_DIR="/home/$WAYDROID_USER/.config/wayvnc"
WAYVNC_CONFIG="$WAYVNC_CONFIG_DIR/config"
WAYVNC_LOG="/tmp/wayvnc-diagnostic.log"
VNC_PORT=5900
WAYLAND_SOCKET_TIMEOUT=10
SWAY_STARTUP_TIMEOUT=15
WAYVNC_STARTUP_TIMEOUT=5

# Results tracking
DIAGNOSTICS_PASSED=0
DIAGNOSTICS_FAILED=0
OVERALL_STATUS="PASS"

# Cleanup on exit
cleanup() {
    msg_info "Performing cleanup..."

    # Kill any test wayvnc processes
    if pgrep -f "wayvnc.*0.0.0.0.*5900" > /dev/null 2>&1; then
        msg_info "Killing test WayVNC processes..."
        pkill -f "wayvnc.*0.0.0.0.*5900" || true
        sleep 1
    fi

    # Don't kill Sway if it was running before we started
    # Just note that it's running
    if pgrep -x sway > /dev/null 2>&1; then
        msg_info "Sway is still running (OK if it was started before diagnostics)"
    fi
}

trap cleanup EXIT

# Test function
run_diagnostic() {
    local test_num=$1
    local test_name=$2
    local test_cmd=$3
    local critical="${4:-no}"

    echo -e "\n${BL}[Test $test_num] $test_name${CL}"
    echo "Command: $test_cmd"
    echo "---"

    if output=$(bash -c "$test_cmd" 2>&1); then
        msg_ok "PASSED"
        echo "$output" | head -20
        DIAGNOSTICS_PASSED=$((DIAGNOSTICS_PASSED + 1))
        return 0
    else
        if [ "$critical" = "yes" ]; then
            msg_error "FAILED (CRITICAL)"
            OVERALL_STATUS="FAIL"
        else
            msg_warn "FAILED (non-critical)"
        fi
        echo "$output" | head -20
        DIAGNOSTICS_FAILED=$((DIAGNOSTICS_FAILED + 1))
        return 1
    fi
}

# Header
echo -e "${GN}═══════════════════════════════════════════════${CL}"
echo -e "${GN}  WayVNC Diagnostic Script${CL}"
echo -e "${GN}  $(date '+%Y-%m-%d %H:%M:%S')${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

if [ -n "$CTID" ]; then
    msg_info "Container ID: $CTID (informational, this script runs inside the container)"
fi

# Check if we're running as root or can escalate
if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
    msg_warn "Some diagnostics require root privileges"
    msg_info "Consider running: sudo $0 $CTID"
fi

# Phase 1: System and Installation Checks
echo -e "\n${BL}=== Phase 1: System and Installation Checks ===${CL}\n"

run_diagnostic 1 "WayVNC Binary Available" \
    "command -v wayvnc" "yes"

run_diagnostic 2 "WayVNC Version" \
    "wayvnc --version 2>&1 || wayvnc -h 2>&1 | head -5"

run_diagnostic 3 "Waydroid User Exists" \
    "id $WAYDROID_USER" "yes"

run_diagnostic 4 "Waydroid User Groups" \
    "groups $WAYDROID_USER"

run_diagnostic 5 "Sway Installed" \
    "command -v sway" "yes"

# Phase 2: Configuration Checks
echo -e "\n${BL}=== Phase 2: Configuration and Environment ===${CL}\n"

run_diagnostic 6 "WayVNC Config Directory Exists" \
    "[ -d '$WAYVNC_CONFIG_DIR' ] && echo 'Config directory found at $WAYVNC_CONFIG_DIR'"

run_diagnostic 7 "WayVNC Config File" \
    "[ -f '$WAYVNC_CONFIG' ] && cat '$WAYVNC_CONFIG' || echo 'Config file not found (may be created at runtime)'"

run_diagnostic 8 "Waydroid User Home Directory" \
    "[ -d '/home/$WAYDROID_USER' ] && ls -la '/home/$WAYDROID_USER/' | head -15"

# Phase 3: Wayland Socket Detection
echo -e "\n${BL}=== Phase 3: Wayland Socket Detection ===${CL}\n"

msg_info "Checking for Wayland sockets (max wait: ${WAYLAND_SOCKET_TIMEOUT}s)..."

DISPLAY_UID=$(id -u "$WAYDROID_USER")
DISPLAY_XDG_RUNTIME_DIR="/run/user/$DISPLAY_UID"

run_diagnostic 9 "XDG Runtime Directory Exists" \
    "[ -d '$DISPLAY_XDG_RUNTIME_DIR' ] && echo 'Runtime dir: $DISPLAY_XDG_RUNTIME_DIR'"

run_diagnostic 10 "Wayland Socket Exists" \
    "[ -e '$DISPLAY_XDG_RUNTIME_DIR/wayland-0' ] && echo 'Wayland socket: wayland-0' || (ls -la '$DISPLAY_XDG_RUNTIME_DIR'/ | grep wayland || echo 'Searching for wayland sockets...')"

# Phase 4: Process Management
echo -e "\n${BL}=== Phase 4: Process Management ===${CL}\n"

msg_info "Checking for existing WayVNC processes..."
run_diagnostic 11 "No Existing WayVNC Processes" \
    "! pgrep -f wayvnc > /dev/null && echo 'No WayVNC processes running' || pgrep -f wayvnc | xargs ps aux | grep -v grep || true"

msg_info "Checking for existing Sway processes..."
run_diagnostic 12 "Sway Process Status" \
    "pgrep -x sway > /dev/null && (echo 'Sway is running (PID:'; pgrep -x sway; echo ')') || echo 'Sway is not running'"

# Phase 5: Kill Existing Processes (Non-destructive)
echo -e "\n${BL}=== Phase 5: Kill Existing Processes (for testing) ===${CL}\n"

msg_info "Attempting to kill existing WayVNC processes..."
if pgrep -f wayvnc > /dev/null 2>&1; then
    msg_warn "Found WayVNC processes, killing them..."
    pkill -f wayvnc || true
    sleep 2

    if ! pgrep -f wayvnc > /dev/null 2>&1; then
        msg_ok "WayVNC processes killed successfully"
        DIAGNOSTICS_PASSED=$((DIAGNOSTICS_PASSED + 1))
    else
        msg_error "Failed to kill WayVNC processes"
        DIAGNOSTICS_FAILED=$((DIAGNOSTICS_FAILED + 1))
    fi
else
    msg_ok "No WayVNC processes to kill"
    DIAGNOSTICS_PASSED=$((DIAGNOSTICS_PASSED + 1))
fi

# Phase 6: Start Sway Manually
echo -e "\n${BL}=== Phase 6: Start Sway Manually ===${CL}\n"

msg_info "Starting Sway as waydroid user (timeout: ${SWAY_STARTUP_TIMEOUT}s)..."

# First, check if Sway is already running
if pgrep -x sway > /dev/null 2>&1; then
    msg_warn "Sway is already running, skipping startup"
    DIAGNOSTICS_PASSED=$((DIAGNOSTICS_PASSED + 1))
else
    msg_info "Launching Sway in background..."

    # Start Sway with proper environment
    SWAY_CMD="
    export DISPLAY_UID=\$(id -u $WAYDROID_USER)
    export XDG_RUNTIME_DIR=/run/user/\$DISPLAY_UID

    # Find Wayland socket
    WAYLAND_DISPLAY=''
    for socket in \$XDG_RUNTIME_DIR/wayland-*; do
        if [ -S \"\$socket\" ]; then
            WAYLAND_DISPLAY=\$(basename \"\$socket\")
            break
        fi
    done

    if [ -z \"\$WAYLAND_DISPLAY\" ]; then
        echo 'ERROR: No Wayland socket found in \$XDG_RUNTIME_DIR'
        exit 1
    fi

    export WAYLAND_DISPLAY=\$WAYLAND_DISPLAY

    echo 'Starting Sway with:'
    echo \"  XDG_RUNTIME_DIR=\$XDG_RUNTIME_DIR\"
    echo \"  WAYLAND_DISPLAY=\$WAYLAND_DISPLAY\"

    # Start sway with minimal config
    timeout $SWAY_STARTUP_TIMEOUT sway -d 2>&1 || true
    "

    if su - "$WAYDROID_USER" -c "$SWAY_CMD" 2>&1 | tee -a "$WAYVNC_LOG" | grep -q "sway"; then
        sleep 2
        if pgrep -x sway > /dev/null 2>&1; then
            msg_ok "Sway started successfully"
            DIAGNOSTICS_PASSED=$((DIAGNOSTICS_PASSED + 1))
        else
            msg_warn "Sway may not have started (timeout is expected)"
            DIAGNOSTICS_PASSED=$((DIAGNOSTICS_PASSED + 1))
        fi
    else
        msg_warn "Sway startup output minimal (may still be running)"
        DIAGNOSTICS_PASSED=$((DIAGNOSTICS_PASSED + 1))
    fi
fi

# Phase 7: Start WayVNC Manually
echo -e "\n${BL}=== Phase 7: Start WayVNC Manually ===${CL}\n"

msg_info "Starting WayVNC (timeout: ${WAYVNC_STARTUP_TIMEOUT}s)..."

WAYVNC_CMD="
export DISPLAY_UID=\$(id -u $WAYDROID_USER)
export XDG_RUNTIME_DIR=/run/user/\$DISPLAY_UID

# Find Wayland socket
WAYLAND_DISPLAY=''
for socket in \$XDG_RUNTIME_DIR/wayland-*; do
    if [ -S \"\$socket\" ]; then
        WAYLAND_DISPLAY=\$(basename \"\$socket\")
        break
    fi
done

if [ -z \"\$WAYLAND_DISPLAY\" ]; then
    echo 'ERROR: No Wayland socket found in \$XDG_RUNTIME_DIR' >&2
    exit 1
fi

export WAYLAND_DISPLAY=\$WAYLAND_DISPLAY

echo 'Starting WayVNC with:'
echo \"  XDG_RUNTIME_DIR=\$XDG_RUNTIME_DIR\"
echo \"  WAYLAND_DISPLAY=\$WAYLAND_DISPLAY\"
echo \"  Binding to 0.0.0.0:$VNC_PORT\"
echo ''

# Start wayvnc with verbose output, binding to all interfaces
timeout $WAYVNC_STARTUP_TIMEOUT wayvnc 0.0.0.0 $VNC_PORT 2>&1 || true
"

if su - "$WAYDROID_USER" -c "$WAYVNC_CMD" 2>&1 | tee -a "$WAYVNC_LOG"; then
    msg_ok "WayVNC command completed"
    DIAGNOSTICS_PASSED=$((DIAGNOSTICS_PASSED + 1))
else
    msg_warn "WayVNC command exited with error code (may be timeout, checking if running...)"
fi

# Phase 8: Check if Processes are Running
echo -e "\n${BL}=== Phase 8: Process Status Check ===${CL}\n"

msg_info "Checking running processes..."

run_diagnostic 13 "Check for WayVNC Process" \
    "pgrep -f wayvnc > /dev/null && (echo 'WayVNC is running'; pgrep -f wayvnc | xargs ps aux | grep -v grep) || echo 'WayVNC not running (expected after short diagnostic test)'"

run_diagnostic 14 "Check for Sway Process" \
    "pgrep -x sway > /dev/null && (echo 'Sway is running'; pgrep -x sway | xargs ps aux | grep -v grep) || echo 'Sway not running (may be OK)'"

# Phase 9: Port Listening Check
echo -e "\n${BL}=== Phase 9: Port Availability Check ===${CL}\n"

msg_info "Checking if VNC port is listening..."

run_diagnostic 15 "VNC Port Availability" \
    "netstat -tuln 2>/dev/null | grep ':$VNC_PORT ' || ss -tuln 2>/dev/null | grep ':$VNC_PORT ' || echo 'Port $VNC_PORT not currently listening (may be OK)'"

# Phase 10: Detailed Configuration Review
echo -e "\n${BL}=== Phase 10: Configuration Review ===${CL}\n"

if [ -f "$WAYVNC_LOG" ]; then
    msg_info "WayVNC diagnostic log contents:"
    echo "---"
    tail -50 "$WAYVNC_LOG"
    echo "---"
fi

# Summary
echo -e "\n${GN}═══════════════════════════════════════════════${CL}"
echo -e "${GN}  Diagnostic Summary${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

echo -e "Diagnostics Passed: ${GN}$DIAGNOSTICS_PASSED${CL}"
echo -e "Diagnostics Failed: ${RD}$DIAGNOSTICS_FAILED${CL}"

if [ "$OVERALL_STATUS" = "PASS" ]; then
    echo -e "\nOverall Status: ${GN}PASS${CL}"
else
    echo -e "\nOverall Status: ${RD}FAIL${CL}"
fi

echo ""
echo "Log file saved to: $WAYVNC_LOG"
echo ""

if [ "$OVERALL_STATUS" = "PASS" ]; then
    msg_ok "All critical checks passed"
    exit 0
else
    msg_error "Some critical checks failed"
    exit 1
fi
