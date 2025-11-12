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
    # Additional colors for better formatting
    PL="\033[35m"    # Purple
    CY="\033[96m"    # Cyan
    OR="\033[38;5;208m"  # Orange
    BD="\033[1m"     # Bold
fi

# Configuration
REFRESH_INTERVAL=2
LOG_FILE="/var/log/waydroid-performance.log"
HISTORICAL_LOG="/var/log/waydroid-performance-history.log"
JSON_EXPORT_FILE="/var/log/waydroid-performance.json"

# Alert Configuration
ALERT_ENABLED=false
ALERT_CPU_THRESHOLD=80
ALERT_MEMORY_THRESHOLD=85
ALERT_DISK_THRESHOLD=90
ALERT_WEBHOOK_URL=""  # Set this for webhook alerts (e.g., Slack, Discord)
ALERT_EMAIL=""        # Set this for email alerts

# Command availability checks
HAS_BC=false
HAS_CURL=false
HAS_NETSTAT=false
HAS_SS=false
HAS_INTEL_GPU_TOP=false

# GPU monitoring optimization
GPU_MONITOR_PID=""
GPU_FIFO="/tmp/gpu_monitor_$$"

# Check command availability
check_commands() {
    command -v bc &>/dev/null && HAS_BC=true
    command -v curl &>/dev/null && HAS_CURL=true
    command -v netstat &>/dev/null && HAS_NETSTAT=true
    command -v ss &>/dev/null && HAS_SS=true
    command -v intel_gpu_top &>/dev/null && [ -c /dev/dri/card0 ] && HAS_INTEL_GPU_TOP=true

    # Warning messages for missing commands
    if [ "$HAS_BC" = false ]; then
        msg_warn "bc not found - some calculations may be limited"
    fi
    if [ "$HAS_CURL" = false ]; then
        msg_warn "curl not found - API health checks disabled"
    fi
    if [ "$HAS_NETSTAT" = false ] && [ "$HAS_SS" = false ]; then
        msg_warn "netstat and ss not found - VNC client counting disabled"
    fi
}

# Initialize
check_commands

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

        if [ "$HAS_BC" = true ]; then
            local rx_mb=$(echo "scale=2; $rx_bytes / 1024 / 1024" | bc)
            local tx_mb=$(echo "scale=2; $tx_bytes / 1024 / 1024" | bc)
            echo "RX: ${rx_mb}MB | TX: ${tx_mb}MB"
        else
            # Fallback to awk if bc is not available
            local rx_mb=$(awk "BEGIN {printf \"%.2f\", $rx_bytes / 1024 / 1024}")
            local tx_mb=$(awk "BEGIN {printf \"%.2f\", $tx_bytes / 1024 / 1024}")
            echo "RX: ${rx_mb}MB | TX: ${tx_mb}MB"
        fi
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

        if [ "$HAS_BC" = true ]; then
            cpu=$(echo "$cpu + $proc_cpu" | bc)
            mem=$(echo "$mem + $proc_mem" | bc)
        else
            cpu=$(awk "BEGIN {printf \"%.1f\", $cpu + $proc_cpu}")
            mem=$(awk "BEGIN {printf \"%.1f\", $mem + $proc_mem}")
        fi
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
    if [ "$HAS_CURL" = false ]; then
        echo -e "${YW}⚠${CL} curl not available"
        return
    fi

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
        local connections=0

        if [ "$HAS_NETSTAT" = true ]; then
            connections=$(netstat -tn 2>/dev/null | grep :5900 | grep ESTABLISHED | wc -l)
        elif [ "$HAS_SS" = true ]; then
            connections=$(ss -tn 2>/dev/null | grep :5900 | grep ESTAB | wc -l)
        fi

        echo -e "${GN}✓${CL} Running ($connections clients)"
    else
        echo -e "${RD}✗${CL} Not running"
    fi
}

# Start background GPU monitoring (efficient - no process spawning per refresh)
start_gpu_monitor() {
    if [ "$HAS_INTEL_GPU_TOP" = false ]; then
        return
    fi

    # Create FIFO for GPU data
    mkfifo "$GPU_FIFO" 2>/dev/null || true

    # Start background GPU monitor
    {
        while true; do
            if [ -c /dev/dri/card0 ]; then
                gpu_usage=$(timeout 1 intel_gpu_top -s 100 -o - 2>/dev/null | tail -1 | grep -oP '\d+\.\d+' | head -1 || echo "0.0")
                echo "$gpu_usage" > "$GPU_FIFO" 2>/dev/null || break
            fi
            sleep 1
        done
    } &
    GPU_MONITOR_PID=$!
}

# Stop background GPU monitoring
stop_gpu_monitor() {
    if [ -n "$GPU_MONITOR_PID" ]; then
        kill "$GPU_MONITOR_PID" 2>/dev/null || true
        wait "$GPU_MONITOR_PID" 2>/dev/null || true
    fi
    rm -f "$GPU_FIFO" 2>/dev/null || true
}

# Function to get GPU usage (optimized - reads from background monitor)
get_gpu_usage() {
    if [ "$HAS_INTEL_GPU_TOP" = false ]; then
        echo "N/A"
        return
    fi

    if [ -p "$GPU_FIFO" ]; then
        # Read from FIFO with timeout
        local gpu_val
        if read -t 0.1 gpu_val < "$GPU_FIFO" 2>/dev/null; then
            echo "${gpu_val}%"
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

# Function to send alerts
send_alert() {
    local alert_type="$1"
    local alert_message="$2"
    local alert_value="$3"

    if [ "$ALERT_ENABLED" = false ]; then
        return
    fi

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local alert_text="[ALERT] $timestamp - $alert_type: $alert_message (Value: $alert_value)"

    # Log alert
    echo "$alert_text" >> "$LOG_FILE"

    # Webhook alert (Slack, Discord, etc.)
    if [ -n "$ALERT_WEBHOOK_URL" ] && [ "$HAS_CURL" = true ]; then
        local json_payload="{\"text\":\"$alert_text\"}"
        curl -X POST -H 'Content-Type: application/json' \
             -d "$json_payload" \
             "$ALERT_WEBHOOK_URL" &>/dev/null || true
    fi

    # Email alert (requires mail command)
    if [ -n "$ALERT_EMAIL" ] && command -v mail &>/dev/null; then
        echo "$alert_message" | mail -s "Waydroid Monitor Alert: $alert_type" "$ALERT_EMAIL" || true
    fi
}

# Function to check thresholds and trigger alerts
check_alerts() {
    local cpu=$(get_cpu_usage)
    local mem=$(get_memory_usage)
    local disk=$(get_disk_usage)

    # CPU alert
    if (( $(echo "$cpu > $ALERT_CPU_THRESHOLD" | bc -l 2>/dev/null || echo 0) )); then
        send_alert "HIGH CPU" "CPU usage exceeded threshold" "${cpu}%"
    fi

    # Memory alert
    if (( $(echo "$mem > $ALERT_MEMORY_THRESHOLD" | bc -l 2>/dev/null || echo 0) )); then
        send_alert "HIGH MEMORY" "Memory usage exceeded threshold" "${mem}%"
    fi

    # Disk alert
    if (( $(echo "$disk > $ALERT_DISK_THRESHOLD" | bc -l 2>/dev/null || echo 0) )); then
        send_alert "HIGH DISK" "Disk usage exceeded threshold" "${disk}%"
    fi
}

# Function to export metrics to JSON
export_to_json() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local cpu=$(get_cpu_usage)
    local mem=$(get_memory_usage)
    local mem_details=$(get_memory_details)
    local swap=$(get_swap_usage)
    local disk=$(get_disk_usage)
    local load=$(get_load_average)
    local gpu=$(get_gpu_usage)

    # Build JSON
    cat > "$JSON_EXPORT_FILE" << EOF
{
  "timestamp": "$timestamp",
  "system": {
    "cpu_usage": $cpu,
    "memory_usage": $mem,
    "memory_details": "$mem_details",
    "swap_usage": $swap,
    "disk_usage": $disk,
    "load_average": "$load",
    "gpu_usage": "$gpu"
  },
  "services": {
    "waydroid_container": "$(get_service_status waydroid-container.service | sed 's/\x1b\[[0-9;]*m//g')",
    "waydroid_vnc": "$(get_service_status waydroid-vnc.service | sed 's/\x1b\[[0-9;]*m//g')",
    "waydroid_api": "$(get_service_status waydroid-api.service | sed 's/\x1b\[[0-9;]*m//g')"
  },
  "waydroid": {
    "processes": "$(get_waydroid_stats)"
  }
}
EOF
}

# Function to log performance data
log_performance() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local cpu=$(get_cpu_usage)
    local mem=$(get_memory_usage)
    echo "$timestamp,CPU:$cpu,MEM:$mem" >> "$LOG_FILE"
}

# Function to log historical data
log_historical() {
    if [ "$ENABLE_HISTORY" != true ]; then
        return
    fi

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local epoch=$(date +%s)
    local cpu=$(get_cpu_usage)
    local mem=$(get_memory_usage)
    local disk=$(get_disk_usage)
    local gpu=$(get_gpu_usage)

    # CSV format for easy parsing
    echo "$epoch,$timestamp,$cpu,$mem,$disk,$gpu" >> "$HISTORICAL_LOG"

    # Rotate log if too large (keep last 10000 lines)
    if [ -f "$HISTORICAL_LOG" ]; then
        local lines=$(wc -l < "$HISTORICAL_LOG")
        if [ "$lines" -gt 10000 ]; then
            tail -5000 "$HISTORICAL_LOG" > "${HISTORICAL_LOG}.tmp"
            mv "${HISTORICAL_LOG}.tmp" "$HISTORICAL_LOG"
        fi
    fi
}

# Function to get colored value based on threshold
get_colored_value() {
    local value=$1
    local threshold_warn=$2
    local threshold_crit=$3
    local suffix=$4

    if (( $(echo "$value >= $threshold_crit" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "${RD}${value}${suffix}${CL}"
    elif (( $(echo "$value >= $threshold_warn" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "${YW}${value}${suffix}${CL}"
    else
        echo -e "${GN}${value}${suffix}${CL}"
    fi
}

# Function to display dashboard
display_dashboard() {
    clear

    # Header with gradient effect
    echo -e "${BD}${CY}╔════════════════════════════════════════════════════════════════════════════╗${CL}"
    echo -e "${BD}${CY}║${CL}${BD}            Waydroid LXC Performance Monitor Dashboard                     ${CY}║${CL}"
    echo -e "${BD}${CY}╚════════════════════════════════════════════════════════════════════════════╝${CL}\n"

    # System Resources Section
    echo -e "${BD}${BL}▓▒░ System Resources ░▒▓${CL}"
    local cpu=$(get_cpu_usage)
    local mem=$(get_memory_usage)
    local swap=$(get_swap_usage)
    local disk=$(get_disk_usage)

    printf "  ${BD}%-20s${CL} %s\n" "CPU Usage:" "$(get_colored_value "$cpu" 60 80 "%")"
    printf "  ${BD}%-20s${CL} %s ($(get_memory_details))\n" "Memory Usage:" "$(get_colored_value "$mem" 70 85 "%")"
    printf "  ${BD}%-20s${CL} %s\n" "Swap Usage:" "$(get_colored_value "$swap" 50 75 "%")"
    printf "  ${BD}%-20s${CL} %s\n" "Disk Usage:" "$(get_colored_value "$disk" 80 90 "%")"
    printf "  ${BD}%-20s${CL} ${CY}%s${CL}\n" "Load Average:" "$(get_load_average)"
    echo ""

    # Waydroid Services Section
    echo -e "${BD}${PL}▓▒░ Waydroid Services ░▒▓${CL}"
    printf "  ${BD}%-25s${CL} %s\n" "Container Service:" "$(get_service_status waydroid-container.service)"
    printf "  ${BD}%-25s${CL} %s\n" "VNC Service:" "$(get_service_status waydroid-vnc.service)"
    printf "  ${BD}%-25s${CL} %s\n" "API Service:" "$(get_service_status waydroid-api.service)"
    echo ""

    # Waydroid Performance Section
    echo -e "${BD}${OR}▓▒░ Waydroid Performance ░▒▓${CL}"
    printf "  ${BD}%-25s${CL} %s\n" "Processes:" "$(get_waydroid_stats)"
    printf "  ${BD}%-25s${CL} %s\n" "VNC Server:" "$(get_vnc_stats)"
    printf "  ${BD}%-25s${CL} %s\n" "API Server:" "$(get_api_stats)"
    echo ""

    # Network Section
    echo -e "${BD}${GN}▓▒░ Network ░▒▓${CL}"
    printf "  ${BD}%-25s${CL} ${CY}%s${CL}\n" "Interface Stats:" "$(get_network_stats)"
    printf "  ${BD}%-25s${CL} ${CY}%s${CL}\n" "IP Address:" "$(hostname -I | awk '{print $1}')"
    echo ""

    # GPU Section
    if [ -d /dev/dri ]; then
        echo -e "${BD}${YW}▓▒░ GPU ░▒▓${CL}"
        printf "  ${BD}%-25s${CL} ${CY}%s${CL}\n" "GPU Devices:" "$(ls -1 /dev/dri/ | tr '\n' ' ')"
        if [ "$HAS_INTEL_GPU_TOP" = true ]; then
            printf "  ${BD}%-25s${CL} ${CY}%s${CL}\n" "GPU Usage:" "$(get_gpu_usage)"
        fi
        if [ -e /dev/dri/card0 ]; then
            printf "  ${BD}%-25s${CL} ${CY}%s${CL}\n" "GPU Permissions:" "$(ls -l /dev/dri/card0 | awk '{print $1, $3, $4}')"
        fi
        echo ""
    fi

    # Recent Activity Section
    echo -e "${BD}${BL}▓▒░ Recent Activity ░▒▓${CL}"
    if [ -f /var/log/waydroid-api.log ]; then
        echo "  API Last 3 requests:"
        tail -3 /var/log/waydroid-api.log 2>/dev/null | sed 's/^/    /' | cut -c1-74 || echo "    No recent activity"
    else
        echo "  No API log available"
    fi
    echo ""

    # Alert Status
    if [ "$ALERT_ENABLED" = true ]; then
        echo -e "${BD}${RD}▓▒░ Alert Status ░▒▓${CL}"
        echo -e "  ${GN}✓${CL} Alerts enabled | CPU: ${ALERT_CPU_THRESHOLD}% | MEM: ${ALERT_MEMORY_THRESHOLD}% | DISK: ${ALERT_DISK_THRESHOLD}%"
        echo ""
    fi

    # Footer
    echo -e "${BD}${CY}────────────────────────────────────────────────────────────────────────────${CL}"
    local current_time=$(date '+%H:%M:%S')
    echo -e "  ${GN}●${CL} Press ${BD}${GN}Ctrl+C${CL} to exit  ${YW}●${CL} Refresh: ${REFRESH_INTERVAL}s  ${BL}●${CL} Time: ${current_time}"

    if [ "$ENABLE_JSON" = true ]; then
        echo -e "  ${CY}●${CL} JSON export: ${JSON_EXPORT_FILE}"
    fi

    if [ "$ENABLE_HISTORY" = true ]; then
        echo -e "  ${PL}●${CL} History log: ${HISTORICAL_LOG}"
    fi
    echo ""

    # Call monitoring functions
    log_performance

    if [ "$ENABLE_HISTORY" = true ]; then
        log_historical
    fi

    if [ "$ENABLE_JSON" = true ]; then
        export_to_json
    fi

    if [ "$ALERT_ENABLED" = true ]; then
        check_alerts
    fi
}

# Main loop
show_help() {
    cat << EOF
${BD}${GN}Waydroid Performance Monitor${CL}

${BD}Usage:${CL} $0 [options]

${BD}Options:${CL}
    ${GN}--interval <seconds>${CL}       Set refresh interval (default: 2)
    ${GN}--once${CL}                     Display once and exit
    ${GN}--log-only${CL}                 Only log performance data, don't display
    ${GN}--enable-history${CL}           Enable historical data logging
    ${GN}--enable-json${CL}              Enable JSON export for external tools
    ${GN}--enable-alerts${CL}            Enable alerting (requires thresholds)
    ${GN}--alert-cpu <percent>${CL}      CPU alert threshold (default: 80)
    ${GN}--alert-memory <percent>${CL}   Memory alert threshold (default: 85)
    ${GN}--alert-disk <percent>${CL}     Disk alert threshold (default: 90)
    ${GN}--alert-webhook <url>${CL}      Webhook URL for alerts (Slack, Discord, etc.)
    ${GN}--alert-email <email>${CL}      Email address for alerts
    ${GN}--help${CL}                     Show this help message

${BD}Examples:${CL}
    ${CY}$0${CL}
        Start interactive dashboard

    ${CY}$0 --once${CL}
        Display current stats once

    ${CY}$0 --interval 5 --enable-history --enable-json${CL}
        Refresh every 5 seconds with history and JSON export

    ${CY}$0 --enable-alerts --alert-cpu 70 --alert-webhook https://hooks.slack.com/...${CL}
        Enable alerts with custom CPU threshold and Slack webhook

    ${CY}$0 --enable-history --enable-json --enable-alerts${CL}
        Full monitoring with all features enabled

${BD}Log Files:${CL}
    Performance log:  ${LOG_FILE}
    Historical log:   ${HISTORICAL_LOG}
    JSON export:      ${JSON_EXPORT_FILE}

${BD}Alert Configuration:${CL}
    Set thresholds via command line or edit the script configuration
    Supports webhook notifications (Slack, Discord, etc.) and email alerts

${BD}GPU Monitoring:${CL}
    Intel GPU: Requires intel_gpu_top and /dev/dri/card0 access
    AMD GPU: Not yet supported (radeontop integration planned)
EOF
}

# Parse arguments
ONCE=false
LOG_ONLY=false
ENABLE_HISTORY=false
ENABLE_JSON=false

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
        --enable-history)
            ENABLE_HISTORY=true
            shift
            ;;
        --enable-json)
            ENABLE_JSON=true
            shift
            ;;
        --enable-alerts)
            ALERT_ENABLED=true
            shift
            ;;
        --alert-cpu)
            ALERT_CPU_THRESHOLD="$2"
            shift 2
            ;;
        --alert-memory)
            ALERT_MEMORY_THRESHOLD="$2"
            shift 2
            ;;
        --alert-disk)
            ALERT_DISK_THRESHOLD="$2"
            shift 2
            ;;
        --alert-webhook)
            ALERT_WEBHOOK_URL="$2"
            shift 2
            ;;
        --alert-email)
            ALERT_EMAIL="$2"
            shift 2
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

# Create log files if they don't exist
touch "$LOG_FILE" 2>/dev/null || true

if [ "$ENABLE_HISTORY" = true ]; then
    touch "$HISTORICAL_LOG" 2>/dev/null || true
fi

# Cleanup function
cleanup() {
    echo -e "\n\n${GN}Cleaning up...${CL}"
    stop_gpu_monitor
    echo -e "${GN}Monitoring stopped.${CL}\n"
    exit 0
}

if [ "$LOG_ONLY" = true ]; then
    # Just log once and exit
    log_performance
    if [ "$ENABLE_HISTORY" = true ]; then
        log_historical
    fi
    if [ "$ENABLE_JSON" = true ]; then
        export_to_json
    fi
    exit 0
fi

if [ "$ONCE" = true ]; then
    # Start GPU monitor for single display
    start_gpu_monitor
    sleep 1  # Give GPU monitor time to start

    # Display once and exit
    display_dashboard

    # Cleanup
    stop_gpu_monitor
else
    # Continuous monitoring
    trap cleanup INT TERM

    # Start GPU monitor
    start_gpu_monitor

    # Give GPU monitor time to initialize
    if [ "$HAS_INTEL_GPU_TOP" = true ]; then
        sleep 1
    fi

    while true; do
        display_dashboard
        sleep "$REFRESH_INTERVAL"
    done
fi
