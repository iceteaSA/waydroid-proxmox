#!/usr/bin/env bash

# Waydroid Performance Monitoring Dashboard
# Real-time monitoring of system resources, Waydroid performance, and services

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/helper-functions.sh" ]; then
    source "${SCRIPT_DIR}/helper-functions.sh"
else
    msg_info() { echo "[INFO] $1"; }
    msg_ok() { echo "[OK] $1"; }
    msg_error() { echo "[ERROR] $1"; }
    msg_warn() { echo "[WARN] $1"; }
    GN="\033[1;92m"
    RD="\033[01;31m"
    YW="\033[1;93m"
    BL="\033[36m"
    CL="\033[m"
fi

# Configuration
REFRESH_INTERVAL=2
LOG_FILE="/var/log/waydroid-performance.log"

# Function to get CPU usage
get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}'
}

# Function to get memory usage
get_memory_usage() {
    free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}'
}

# Function to get memory details
get_memory_details() {
    free -h | grep Mem | awk '{print $3 " / " $2}'
}

# Function to get swap usage
get_swap_usage() {
    free | grep Swap | awk '{if($2>0) printf "%.1f", $3/$2 * 100.0; else print "0"}'
}

# Function to get disk usage
get_disk_usage() {
    df -h / | tail -1 | awk '{print $5}' | tr -d '%'
}

# Function to get load average
get_load_average() {
    uptime | awk -F'load average:' '{print $2}' | xargs
}

# Function to get network stats
get_network_stats() {
    local interface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$interface" ]; then
        local rx_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo 0)
        local rx_mb=$(echo "scale=2; $rx_bytes / 1024 / 1024" | bc)
        local tx_mb=$(echo "scale=2; $tx_bytes / 1024 / 1024" | bc)
        echo "RX: ${rx_mb}MB | TX: ${tx_mb}MB"
    else
        echo "N/A"
    fi
}

# Function to get Waydroid process stats
get_waydroid_stats() {
    local cpu=0
    local mem=0
    local count=0

    while read -r line; do
        local proc_cpu=$(echo "$line" | awk '{print $1}')
        local proc_mem=$(echo "$line" | awk '{print $2}')
        cpu=$(echo "$cpu + $proc_cpu" | bc)
        mem=$(echo "$mem + $proc_mem" | bc)
        count=$((count + 1))
    done < <(ps aux | grep -E "waydroid|sway|wayvnc" | grep -v grep | awk '{print $3, $4}')

    if [ $count -gt 0 ]; then
        echo "CPU: ${cpu}% | MEM: ${mem}% | Processes: $count"
    else
        echo "Not running"
    fi
}

# Function to get service status
get_service_status() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        echo -e "${GN}●${CL} Active"
    elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
        echo -e "${YW}○${CL} Inactive"
    else
        echo -e "${RD}✗${CL} Disabled"
    fi
}

# Function to get API stats
get_api_stats() {
    if curl -sf -m 2 http://localhost:8080/health &>/dev/null; then
        local response_time=$(curl -sf -m 2 -w "%{time_total}" -o /dev/null http://localhost:8080/health 2>/dev/null)
        echo -e "${GN}✓${CL} Healthy (${response_time}s)"
    else
        echo -e "${RD}✗${CL} Unreachable"
    fi
}

# Function to get VNC stats
get_vnc_stats() {
    if pgrep -f wayvnc &>/dev/null; then
        local connections=$(netstat -tn 2>/dev/null | grep :5900 | grep ESTABLISHED | wc -l)
        echo -e "${GN}✓${CL} Running ($connections clients)"
    else
        echo -e "${RD}✗${CL} Not running"
    fi
}

# Function to get GPU usage (Intel)
get_gpu_usage() {
    if command -v intel_gpu_top &>/dev/null && [ -c /dev/dri/card0 ]; then
        # Intel GPU
        timeout 1 intel_gpu_top -s 100 -o - | tail -1 | grep -oP '\d+\.\d+' | head -1 || echo "N/A"
    elif command -v radeontop &>/dev/null; then
        # AMD GPU
        echo "AMD GPU monitoring requires radeontop in interactive mode"
    else
        echo "N/A"
    fi
}

# Function to log performance data
log_performance() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local cpu=$(get_cpu_usage)
    local mem=$(get_memory_usage)
    echo "$timestamp,CPU:$cpu,MEM:$mem" >> "$LOG_FILE"
}

# Function to display dashboard
display_dashboard() {
    clear
    echo -e "${GN}╔══════════════════════════════════════════════════════════════════════╗${CL}"
    echo -e "${GN}║           Waydroid LXC Performance Monitor Dashboard                 ║${CL}"
    echo -e "${GN}╚══════════════════════════════════════════════════════════════════════╝${CL}\n"

    echo -e "${BL}═══ System Resources ═══${CL}"
    printf "%-20s %s\n" "CPU Usage:" "$(get_cpu_usage)%"
    printf "%-20s %s\n" "Memory Usage:" "$(get_memory_usage)% ($(get_memory_details))"
    printf "%-20s %s\n" "Swap Usage:" "$(get_swap_usage)%"
    printf "%-20s %s\n" "Disk Usage:" "$(get_disk_usage)%"
    printf "%-20s %s\n" "Load Average:" "$(get_load_average)"
    echo ""

    echo -e "${BL}═══ Waydroid Services ═══${CL}"
    printf "%-30s %s\n" "Waydroid Container:" "$(get_service_status waydroid-container.service)"
    printf "%-30s %s\n" "Waydroid VNC:" "$(get_service_status waydroid-vnc.service)"
    printf "%-30s %s\n" "Waydroid API:" "$(get_service_status waydroid-api.service)"
    echo ""

    echo -e "${BL}═══ Waydroid Performance ═══${CL}"
    printf "%-30s %s\n" "Waydroid Processes:" "$(get_waydroid_stats)"
    printf "%-30s %s\n" "VNC Server:" "$(get_vnc_stats)"
    printf "%-30s %s\n" "API Server:" "$(get_api_stats)"
    echo ""

    echo -e "${BL}═══ Network ═══${CL}"
    printf "%-30s %s\n" "Interface Stats:" "$(get_network_stats)"
    printf "%-30s %s\n" "IP Address:" "$(hostname -I | awk '{print $1}')"
    echo ""

    if [ -d /dev/dri ]; then
        echo -e "${BL}═══ GPU ═══${CL}"
        printf "%-30s %s\n" "GPU Devices:" "$(ls -1 /dev/dri/ | tr '\n' ' ')"
        if [ -e /dev/dri/card0 ]; then
            printf "%-30s %s\n" "GPU Permissions:" "$(ls -l /dev/dri/card0 | awk '{print $1, $3, $4}')"
        fi
        echo ""
    fi

    echo -e "${BL}═══ Recent Activity ═══${CL}"
    if [ -f /var/log/waydroid-api.log ]; then
        echo "API Last 3 requests:"
        tail -3 /var/log/waydroid-api.log 2>/dev/null | cut -c1-70 || echo "No recent activity"
    else
        echo "No API log available"
    fi
    echo ""

    echo -e "${GN}════════════════════════════════════════════════════════════════════════${CL}"
    echo -e "Press ${GN}Ctrl+C${CL} to exit | Refreshing every ${REFRESH_INTERVAL}s | $(date '+%H:%M:%S')"

    # Log performance data
    log_performance
}

# Main loop
show_help() {
    cat << EOF
${GN}Waydroid Performance Monitor${CL}

Usage: $0 [options]

Options:
    --interval <seconds>    Set refresh interval (default: 2)
    --once                  Display once and exit
    --log-only              Only log performance data, don't display
    --help                  Show this help message

Examples:
    $0                      # Start interactive dashboard
    $0 --once               # Display current stats once
    $0 --interval 5         # Refresh every 5 seconds

Performance logs are saved to: $LOG_FILE
EOF
}

# Parse arguments
ONCE=false
LOG_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --interval)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        --once)
            ONCE=true
            shift
            ;;
        --log-only)
            LOG_ONLY=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Create log file if it doesn't exist
touch "$LOG_FILE" 2>/dev/null || true

if [ "$LOG_ONLY" = true ]; then
    # Just log once and exit
    log_performance
    exit 0
fi

if [ "$ONCE" = true ]; then
    # Display once and exit
    display_dashboard
else
    # Continuous monitoring
    trap 'echo -e "\n\n${GN}Monitoring stopped.${CL}\n"; exit 0' INT TERM

    while true; do
        display_dashboard
        sleep "$REFRESH_INTERVAL"
    done
fi
