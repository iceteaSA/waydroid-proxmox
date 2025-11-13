#!/usr/bin/env bash

################################################################################
# Comprehensive Waydroid LXC System Testing Script
#
# Tests all components of the Waydroid LXC setup with detailed diagnostics,
# performance benchmarks, and multiple output formats.
#
# Usage: test-complete.sh [OPTIONS]
#
# Copyright (c) 2025
# License: MIT
################################################################################

set -euo pipefail

# Script directory and dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/helper-functions.sh" ]; then
    source "${SCRIPT_DIR}/helper-functions.sh"
else
    # Minimal fallback
    msg_info() { echo "[INFO] $1"; }
    msg_ok() { echo "[OK] $1"; }
    msg_error() { echo "[ERROR] $1"; }
    msg_warn() { echo "[WARN] $1"; }
    is_lxc() { [ -f /proc/1/environ ] && grep -q container=lxc /proc/1/environ 2>/dev/null; }
    is_proxmox_host() { command -v pveversion &> /dev/null; }
    GN="\033[1;92m"; RD="\033[01;31m"; YW="\033[1;93m"; BL="\033[36m"; CL="\033[m"
    CM="${GN}✓${CL}"; CROSS="${RD}✗${CL}"
fi

################################################################################
# Configuration and Global Variables
################################################################################

VERSION="1.0.0"
TEST_START_TIME=$(date +%s)
TEST_MODE="thorough"  # quick or thorough
OUTPUT_FORMAT="text"   # text, json, html, all
OUTPUT_DIR="/tmp/waydroid-test-results"
REPORT_PREFIX="waydroid-test"
VERBOSE=false
CI_MODE=false
RUN_FROM="auto"  # auto, host, container

# Test results tracking
declare -a TEST_CATEGORIES=()
declare -A TEST_RESULTS=()
declare -A TEST_MESSAGES=()
declare -A TEST_DIAGNOSTICS=()
declare -A TEST_RECOMMENDATIONS=()
declare -A TEST_TIMINGS=()
declare -A PERFORMANCE_METRICS=()

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0
WARNING_TESTS=0

# Performance thresholds
declare -A PERF_THRESHOLDS=(
    ["gpu_render_time"]=5000        # ms
    ["api_response_time"]=1000      # ms
    ["vnc_handshake_time"]=2000     # ms
    ["waydroid_start_time"]=30000   # ms
    ["memory_available_mb"]=512     # MB
    ["disk_free_percent"]=10        # %
)

################################################################################
# Utility Functions
################################################################################

print_header() {
    if [ "$OUTPUT_FORMAT" != "json" ]; then
        echo -e "${GN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
        echo -e "${GN}  $1${CL}"
        echo -e "${GN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
    fi
}

print_section() {
    if [ "$OUTPUT_FORMAT" != "json" ] && ! $CI_MODE; then
        echo ""
        echo -e "${BL}╔══════════════════════════════════════════════════════════════════╗${CL}"
        echo -e "${BL}║  $1${CL}"
        echo -e "${BL}╚══════════════════════════════════════════════════════════════════╝${CL}"
    fi
}

verbose() {
    if $VERBOSE && [ "$OUTPUT_FORMAT" != "json" ]; then
        echo -e "${YW}[VERBOSE]${CL} $1"
    fi
}

log_metric() {
    local name=$1
    local value=$2
    PERFORMANCE_METRICS["$name"]=$value
    verbose "Metric: $name = $value"
}

get_timestamp_ms() {
    date +%s%3N
}

record_test() {
    local category=$1
    local test_name=$2
    local result=$3        # pass, fail, warn, skip
    local message=$4
    local diagnostic=${5:-}
    local recommendation=${6:-}
    local timing=${7:-0}

    local full_name="${category}::${test_name}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    TEST_RESULTS["$full_name"]=$result
    TEST_MESSAGES["$full_name"]=$message
    TEST_DIAGNOSTICS["$full_name"]=$diagnostic
    TEST_RECOMMENDATIONS["$full_name"]=$recommendation
    TEST_TIMINGS["$full_name"]=$timing

    # Track category
    if [[ ! " ${TEST_CATEGORIES[*]} " =~ " ${category} " ]]; then
        TEST_CATEGORIES+=("$category")
    fi

    case $result in
        pass)
            PASSED_TESTS=$((PASSED_TESTS + 1))
            [ "$OUTPUT_FORMAT" != "json" ] && ! $CI_MODE && echo -e "  ${CM} $test_name ${YW}(${timing}ms)${CL}"
            ;;
        fail)
            FAILED_TESTS=$((FAILED_TESTS + 1))
            if [ "$OUTPUT_FORMAT" != "json" ]; then
                echo -e "  ${CROSS} $test_name"
                [ -n "$message" ] && echo -e "    ${RD}└─ $message${CL}"
            fi
            ;;
        warn)
            WARNING_TESTS=$((WARNING_TESTS + 1))
            [ "$OUTPUT_FORMAT" != "json" ] && ! $CI_MODE && echo -e "  ${YW}⚠${CL} $test_name: $message"
            ;;
        skip)
            SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
            [ "$OUTPUT_FORMAT" != "json" ] && ! $CI_MODE && echo -e "  ${BL}○${CL} $test_name (skipped)"
            ;;
    esac
}

show_help() {
    cat << EOF
Comprehensive Waydroid LXC System Testing Script v${VERSION}

Usage: $(basename "$0") [OPTIONS]

Test Modes:
  --quick             Run quick tests only (basic functionality)
  --thorough          Run thorough tests including performance (default)

Output Options:
  --format FORMAT     Output format: text, json, html, all (default: text)
  --output-dir DIR    Directory for test reports (default: /tmp/waydroid-test-results)
  --verbose, -v       Enable verbose output with detailed diagnostics
  --ci                CI/CD mode (minimal output, machine-readable)

Test Location:
  --from-host         Run host-specific tests only
  --from-container    Run container-specific tests only
  --auto              Auto-detect location (default)

Examples:
  $(basename "$0")                           # Run thorough tests with text output
  $(basename "$0") --quick --ci              # Quick tests for CI/CD
  $(basename "$0") --format all --verbose    # All formats with verbose output
  $(basename "$0") --from-host               # Host-specific tests only
  $(basename "$0") --format json > results.json  # JSON output to file

Exit Codes:
  0 - All tests passed
  1 - Some tests failed or warnings
  2 - Critical failure or setup error

EOF
}

################################################################################
# Test Category: System Resources
################################################################################

test_system_resources() {
    print_section "System Resources"
    local category="System Resources"
    local start_time

    # CPU Test
    start_time=$(get_timestamp_ms)
    local cpu_count=$(nproc)
    local load_avg=$(awk '{print $1}' /proc/loadavg)
    local load_per_cpu=$(awk "BEGIN {printf \"%.2f\", $load_avg / $cpu_count}")
    local timing=$(($(get_timestamp_ms) - start_time))

    log_metric "cpu_count" "$cpu_count"
    log_metric "load_avg" "$load_avg"
    log_metric "load_per_cpu" "$load_per_cpu"

    if (( $(awk "BEGIN {print ($load_per_cpu < 2.0)}") )); then
        record_test "$category" "CPU Load" "pass" "Load: $load_avg (${load_per_cpu}/core)" \
            "CPU cores: $cpu_count, Load average: $load_avg" \
            "" "$timing"
    else
        record_test "$category" "CPU Load" "warn" "High load: $load_avg (${load_per_cpu}/core)" \
            "System may be under heavy load" \
            "Check running processes with 'top' or 'htop'" "$timing"
    fi

    # Memory Test
    start_time=$(get_timestamp_ms)
    local mem_total=$(free -m | awk 'NR==2{print $2}')
    local mem_used=$(free -m | awk 'NR==2{print $3}')
    local mem_available=$(free -m | awk 'NR==2{print $7}')
    local mem_percent=$(awk "BEGIN {printf \"%.1f\", ($mem_used/$mem_total)*100}")
    timing=$(($(get_timestamp_ms) - start_time))

    log_metric "memory_total_mb" "$mem_total"
    log_metric "memory_used_mb" "$mem_used"
    log_metric "memory_available_mb" "$mem_available"
    log_metric "memory_used_percent" "$mem_percent"

    if [ "$mem_available" -gt "${PERF_THRESHOLDS[memory_available_mb]}" ]; then
        record_test "$category" "Memory Available" "pass" "$mem_available MB available (${mem_percent}% used)" \
            "Total: ${mem_total}MB, Used: ${mem_used}MB, Available: ${mem_available}MB" \
            "" "$timing"
    else
        record_test "$category" "Memory Available" "fail" "Low memory: $mem_available MB available" \
            "Only ${mem_available}MB available, ${mem_percent}% used" \
            "Consider increasing container memory allocation or closing applications" "$timing"
    fi

    # Disk Space Test
    start_time=$(get_timestamp_ms)
    local disk_total=$(df -h / | awk 'NR==2{print $2}')
    local disk_used=$(df -h / | awk 'NR==2{print $3}')
    local disk_avail=$(df -h / | awk 'NR==2{print $4}')
    local disk_percent=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')
    timing=$(($(get_timestamp_ms) - start_time))

    log_metric "disk_total" "$disk_total"
    log_metric "disk_used" "$disk_used"
    log_metric "disk_available" "$disk_avail"
    log_metric "disk_used_percent" "$disk_percent"

    if [ "$disk_percent" -lt 90 ]; then
        record_test "$category" "Disk Space" "pass" "$disk_avail available (${disk_percent}% used)" \
            "Total: ${disk_total}, Used: ${disk_used}, Available: ${disk_avail}" \
            "" "$timing"
    else
        record_test "$category" "Disk Space" "fail" "Low disk space: $disk_avail available (${disk_percent}% used)" \
            "Disk is ${disk_percent}% full" \
            "Clean up unnecessary files or increase disk allocation" "$timing"
    fi

    # I/O Performance Test (thorough mode only)
    if [ "$TEST_MODE" = "thorough" ]; then
        start_time=$(get_timestamp_ms)
        local test_file="/tmp/waydroid-io-test-$$"
        local io_speed="N/A"

        if dd if=/dev/zero of="$test_file" bs=1M count=100 oflag=direct 2>&1 | grep -o '[0-9.]* [MG]B/s' > /dev/null 2>&1; then
            io_speed=$(dd if=/dev/zero of="$test_file" bs=1M count=100 oflag=direct 2>&1 | grep -o '[0-9.]* [MG]B/s' | tail -1)
            rm -f "$test_file"
        fi
        timing=$(($(get_timestamp_ms) - start_time))

        log_metric "disk_write_speed" "$io_speed"

        if [ "$io_speed" != "N/A" ]; then
            record_test "$category" "Disk I/O Performance" "pass" "Write speed: $io_speed" \
                "Sequential write performance: $io_speed" \
                "" "$timing"
        else
            record_test "$category" "Disk I/O Performance" "skip" "Could not measure I/O speed" \
                "" "" "$timing"
        fi
    fi
}

################################################################################
# Test Category: Host Configuration (if on host)
################################################################################

test_host_configuration() {
    if [ "$RUN_FROM" = "container" ]; then
        return
    fi

    print_section "Host Configuration"
    local category="Host Configuration"
    local start_time

    # Proxmox Check
    start_time=$(get_timestamp_ms)
    local timing=$(($(get_timestamp_ms) - start_time))
    if is_proxmox_host; then
        local pve_version=$(pveversion | head -1)
        record_test "$category" "Proxmox Host" "pass" "$pve_version" \
            "Running on Proxmox VE" "" "$timing"
    else
        record_test "$category" "Proxmox Host" "skip" "Not running on Proxmox" \
            "" "" "$timing"
    fi

    # Kernel Modules (Host)
    start_time=$(get_timestamp_ms)
    local missing_modules=()
    for module in binder_linux ashmem_linux; do
        if ! lsmod | grep -q "^${module}"; then
            missing_modules+=("$module")
        fi
    done
    timing=$(($(get_timestamp_ms) - start_time))

    if [ ${#missing_modules[@]} -eq 0 ]; then
        record_test "$category" "Kernel Modules" "pass" "All required modules loaded" \
            "binder_linux and ashmem_linux are loaded" "" "$timing"
    else
        record_test "$category" "Kernel Modules" "fail" "Missing modules: ${missing_modules[*]}" \
            "Required Android kernel modules not loaded" \
            "Load modules: modprobe ${missing_modules[*]}" "$timing"
    fi

    # GPU Devices on Host
    start_time=$(get_timestamp_ms)
    local gpu_devices=$(ls /dev/dri/card* 2>/dev/null | wc -l)
    timing=$(($(get_timestamp_ms) - start_time))

    log_metric "gpu_devices_count" "$gpu_devices"

    if [ "$gpu_devices" -gt 0 ]; then
        record_test "$category" "GPU Devices" "pass" "Found $gpu_devices GPU device(s)" \
            "GPU devices available for passthrough" "" "$timing"

        # List GPU devices
        if $VERBOSE; then
            ls -la /dev/dri/ 2>/dev/null || true
        fi
    else
        record_test "$category" "GPU Devices" "warn" "No GPU devices found" \
            "No /dev/dri/card* devices detected" \
            "Ensure GPU drivers are installed and GPU is enabled" "$timing"
    fi
}

################################################################################
# Test Category: LXC Container Configuration
################################################################################

test_lxc_configuration() {
    if [ "$RUN_FROM" = "host" ]; then
        return
    fi

    print_section "LXC Container Configuration"
    local category="LXC Container"
    local start_time

    # Check if in LXC
    start_time=$(get_timestamp_ms)
    local timing=$(($(get_timestamp_ms) - start_time))
    if is_lxc; then
        record_test "$category" "Container Type" "pass" "Running in LXC container" \
            "Detected LXC containerization" "" "$timing"
    else
        record_test "$category" "Container Type" "fail" "Not running in LXC" \
            "This script should run inside an LXC container" \
            "Run this script inside the Waydroid LXC container" "$timing"
        return
    fi

    # GPU Device Access
    start_time=$(get_timestamp_ms)
    if [ -e /dev/dri/card0 ]; then
        if [ -r /dev/dri/card0 ] && [ -w /dev/dri/card0 ]; then
            record_test "$category" "GPU Device Access" "pass" "/dev/dri/card0 accessible" \
                "GPU device has read/write permissions" "" "$timing"
        else
            record_test "$category" "GPU Device Access" "fail" "/dev/dri/card0 no read/write access" \
                "GPU device exists but lacks proper permissions" \
                "Fix permissions: chmod 666 /dev/dri/card0 or add user to video group" "$timing"
        fi
    else
        record_test "$category" "GPU Device Access" "warn" "/dev/dri/card0 not found" \
            "GPU device not passed through to container" \
            "Add GPU passthrough in LXC config: lxc.cgroup2.devices.allow: c 226:* rwm" "$timing"
    fi
    timing=$(($(get_timestamp_ms) - start_time))

    # Render Node
    start_time=$(get_timestamp_ms)
    if [ -e /dev/dri/renderD128 ]; then
        record_test "$category" "Render Node" "pass" "/dev/dri/renderD128 available" \
            "Render node for GPU acceleration available" "" "$timing"
    else
        record_test "$category" "Render Node" "warn" "/dev/dri/renderD128 not found" \
            "Render node not available (may not be critical)" \
            "Verify GPU drivers are installed" "$timing"
    fi
    timing=$(($(get_timestamp_ms) - start_time))

    # Kernel Modules in Container
    start_time=$(get_timestamp_ms)
    local missing_modules=()
    for module in binder_linux ashmem_linux; do
        if ! lsmod 2>/dev/null | grep -q "^${module}"; then
            missing_modules+=("$module")
        fi
    done
    timing=$(($(get_timestamp_ms) - start_time))

    if [ ${#missing_modules[@]} -eq 0 ]; then
        record_test "$category" "Kernel Modules" "pass" "Required modules available" \
            "binder_linux and ashmem_linux are loaded" "" "$timing"
    else
        record_test "$category" "Kernel Modules" "fail" "Missing modules: ${missing_modules[*]}" \
            "Android kernel modules not loaded on host" \
            "Load on host: modprobe ${missing_modules[*]}" "$timing"
    fi
}

################################################################################
# Test Category: Waydroid Installation and Operation
################################################################################

test_waydroid() {
    if [ "$RUN_FROM" = "host" ]; then
        return
    fi

    print_section "Waydroid Installation & Operation"
    local category="Waydroid"
    local start_time

    # Installation Check
    start_time=$(get_timestamp_ms)
    local timing=$(($(get_timestamp_ms) - start_time))
    if command -v waydroid &> /dev/null; then
        local version=$(waydroid --version 2>/dev/null || echo "unknown")
        record_test "$category" "Installation" "pass" "Waydroid installed (${version})" \
            "Waydroid binary found at $(which waydroid)" "" "$timing"
    else
        record_test "$category" "Installation" "fail" "Waydroid not installed" \
            "Waydroid command not found" \
            "Install Waydroid: https://github.com/waydroid/waydroid" "$timing"
        return
    fi

    # Initialization Check
    start_time=$(get_timestamp_ms)
    timing=$(($(get_timestamp_ms) - start_time))
    if [ -d /var/lib/waydroid/overlay ]; then
        record_test "$category" "Initialization" "pass" "Waydroid initialized" \
            "Waydroid data directory exists" "" "$timing"
    else
        record_test "$category" "Initialization" "fail" "Waydroid not initialized" \
            "Waydroid data directory not found" \
            "Initialize: waydroid init -s GAPPS" "$timing"
    fi

    # Container Service
    start_time=$(get_timestamp_ms)
    timing=$(($(get_timestamp_ms) - start_time))
    if systemctl is-active --quiet waydroid-container.service 2>/dev/null; then
        record_test "$category" "Container Service" "pass" "Service running" \
            "waydroid-container.service is active" "" "$timing"
    else
        record_test "$category" "Container Service" "warn" "Service not running" \
            "waydroid-container.service is not active" \
            "Start: systemctl start waydroid-container" "$timing"
    fi

    # Status Check
    start_time=$(get_timestamp_ms)
    local status_output=$(waydroid status 2>&1 || echo "ERROR")
    timing=$(($(get_timestamp_ms) - start_time))

    if echo "$status_output" | grep -q "RUNNING"; then
        record_test "$category" "Session Status" "pass" "Session running" \
            "Waydroid session is active" "" "$timing"

        # App List Test (thorough mode)
        if [ "$TEST_MODE" = "thorough" ]; then
            start_time=$(get_timestamp_ms)
            local app_list=$(waydroid app list 2>/dev/null || echo "")
            timing=$(($(get_timestamp_ms) - start_time))

            if [ -n "$app_list" ]; then
                local app_count=$(echo "$app_list" | wc -l)
                log_metric "waydroid_apps_count" "$app_count"
                record_test "$category" "Installed Apps" "pass" "$app_count apps installed" \
                    "Apps: $(echo "$app_list" | head -3 | tr '\n' ' ')..." "" "$timing"
            else
                record_test "$category" "Installed Apps" "warn" "No apps found" \
                    "No Android apps installed" \
                    "Install apps: waydroid app install <apk>" "$timing"
            fi
        fi
    else
        record_test "$category" "Session Status" "warn" "Session not running" \
            "Waydroid session is not active" \
            "Start session: waydroid session start" "$timing"
    fi
}

################################################################################
# Test Category: Wayland Compositor
################################################################################

test_wayland() {
    if [ "$RUN_FROM" = "host" ]; then
        return
    fi

    print_section "Wayland Compositor"
    local category="Wayland"
    local start_time

    # Sway Check
    start_time=$(get_timestamp_ms)
    local timing=$(($(get_timestamp_ms) - start_time))
    if command -v sway &> /dev/null; then
        if pgrep -x sway > /dev/null; then
            record_test "$category" "Sway Compositor" "pass" "Sway running" \
                "Sway Wayland compositor is active" "" "$timing"
        else
            record_test "$category" "Sway Compositor" "warn" "Sway installed but not running" \
                "Sway is available but not currently active" \
                "Start Sway compositor" "$timing"
        fi
    else
        record_test "$category" "Sway Compositor" "warn" "Sway not installed" \
            "Sway compositor not found" \
            "Install: apt install sway" "$timing"
    fi

    # Wayland Display Check
    start_time=$(get_timestamp_ms)
    timing=$(($(get_timestamp_ms) - start_time))
    if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -e /run/user/0/wayland-0 ]; then
        record_test "$category" "Wayland Display" "pass" "Display socket available" \
            "Wayland display is configured" "" "$timing"
    else
        record_test "$category" "Wayland Display" "warn" "No Wayland display found" \
            "WAYLAND_DISPLAY not set and no socket found" \
            "Ensure Wayland compositor is running" "$timing"
    fi
}

################################################################################
# Test Category: VNC Server
################################################################################

test_vnc_server() {
    if [ "$RUN_FROM" = "host" ]; then
        return
    fi

    print_section "VNC Server"
    local category="VNC Server"
    local start_time

    # WayVNC Installation
    start_time=$(get_timestamp_ms)
    local timing=$(($(get_timestamp_ms) - start_time))
    if command -v wayvnc &> /dev/null; then
        record_test "$category" "WayVNC Installation" "pass" "WayVNC installed" \
            "wayvnc binary found" "" "$timing"
    else
        record_test "$category" "WayVNC Installation" "fail" "WayVNC not installed" \
            "wayvnc command not found" \
            "Install: apt install wayvnc" "$timing"
        return
    fi

    # VNC Service
    start_time=$(get_timestamp_ms)
    timing=$(($(get_timestamp_ms) - start_time))
    if systemctl is-active --quiet waydroid-vnc.service 2>/dev/null; then
        record_test "$category" "VNC Service" "pass" "Service running" \
            "waydroid-vnc.service is active" "" "$timing"
    else
        record_test "$category" "VNC Service" "warn" "Service not running" \
            "waydroid-vnc.service is not active" \
            "Start: systemctl start waydroid-vnc" "$timing"
    fi

    # VNC Port Listen
    start_time=$(get_timestamp_ms)
    timing=$(($(get_timestamp_ms) - start_time))
    if ss -tuln 2>/dev/null | grep -q ":5900 " || netstat -tuln 2>/dev/null | grep -q ":5900 "; then
        record_test "$category" "VNC Port" "pass" "Listening on port 5900" \
            "VNC server accepting connections" "" "$timing"
    else
        record_test "$category" "VNC Port" "warn" "Not listening on port 5900" \
            "VNC port not open" \
            "Check VNC service logs: journalctl -u waydroid-vnc" "$timing"
    fi

    # VNC Connection Test
    if [ "$TEST_MODE" = "thorough" ]; then
        start_time=$(get_timestamp_ms)
        if timeout 3 bash -c "</dev/tcp/localhost/5900" 2>/dev/null; then
            timing=$(($(get_timestamp_ms) - start_time))
            log_metric "vnc_connection_time_ms" "$timing"

            if [ "$timing" -lt "${PERF_THRESHOLDS[vnc_handshake_time]}" ]; then
                record_test "$category" "VNC Connection" "pass" "Connection successful (${timing}ms)" \
                    "VNC handshake completed quickly" "" "$timing"
            else
                record_test "$category" "VNC Connection" "warn" "Connection slow (${timing}ms)" \
                    "VNC handshake took longer than expected" \
                    "Check network and VNC server performance" "$timing"
            fi
        else
            timing=$(($(get_timestamp_ms) - start_time))
            record_test "$category" "VNC Connection" "fail" "Connection failed" \
                "Cannot establish connection to VNC port" \
                "Verify VNC service is running and configured correctly" "$timing"
        fi
    fi

    # VNC Security Check
    start_time=$(get_timestamp_ms)
    timing=$(($(get_timestamp_ms) - start_time))
    if [ -f /etc/wayvnc/config ]; then
        if grep -q "enable_auth=true" /etc/wayvnc/config 2>/dev/null; then
            record_test "$category" "VNC Security" "pass" "Authentication enabled" \
                "VNC requires authentication" "" "$timing"
        else
            record_test "$category" "VNC Security" "warn" "Authentication may be disabled" \
                "VNC config exists but auth status unclear" \
                "Enable auth in /etc/wayvnc/config" "$timing"
        fi
    else
        record_test "$category" "VNC Security" "warn" "No config file found" \
            "Cannot verify VNC security settings" \
            "Create config at /etc/wayvnc/config" "$timing"
    fi
}

################################################################################
# Test Category: API Server
################################################################################

test_api_server() {
    if [ "$RUN_FROM" = "host" ]; then
        return
    fi

    print_section "API Server"
    local category="API Server"
    local start_time

    # API Script Check
    start_time=$(get_timestamp_ms)
    local timing=$(($(get_timestamp_ms) - start_time))
    if [ -f /usr/local/bin/waydroid-api.py ]; then
        record_test "$category" "API Script" "pass" "API script installed" \
            "waydroid-api.py found" "" "$timing"
    else
        record_test "$category" "API Script" "fail" "API script not found" \
            "waydroid-api.py missing" \
            "Install API script from repository" "$timing"
        return
    fi

    # API Service
    start_time=$(get_timestamp_ms)
    timing=$(($(get_timestamp_ms) - start_time))
    if systemctl is-active --quiet waydroid-api.service 2>/dev/null; then
        record_test "$category" "API Service" "pass" "Service running" \
            "waydroid-api.service is active" "" "$timing"
    else
        record_test "$category" "API Service" "warn" "Service not running" \
            "waydroid-api.service is not active" \
            "Start: systemctl start waydroid-api" "$timing"
        return
    fi

    # API Port
    start_time=$(get_timestamp_ms)
    timing=$(($(get_timestamp_ms) - start_time))
    if ss -tuln 2>/dev/null | grep -q ":8080 " || netstat -tuln 2>/dev/null | grep -q ":8080 "; then
        record_test "$category" "API Port" "pass" "Listening on port 8080" \
            "API server accepting connections" "" "$timing"
    else
        record_test "$category" "API Port" "fail" "Not listening on port 8080" \
            "API port not open" \
            "Check API service logs: journalctl -u waydroid-api" "$timing"
        return
    fi

    # Test API Endpoints
    if command -v curl &> /dev/null; then
        # GET /status
        start_time=$(get_timestamp_ms)
        local status_response=$(curl -s --connect-timeout 5 http://localhost:8080/status 2>/dev/null || echo "")
        timing=$(($(get_timestamp_ms) - start_time))

        log_metric "api_status_response_time_ms" "$timing"

        if [ -n "$status_response" ]; then
            if echo "$status_response" | grep -q -E '(status|waydroid|running|stopped)'; then
                if [ "$timing" -lt "${PERF_THRESHOLDS[api_response_time]}" ]; then
                    record_test "$category" "GET /status" "pass" "Endpoint working (${timing}ms)" \
                        "API status endpoint responding correctly" "" "$timing"
                else
                    record_test "$category" "GET /status" "warn" "Endpoint slow (${timing}ms)" \
                        "API response time exceeds threshold" \
                        "Investigate API server performance" "$timing"
                fi
            else
                record_test "$category" "GET /status" "warn" "Unexpected response format" \
                    "API responded but format is unexpected" \
                    "Check API implementation" "$timing"
            fi
        else
            record_test "$category" "GET /status" "fail" "Endpoint not responding" \
                "No response from /status endpoint" \
                "Check API service status and logs" "$timing"
        fi

        # GET /apps
        if [ "$TEST_MODE" = "thorough" ]; then
            start_time=$(get_timestamp_ms)
            local apps_response=$(curl -s --connect-timeout 5 http://localhost:8080/apps 2>/dev/null || echo "")
            timing=$(($(get_timestamp_ms) - start_time))

            if [ -n "$apps_response" ]; then
                record_test "$category" "GET /apps" "pass" "Endpoint working (${timing}ms)" \
                    "API apps endpoint responding" "" "$timing"
            else
                record_test "$category" "GET /apps" "warn" "Endpoint not responding" \
                    "No response from /apps endpoint" \
                    "Verify API implementation includes /apps" "$timing"
            fi
        fi
    else
        record_test "$category" "API Endpoints" "skip" "curl not available" \
            "Cannot test API endpoints without curl" \
            "Install curl: apt install curl" "0"
    fi
}

################################################################################
# Test Category: Audio System
################################################################################

test_audio_system() {
    if [ "$RUN_FROM" = "host" ] || [ "$TEST_MODE" = "quick" ]; then
        return
    fi

    print_section "Audio System"
    local category="Audio"
    local start_time

    # PulseAudio Check
    start_time=$(get_timestamp_ms)
    local timing=$(($(get_timestamp_ms) - start_time))
    if command -v pulseaudio &> /dev/null; then
        if pgrep -x pulseaudio > /dev/null; then
            record_test "$category" "PulseAudio" "pass" "PulseAudio running" \
                "PulseAudio daemon is active" "" "$timing"
        else
            record_test "$category" "PulseAudio" "warn" "PulseAudio not running" \
                "PulseAudio installed but not active" \
                "Start: pulseaudio --start" "$timing"
        fi
    else
        record_test "$category" "PulseAudio" "skip" "PulseAudio not installed" \
            "PulseAudio not found (may use alternative)" "" "$timing"
    fi

    # PipeWire Check
    start_time=$(get_timestamp_ms)
    timing=$(($(get_timestamp_ms) - start_time))
    if command -v pipewire &> /dev/null; then
        if pgrep -x pipewire > /dev/null; then
            record_test "$category" "PipeWire" "pass" "PipeWire running" \
                "PipeWire audio server is active" "" "$timing"
        else
            record_test "$category" "PipeWire" "warn" "PipeWire not running" \
                "PipeWire installed but not active" \
                "Start: systemctl --user start pipewire" "$timing"
        fi
    else
        record_test "$category" "PipeWire" "skip" "PipeWire not installed" \
            "PipeWire not found (may use alternative)" "" "$timing"
    fi

    # Audio Devices
    start_time=$(get_timestamp_ms)
    timing=$(($(get_timestamp_ms) - start_time))
    if [ -d /dev/snd ]; then
        local device_count=$(ls -1 /dev/snd/pcm* 2>/dev/null | wc -l)
        if [ "$device_count" -gt 0 ]; then
            record_test "$category" "Audio Devices" "pass" "$device_count PCM device(s)" \
                "Audio hardware devices available" "" "$timing"
        else
            record_test "$category" "Audio Devices" "warn" "No PCM devices found" \
                "/dev/snd exists but no PCM devices" \
                "Verify audio configuration" "$timing"
        fi
    else
        record_test "$category" "Audio Devices" "warn" "/dev/snd not found" \
            "Audio device directory missing" \
            "Enable audio passthrough in LXC config" "$timing"
    fi
}

################################################################################
# Test Category: Clipboard Sharing
################################################################################

test_clipboard() {
    if [ "$RUN_FROM" = "host" ] || [ "$TEST_MODE" = "quick" ]; then
        return
    fi

    print_section "Clipboard Sharing"
    local category="Clipboard"
    local start_time

    # wl-clipboard Check
    start_time=$(get_timestamp_ms)
    local timing=$(($(get_timestamp_ms) - start_time))
    if command -v wl-copy &> /dev/null && command -v wl-paste &> /dev/null; then
        record_test "$category" "wl-clipboard Tools" "pass" "wl-copy and wl-paste available" \
            "Wayland clipboard tools installed" "" "$timing"
    else
        record_test "$category" "wl-clipboard Tools" "warn" "wl-clipboard not fully installed" \
            "Missing wl-copy or wl-paste" \
            "Install: apt install wl-clipboard" "$timing"
    fi

    # Clipboard Sync Daemon
    start_time=$(get_timestamp_ms)
    timing=$(($(get_timestamp_ms) - start_time))
    if [ -f /usr/local/bin/waydroid-clipboard-sync.sh ]; then
        if pgrep -f waydroid-clipboard-sync > /dev/null; then
            record_test "$category" "Sync Daemon" "pass" "Clipboard sync running" \
                "Clipboard synchronization daemon is active" "" "$timing"
        else
            record_test "$category" "Sync Daemon" "warn" "Sync daemon not running" \
                "Clipboard sync script exists but not active" \
                "Start clipboard sync service" "$timing"
        fi
    else
        record_test "$category" "Sync Daemon" "skip" "Sync daemon not installed" \
            "Clipboard sync not configured" \
            "Run: ./scripts/setup-clipboard.sh" "$timing"
    fi

    # ADB for Clipboard
    start_time=$(get_timestamp_ms)
    timing=$(($(get_timestamp_ms) - start_time))
    if command -v adb &> /dev/null; then
        record_test "$category" "ADB Tools" "pass" "ADB installed" \
            "Android Debug Bridge available for clipboard sync" "" "$timing"
    else
        record_test "$category" "ADB Tools" "warn" "ADB not installed" \
            "ADB needed for Android clipboard access" \
            "Install: apt install adb" "$timing"
    fi
}

################################################################################
# Test Category: GPU Performance
################################################################################

test_gpu_performance() {
    if [ "$RUN_FROM" = "host" ] || [ "$TEST_MODE" = "quick" ]; then
        return
    fi

    print_section "GPU Performance"
    local category="GPU Performance"
    local start_time

    # glxinfo Check
    start_time=$(get_timestamp_ms)
    if command -v glxinfo &> /dev/null; then
        local glx_output=$(glxinfo 2>&1 || echo "ERROR")
        timing=$(($(get_timestamp_ms) - start_time))

        if echo "$glx_output" | grep -q "direct rendering: Yes"; then
            local renderer=$(echo "$glx_output" | grep "OpenGL renderer" | cut -d: -f2 | xargs)
            local gl_version=$(echo "$glx_output" | grep "OpenGL version" | cut -d: -f2 | xargs)

            log_metric "gpu_renderer" "$renderer"
            log_metric "opengl_version" "$gl_version"

            record_test "$category" "Direct Rendering" "pass" "Enabled ($renderer)" \
                "OpenGL Version: $gl_version" "" "$timing"
        else
            record_test "$category" "Direct Rendering" "fail" "Not available" \
                "Direct rendering is disabled" \
                "Check GPU drivers and configuration" "$timing"
        fi
    else
        timing=$(($(get_timestamp_ms) - start_time))
        record_test "$category" "Direct Rendering" "skip" "glxinfo not available" \
            "Cannot test GPU rendering" \
            "Install: apt install mesa-utils" "$timing"
    fi

    # Vulkan Support
    start_time=$(get_timestamp_ms)
    if command -v vulkaninfo &> /dev/null; then
        if vulkaninfo --summary &>/dev/null; then
            timing=$(($(get_timestamp_ms) - start_time))
            record_test "$category" "Vulkan Support" "pass" "Vulkan available" \
                "Vulkan API is functional" "" "$timing"
        else
            timing=$(($(get_timestamp_ms) - start_time))
            record_test "$category" "Vulkan Support" "warn" "Vulkan not working" \
                "vulkaninfo failed" \
                "Install Vulkan drivers" "$timing"
        fi
    else
        timing=$(($(get_timestamp_ms) - start_time))
        record_test "$category" "Vulkan Support" "skip" "vulkaninfo not available" \
            "Cannot test Vulkan support" \
            "Install: apt install vulkan-tools" "$timing"
    fi

    # Intel GPU Tools
    if [ "$TEST_MODE" = "thorough" ]; then
        start_time=$(get_timestamp_ms)
        timing=$(($(get_timestamp_ms) - start_time))
        if command -v intel_gpu_top &> /dev/null; then
            record_test "$category" "Intel GPU Tools" "pass" "intel_gpu_top available" \
                "Intel GPU monitoring tools installed" "" "$timing"
        else
            record_test "$category" "Intel GPU Tools" "skip" "intel_gpu_top not found" \
                "Intel GPU tools not installed (may not be Intel GPU)" \
                "Install: apt install intel-gpu-tools" "$timing"
        fi
    fi
}

################################################################################
# Test Category: Network Connectivity
################################################################################

test_network() {
    print_section "Network Connectivity"
    local category="Network"
    local start_time

    # DNS Resolution
    start_time=$(get_timestamp_ms)
    if host google.com &> /dev/null || nslookup google.com &> /dev/null; then
        timing=$(($(get_timestamp_ms) - start_time))
        record_test "$category" "DNS Resolution" "pass" "DNS working (${timing}ms)" \
            "Domain name resolution successful" "" "$timing"
    else
        timing=$(($(get_timestamp_ms) - start_time))
        record_test "$category" "DNS Resolution" "fail" "DNS not working" \
            "Cannot resolve domain names" \
            "Check /etc/resolv.conf" "$timing"
    fi

    # Internet Connectivity
    start_time=$(get_timestamp_ms)
    if ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
        timing=$(($(get_timestamp_ms) - start_time))
        record_test "$category" "Internet Connectivity" "pass" "Ping successful (${timing}ms)" \
            "Can reach external hosts" "" "$timing"
    else
        timing=$(($(get_timestamp_ms) - start_time))
        record_test "$category" "Internet Connectivity" "fail" "Cannot reach internet" \
            "Ping to 8.8.8.8 failed" \
            "Check network configuration and firewall" "$timing"
    fi

    # HTTP/HTTPS Connectivity
    if command -v curl &> /dev/null; then
        start_time=$(get_timestamp_ms)
        if curl -s --connect-timeout 5 https://google.com > /dev/null; then
            timing=$(($(get_timestamp_ms) - start_time))
            record_test "$category" "HTTP/HTTPS" "pass" "HTTP(S) working (${timing}ms)" \
                "Can access web resources" "" "$timing"
        else
            timing=$(($(get_timestamp_ms) - start_time))
            record_test "$category" "HTTP/HTTPS" "warn" "HTTP(S) not working" \
                "Cannot access web resources" \
                "Check proxy settings and firewall" "$timing"
        fi
    fi

    # Container IP
    start_time=$(get_timestamp_ms)
    local container_ip=$(hostname -I | awk '{print $1}')
    timing=$(($(get_timestamp_ms) - start_time))

    if [ -n "$container_ip" ]; then
        log_metric "container_ip" "$container_ip"
        record_test "$category" "Container IP" "pass" "IP: $container_ip" \
            "Container has network address" "" "$timing"
    else
        record_test "$category" "Container IP" "fail" "No IP address" \
            "Container has no network address" \
            "Check LXC network configuration" "$timing"
    fi
}

################################################################################
# Report Generation Functions
################################################################################

generate_text_report() {
    local output_file="${OUTPUT_DIR}/${REPORT_PREFIX}-$(date +%Y%m%d-%H%M%S).txt"

    {
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  WAYDROID LXC COMPREHENSIVE TEST REPORT"
        echo "  Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "  Version: ${VERSION}"
        echo "  Test Mode: ${TEST_MODE}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        # Executive Summary
        echo "EXECUTIVE SUMMARY"
        echo "══════════════════════════════════════════════════════════════════════════════"
        echo "  Total Tests:    $TOTAL_TESTS"
        echo "  Passed:         $PASSED_TESTS"
        echo "  Failed:         $FAILED_TESTS"
        echo "  Warnings:       $WARNING_TESTS"
        echo "  Skipped:        $SKIPPED_TESTS"
        echo ""

        local test_duration=$(($(date +%s) - TEST_START_TIME))
        echo "  Test Duration:  ${test_duration}s"

        if [ $FAILED_TESTS -eq 0 ] && [ $WARNING_TESTS -eq 0 ]; then
            echo "  Overall Status: ✓ ALL TESTS PASSED"
        elif [ $FAILED_TESTS -eq 0 ]; then
            echo "  Overall Status: ⚠ PASSED WITH WARNINGS"
        else
            echo "  Overall Status: ✗ TESTS FAILED"
        fi
        echo ""

        # System Information
        echo "SYSTEM INFORMATION"
        echo "══════════════════════════════════════════════════════════════════════════════"
        echo "  Hostname:       $(hostname)"
        echo "  OS:             $(grep PRETTY_NAME /etc/os-release | cut -d '"' -f 2)"
        echo "  Kernel:         $(uname -r)"
        echo "  Architecture:   $(uname -m)"
        if is_lxc; then
            echo "  Container Type: LXC"
            echo "  Container IP:   $(hostname -I | awk '{print $1}')"
        else
            echo "  Container Type: Host/VM"
        fi
        echo ""

        # Detailed Results by Category
        echo "DETAILED TEST RESULTS"
        echo "══════════════════════════════════════════════════════════════════════════════"
        echo ""

        for category in "${TEST_CATEGORIES[@]}"; do
            echo "Category: $category"
            echo "──────────────────────────────────────────────────────────────────────────────"

            for test_name in "${!TEST_RESULTS[@]}"; do
                if [[ "$test_name" == "${category}::"* ]]; then
                    local short_name="${test_name#*::}"
                    local result="${TEST_RESULTS[$test_name]}"
                    local message="${TEST_MESSAGES[$test_name]}"
                    local timing="${TEST_TIMINGS[$test_name]}"

                    case $result in
                        pass) echo "  ✓ $short_name: $message (${timing}ms)" ;;
                        fail) echo "  ✗ $short_name: $message" ;;
                        warn) echo "  ⚠ $short_name: $message" ;;
                        skip) echo "  ○ $short_name: Skipped" ;;
                    esac
                fi
            done
            echo ""
        done

        # Failed Tests and Recommendations
        if [ $FAILED_TESTS -gt 0 ] || [ $WARNING_TESTS -gt 0 ]; then
            echo "ISSUES AND RECOMMENDATIONS"
            echo "══════════════════════════════════════════════════════════════════════════════"
            echo ""

            for test_name in "${!TEST_RESULTS[@]}"; do
                local result="${TEST_RESULTS[$test_name]}"
                if [ "$result" = "fail" ] || [ "$result" = "warn" ]; then
                    local message="${TEST_MESSAGES[$test_name]}"
                    local diagnostic="${TEST_DIAGNOSTICS[$test_name]}"
                    local recommendation="${TEST_RECOMMENDATIONS[$test_name]}"

                    if [ "$result" = "fail" ]; then
                        echo "✗ FAILURE: $test_name"
                    else
                        echo "⚠ WARNING: $test_name"
                    fi
                    echo "  Issue: $message"
                    [ -n "$diagnostic" ] && echo "  Diagnostic: $diagnostic"
                    [ -n "$recommendation" ] && echo "  Recommendation: $recommendation"
                    echo ""
                fi
            done
        fi

        # Performance Metrics
        if [ ${#PERFORMANCE_METRICS[@]} -gt 0 ]; then
            echo "PERFORMANCE METRICS"
            echo "══════════════════════════════════════════════════════════════════════════════"
            for metric in "${!PERFORMANCE_METRICS[@]}"; do
                echo "  ${metric}: ${PERFORMANCE_METRICS[$metric]}"
            done
            echo ""
        fi

        # Footer
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  End of Report"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    } > "$output_file"

    if [ "$OUTPUT_FORMAT" = "text" ] || [ "$OUTPUT_FORMAT" = "all" ]; then
        cat "$output_file"
    fi

    echo -e "${GN}✓${CL} Text report saved to: $output_file" >&2
}

generate_json_report() {
    local output_file="${OUTPUT_DIR}/${REPORT_PREFIX}-$(date +%Y%m%d-%H%M%S).json"
    local test_duration=$(($(date +%s) - TEST_START_TIME))

    {
        echo "{"
        echo "  \"report\": {"
        echo "    \"version\": \"${VERSION}\","
        echo "    \"generated\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "    \"test_mode\": \"${TEST_MODE}\","
        echo "    \"duration_seconds\": $test_duration"
        echo "  },"
        echo "  \"summary\": {"
        echo "    \"total\": $TOTAL_TESTS,"
        echo "    \"passed\": $PASSED_TESTS,"
        echo "    \"failed\": $FAILED_TESTS,"
        echo "    \"warnings\": $WARNING_TESTS,"
        echo "    \"skipped\": $SKIPPED_TESTS,"
        echo "    \"success_rate\": $(awk "BEGIN {printf \"%.2f\", ($PASSED_TESTS/$TOTAL_TESTS)*100}")"
        echo "  },"
        echo "  \"system\": {"
        echo "    \"hostname\": \"$(hostname)\","
        echo "    \"os\": \"$(grep PRETTY_NAME /etc/os-release | cut -d '"' -f 2)\","
        echo "    \"kernel\": \"$(uname -r)\","
        echo "    \"architecture\": \"$(uname -m)\","
        echo "    \"container_type\": \"$(is_lxc && echo 'lxc' || echo 'host')\","
        echo "    \"ip_address\": \"$(hostname -I | awk '{print $1}')\""
        echo "  },"
        echo "  \"tests\": ["

        local first=true
        for test_name in "${!TEST_RESULTS[@]}"; do
            $first || echo ","
            first=false

            local result="${TEST_RESULTS[$test_name]}"
            local message="${TEST_MESSAGES[$test_name]}"
            local diagnostic="${TEST_DIAGNOSTICS[$test_name]}"
            local recommendation="${TEST_RECOMMENDATIONS[$test_name]}"
            local timing="${TEST_TIMINGS[$test_name]}"

            # Escape quotes in strings
            message="${message//\"/\\\"}"
            diagnostic="${diagnostic//\"/\\\"}"
            recommendation="${recommendation//\"/\\\"}"

            echo "    {"
            echo "      \"name\": \"$test_name\","
            echo "      \"result\": \"$result\","
            echo "      \"message\": \"$message\","
            echo "      \"timing_ms\": $timing,"
            echo "      \"diagnostic\": \"$diagnostic\","
            echo "      \"recommendation\": \"$recommendation\""
            echo -n "    }"
        done
        echo ""
        echo "  ],"
        echo "  \"metrics\": {"

        first=true
        for metric in "${!PERFORMANCE_METRICS[@]}"; do
            $first || echo ","
            first=false
            local value="${PERFORMANCE_METRICS[$metric]}"
            echo -n "    \"$metric\": \"$value\""
        done
        echo ""
        echo "  }"
        echo "}"

    } > "$output_file"

    if [ "$OUTPUT_FORMAT" = "json" ]; then
        cat "$output_file"
    fi

    echo -e "${GN}✓${CL} JSON report saved to: $output_file" >&2
}

generate_html_report() {
    local output_file="${OUTPUT_DIR}/${REPORT_PREFIX}-$(date +%Y%m%d-%H%M%S).html"
    local test_duration=$(($(date +%s) - TEST_START_TIME))

    {
        cat << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Waydroid LXC Test Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            line-height: 1.6;
            color: #333;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 50px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .header p { opacity: 0.9; font-size: 1.1em; }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            padding: 30px;
            background: #f8f9fa;
        }
        .summary-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            text-align: center;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .summary-card .number {
            font-size: 3em;
            font-weight: bold;
            margin-bottom: 10px;
        }
        .summary-card .label {
            color: #666;
            text-transform: uppercase;
            font-size: 0.9em;
            letter-spacing: 1px;
        }
        .pass .number { color: #28a745; }
        .fail .number { color: #dc3545; }
        .warn .number { color: #ffc107; }
        .skip .number { color: #6c757d; }
        .content { padding: 30px; }
        .section {
            margin-bottom: 40px;
            border-left: 4px solid #667eea;
            padding-left: 20px;
        }
        .section h2 {
            color: #667eea;
            margin-bottom: 20px;
            font-size: 1.8em;
        }
        .test-category {
            margin-bottom: 30px;
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
        }
        .test-category h3 {
            color: #333;
            margin-bottom: 15px;
            font-size: 1.3em;
        }
        .test-item {
            padding: 12px;
            margin-bottom: 10px;
            background: white;
            border-radius: 5px;
            display: flex;
            align-items: center;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }
        .test-item .icon {
            font-size: 1.5em;
            margin-right: 15px;
            min-width: 30px;
        }
        .test-item.pass .icon { color: #28a745; }
        .test-item.fail .icon { color: #dc3545; }
        .test-item.warn .icon { color: #ffc107; }
        .test-item.skip .icon { color: #6c757d; }
        .test-item .details {
            flex: 1;
        }
        .test-item .name {
            font-weight: bold;
            margin-bottom: 5px;
        }
        .test-item .message {
            color: #666;
            font-size: 0.9em;
        }
        .test-item .timing {
            color: #999;
            font-size: 0.85em;
            margin-left: auto;
        }
        .recommendation {
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 15px;
            margin-top: 10px;
            border-radius: 5px;
        }
        .recommendation strong {
            display: block;
            margin-bottom: 5px;
            color: #856404;
        }
        .metrics {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
            gap: 15px;
            margin-top: 20px;
        }
        .metric {
            background: white;
            padding: 15px;
            border-radius: 5px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }
        .metric .label {
            color: #666;
            font-size: 0.9em;
            margin-bottom: 5px;
        }
        .metric .value {
            font-size: 1.3em;
            font-weight: bold;
            color: #667eea;
        }
        .footer {
            text-align: center;
            padding: 20px;
            background: #f8f9fa;
            color: #666;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🐧 Waydroid LXC Test Report</h1>
EOF
        echo "            <p>Generated: $(date '+%Y-%m-%d %H:%M:%S %Z') | Version: ${VERSION} | Mode: ${TEST_MODE}</p>"
        cat << 'EOF'
        </div>

        <div class="summary">
EOF
        echo "            <div class=\"summary-card\"><div class=\"number\">${TOTAL_TESTS}</div><div class=\"label\">Total Tests</div></div>"
        echo "            <div class=\"summary-card pass\"><div class=\"number\">${PASSED_TESTS}</div><div class=\"label\">Passed</div></div>"
        echo "            <div class=\"summary-card fail\"><div class=\"number\">${FAILED_TESTS}</div><div class=\"label\">Failed</div></div>"
        echo "            <div class=\"summary-card warn\"><div class=\"number\">${WARNING_TESTS}</div><div class=\"label\">Warnings</div></div>"
        echo "            <div class=\"summary-card skip\"><div class=\"number\">${SKIPPED_TESTS}</div><div class=\"label\">Skipped</div></div>"
        cat << 'EOF'
        </div>

        <div class="content">
            <div class="section">
                <h2>System Information</h2>
                <div class="metrics">
EOF
        echo "                    <div class=\"metric\"><div class=\"label\">Hostname</div><div class=\"value\">$(hostname)</div></div>"
        echo "                    <div class=\"metric\"><div class=\"label\">OS</div><div class=\"value\">$(grep PRETTY_NAME /etc/os-release | cut -d '"' -f 2)</div></div>"
        echo "                    <div class=\"metric\"><div class=\"label\">Kernel</div><div class=\"value\">$(uname -r)</div></div>"
        echo "                    <div class=\"metric\"><div class=\"label\">Test Duration</div><div class=\"value\">${test_duration}s</div></div>"
        cat << 'EOF'
                </div>
            </div>

            <div class="section">
                <h2>Test Results</h2>
EOF

        # Generate test results by category
        for category in "${TEST_CATEGORIES[@]}"; do
            echo "                <div class=\"test-category\">"
            echo "                    <h3>${category}</h3>"

            for test_name in "${!TEST_RESULTS[@]}"; do
                if [[ "$test_name" == "${category}::"* ]]; then
                    local short_name="${test_name#*::}"
                    local result="${TEST_RESULTS[$test_name]}"
                    local message="${TEST_MESSAGES[$test_name]}"
                    local timing="${TEST_TIMINGS[$test_name]}"
                    local recommendation="${TEST_RECOMMENDATIONS[$test_name]}"

                    # Escape HTML
                    message="${message//</&lt;}"
                    message="${message//>/&gt;}"
                    recommendation="${recommendation//</&lt;}"
                    recommendation="${recommendation//>/&gt;}"

                    local icon="✓"
                    case $result in
                        fail) icon="✗" ;;
                        warn) icon="⚠" ;;
                        skip) icon="○" ;;
                    esac

                    echo "                    <div class=\"test-item $result\">"
                    echo "                        <div class=\"icon\">$icon</div>"
                    echo "                        <div class=\"details\">"
                    echo "                            <div class=\"name\">$short_name</div>"
                    echo "                            <div class=\"message\">$message</div>"
                    if [ -n "$recommendation" ] && [ "$result" != "pass" ]; then
                        echo "                            <div class=\"recommendation\"><strong>Recommendation:</strong> $recommendation</div>"
                    fi
                    echo "                        </div>"
                    echo "                        <div class=\"timing\">${timing}ms</div>"
                    echo "                    </div>"
                fi
            done

            echo "                </div>"
        done

        cat << 'EOF'
            </div>

            <div class="section">
                <h2>Performance Metrics</h2>
                <div class="metrics">
EOF

        for metric in "${!PERFORMANCE_METRICS[@]}"; do
            echo "                    <div class=\"metric\"><div class=\"label\">${metric}</div><div class=\"value\">${PERFORMANCE_METRICS[$metric]}</div></div>"
        done

        cat << 'EOF'
                </div>
            </div>
        </div>

        <div class="footer">
            <p>Waydroid LXC Comprehensive Testing Framework</p>
            <p>For more information, visit the project repository</p>
        </div>
    </div>
</body>
</html>
EOF

    } > "$output_file"

    echo -e "${GN}✓${CL} HTML report saved to: $output_file" >&2
}

################################################################################
# Main Execution
################################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick)
                TEST_MODE="quick"
                shift
                ;;
            --thorough)
                TEST_MODE="thorough"
                shift
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                if [[ ! "$OUTPUT_FORMAT" =~ ^(text|json|html|all)$ ]]; then
                    echo "ERROR: Invalid format: $OUTPUT_FORMAT" >&2
                    exit 2
                fi
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --ci)
                CI_MODE=true
                shift
                ;;
            --from-host)
                RUN_FROM="host"
                shift
                ;;
            --from-container)
                RUN_FROM="container"
                shift
                ;;
            --auto)
                RUN_FROM="auto"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "ERROR: Unknown option: $1" >&2
                show_help
                exit 2
                ;;
        esac
    done
}

main() {
    parse_arguments "$@"

    # Auto-detect run location if needed
    if [ "$RUN_FROM" = "auto" ]; then
        if is_lxc; then
            RUN_FROM="container"
        else
            RUN_FROM="host"
        fi
    fi

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Print header
    if [ "$OUTPUT_FORMAT" != "json" ] && ! $CI_MODE; then
        print_header "Waydroid LXC Comprehensive System Test"
        echo -e "${BL}Version:${CL} $VERSION"
        echo -e "${BL}Mode:${CL} $TEST_MODE"
        echo -e "${BL}Location:${CL} $RUN_FROM"
        echo -e "${BL}Output:${CL} $OUTPUT_FORMAT"
        echo ""
    fi

    # Run all test categories
    test_system_resources
    test_host_configuration
    test_lxc_configuration
    test_waydroid
    test_wayland
    test_vnc_server
    test_api_server
    test_audio_system
    test_clipboard
    test_gpu_performance
    test_network

    # Generate reports
    case $OUTPUT_FORMAT in
        text)
            generate_text_report
            ;;
        json)
            generate_json_report
            ;;
        html)
            generate_html_report
            ;;
        all)
            generate_text_report
            generate_json_report
            generate_html_report
            ;;
    esac

    # Exit with appropriate code
    if [ $FAILED_TESTS -gt 0 ]; then
        exit 1
    elif [ $WARNING_TESTS -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"
