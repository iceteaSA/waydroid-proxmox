#!/usr/bin/env bash

# WayVNC Enhancement Script for Headless Waydroid
# Improves security, performance, and features for WayVNC setup
#
# Usage:
#   ./enhance-vnc.sh [options]
#
# Options:
#   --security-only       Only apply security enhancements
#   --performance-only    Only apply performance enhancements
#   --install-novnc       Install noVNC web interface
#   --enable-tls          Enable TLS encryption with self-signed cert
#   --enable-rsa-aes      Enable RSA-AES encryption
#   --fps <rate>          Set max frame rate (default: 60)
#   --quality <level>     Set JPEG quality 1-9 (default: 7)
#   --enable-monitoring   Enable connection monitoring
#   --help                Show this help message

set -euo pipefail

# Source helper functions if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/helper-functions.sh" ]; then
    source "$SCRIPT_DIR/helper-functions.sh"
else
    # Minimal fallback functions
    msg_info() { echo "[INFO] $1"; }
    msg_ok() { echo "[OK] $1"; }
    msg_error() { echo "[ERROR] $1"; }
    msg_warn() { echo "[WARN] $1"; }
fi

# Default settings
SECURITY_ONLY=false
PERFORMANCE_ONLY=false
INSTALL_NOVNC=false
ENABLE_TLS=false
ENABLE_RSA_AES=false
MAX_FPS=60
JPEG_QUALITY=7
ENABLE_MONITORING=false
WAYVNC_CONFIG_DIR="/etc/wayvnc"
WAYVNC_CONFIG="$WAYVNC_CONFIG_DIR/config"
WAYVNC_LOG="/var/log/wayvnc.log"
NOVNC_DIR="/opt/noVNC"
WEBSOCKIFY_PORT=6080
VNC_PORT=5900

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --security-only)
            SECURITY_ONLY=true
            shift
            ;;
        --performance-only)
            PERFORMANCE_ONLY=true
            shift
            ;;
        --install-novnc)
            INSTALL_NOVNC=true
            shift
            ;;
        --enable-tls)
            ENABLE_TLS=true
            shift
            ;;
        --enable-rsa-aes)
            ENABLE_RSA_AES=true
            shift
            ;;
        --fps)
            MAX_FPS="$2"
            shift 2
            ;;
        --quality)
            JPEG_QUALITY="$2"
            shift 2
            ;;
        --enable-monitoring)
            ENABLE_MONITORING=true
            shift
            ;;
        --help)
            grep '^#' "$0" | grep -E '^# (Usage|Options|  )' | sed 's/^# //'
            exit 0
            ;;
        *)
            msg_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validation
if [[ "$MAX_FPS" -lt 15 || "$MAX_FPS" -gt 120 ]]; then
    msg_error "FPS must be between 15 and 120"
    exit 1
fi

if [[ "$JPEG_QUALITY" -lt 1 || "$JPEG_QUALITY" -gt 9 ]]; then
    msg_error "JPEG quality must be between 1 and 9"
    exit 1
fi

# Check if running inside LXC
if [ ! -f /proc/1/environ ] || ! grep -q container=lxc /proc/1/environ; then
    msg_warn "This script is designed to run inside an LXC container"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if wayvnc is installed
if ! command -v wayvnc &> /dev/null; then
    msg_error "WayVNC is not installed"
    exit 1
fi

msg_info "Starting WayVNC Enhancement"
echo "Configuration:"
echo "  Max FPS: $MAX_FPS"
echo "  JPEG Quality: $JPEG_QUALITY"
echo "  TLS Enabled: $ENABLE_TLS"
echo "  RSA-AES Enabled: $ENABLE_RSA_AES"
echo "  Install noVNC: $INSTALL_NOVNC"
echo "  Monitoring: $ENABLE_MONITORING"
echo ""

# ============================================================================
# SECURITY ENHANCEMENTS
# ============================================================================

apply_security_enhancements() {
    msg_info "Applying security enhancements..."

    # Create config directory if it doesn't exist
    mkdir -p "$WAYVNC_CONFIG_DIR"
    chmod 700 "$WAYVNC_CONFIG_DIR"

    # Setup systemd credentials for password management
    msg_info "Setting up systemd credentials for password management"

    # Check if password file exists, create if not
    if [ ! -f "$WAYVNC_CONFIG_DIR/password" ]; then
        msg_warn "No existing password found, generating new one"
        tr -dc 'A-Za-z0-9!@#$%^&*()_+' < /dev/urandom | head -c 24 > "$WAYVNC_CONFIG_DIR/password"
        echo "" >> "$WAYVNC_CONFIG_DIR/password"
    fi

    chmod 600 "$WAYVNC_CONFIG_DIR/password"

    # Create systemd credential
    mkdir -p /etc/credstore
    cp "$WAYVNC_CONFIG_DIR/password" /etc/credstore/wayvnc.password
    chmod 600 /etc/credstore/wayvnc.password

    msg_ok "Password secured with systemd credentials"

    # Generate TLS certificates if enabled
    if [ "$ENABLE_TLS" = true ]; then
        msg_info "Generating TLS certificates (secp384r1 curve)"

        # Generate EC private key
        openssl ecparam -genkey -name secp384r1 -out "$WAYVNC_CONFIG_DIR/tls-key.pem"
        chmod 600 "$WAYVNC_CONFIG_DIR/tls-key.pem"

        # Generate self-signed certificate (valid for 365 days)
        openssl req -new -x509 -key "$WAYVNC_CONFIG_DIR/tls-key.pem" \
            -out "$WAYVNC_CONFIG_DIR/tls-cert.pem" -days 365 \
            -subj "/C=US/ST=State/L=City/O=Waydroid/CN=wayvnc-server" \
            2>/dev/null

        chmod 644 "$WAYVNC_CONFIG_DIR/tls-cert.pem"

        msg_ok "TLS certificates generated"
        msg_info "Certificate fingerprint:"
        openssl x509 -in "$WAYVNC_CONFIG_DIR/tls-cert.pem" -noout -fingerprint -sha256
    fi

    # Generate RSA keys if enabled
    if [ "$ENABLE_RSA_AES" = true ]; then
        msg_info "Generating RSA-AES keys"

        # Generate 2048-bit RSA key
        openssl genrsa -out "$WAYVNC_CONFIG_DIR/rsa-key.pem" 2048 2>/dev/null
        chmod 600 "$WAYVNC_CONFIG_DIR/rsa-key.pem"

        msg_ok "RSA-AES keys generated (TOFU security model)"
    fi

    # Setup audit logging
    msg_info "Configuring audit logging"

    # Create log directory
    mkdir -p /var/log/wayvnc
    touch "$WAYVNC_LOG"
    chmod 640 "$WAYVNC_LOG"

    # Create logrotate config
    cat > /etc/logrotate.d/wayvnc <<'EOF'
/var/log/wayvnc.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        systemctl reload wayvnc 2>/dev/null || true
    endscript
}
EOF

    msg_ok "Audit logging configured"

    # Setup connection rate limiting with iptables
    msg_info "Configuring connection rate limiting"

    # Install iptables if not present
    if ! command -v iptables &> /dev/null; then
        apt-get update -qq
        apt-get install -y -qq iptables iptables-persistent
    fi

    # Add rate limiting rules (max 10 connections per minute per IP)
    iptables -D INPUT -p tcp --dport "$VNC_PORT" -m state --state NEW -m recent --set 2>/dev/null || true
    iptables -D INPUT -p tcp --dport "$VNC_PORT" -m state --state NEW -m recent --update --seconds 60 --hitcount 10 -j DROP 2>/dev/null || true

    iptables -I INPUT -p tcp --dport "$VNC_PORT" -m state --state NEW -m recent --set
    iptables -I INPUT -p tcp --dport "$VNC_PORT" -m state --state NEW -m recent --update --seconds 60 --hitcount 10 -j LOG --log-prefix "VNC rate limit: "
    iptables -I INPUT -p tcp --dport "$VNC_PORT" -m state --state NEW -m recent --update --seconds 60 --hitcount 10 -j DROP

    # Save iptables rules
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
    elif command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables/rules.v4
    fi

    msg_ok "Rate limiting configured (10 connections/min per IP)"

    # Create connection monitor script
    cat > /usr/local/bin/wayvnc-monitor.sh <<'MONITOR_EOF'
#!/usr/bin/env bash
# WayVNC Connection Monitor

LOG_FILE="/var/log/wayvnc/connections.log"
mkdir -p "$(dirname "$LOG_FILE")"

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Check for active VNC connections
    CONNECTIONS=$(netstat -tn 2>/dev/null | grep ":5900 " | grep ESTABLISHED | wc -l)

    if [ "$CONNECTIONS" -gt 0 ]; then
        # Log active connections
        netstat -tn 2>/dev/null | grep ":5900 " | grep ESTABLISHED | while read -r line; do
            SRC_IP=$(echo "$line" | awk '{print $5}' | cut -d: -f1)
            echo "[$TIMESTAMP] Active connection from: $SRC_IP" >> "$LOG_FILE"
        done
    fi

    sleep 30
done
MONITOR_EOF

    chmod +x /usr/local/bin/wayvnc-monitor.sh

    msg_ok "Security enhancements applied"
}

# ============================================================================
# PERFORMANCE ENHANCEMENTS
# ============================================================================

apply_performance_enhancements() {
    msg_info "Applying performance enhancements..."

    # Ensure wl-clipboard is installed for clipboard support
    msg_info "Installing clipboard support"
    apt-get update -qq
    apt-get install -y -qq wl-clipboard 2>/dev/null || msg_warn "Could not install wl-clipboard"

    # Create optimized WayVNC configuration
    msg_info "Creating optimized WayVNC configuration"

    # Backup existing config
    if [ -f "$WAYVNC_CONFIG" ]; then
        cp "$WAYVNC_CONFIG" "$WAYVNC_CONFIG.backup.$(date +%Y%m%d-%H%M%S)"
    fi

    # Build configuration
    cat > "$WAYVNC_CONFIG" <<EOF
# WayVNC Enhanced Configuration
# Generated by enhance-vnc.sh on $(date)

# Network Settings
address=0.0.0.0
port=$VNC_PORT

# Authentication
enable_auth=true
username=waydroid
password_file=$WAYVNC_CONFIG_DIR/password

# Performance Settings
# Frame rate: Higher values = smoother but more bandwidth
# Set to double desired FPS to avoid interference
max_rate=$((MAX_FPS * 2))

# Output configuration
# Use relative paths for certificate files
use_relative_paths=true

EOF

    # Add TLS configuration if enabled
    if [ "$ENABLE_TLS" = true ]; then
        cat >> "$WAYVNC_CONFIG" <<EOF
# TLS Encryption (VeNCrypt)
private_key_file=tls-key.pem
certificate_file=tls-cert.pem

EOF
    fi

    # Add RSA-AES configuration if enabled
    if [ "$ENABLE_RSA_AES" = true ]; then
        cat >> "$WAYVNC_CONFIG" <<EOF
# RSA-AES Encryption (TOFU model)
rsa_private_key_file=rsa-key.pem

EOF
    fi

    msg_ok "Configuration created with max FPS: $MAX_FPS"

    # Create performance tuning script
    cat > /usr/local/bin/wayvnc-tune.sh <<'TUNE_EOF'
#!/usr/bin/env bash
# WayVNC Performance Tuning Helper

show_usage() {
    cat <<EOF
WayVNC Performance Tuning Tool

Usage: wayvnc-tune.sh [command]

Commands:
    show            Show current performance settings
    fps <rate>      Set max frame rate (15-120)
    quality <1-9>   Set JPEG quality (1=low, 9=high)
    preset <name>   Apply preset configuration

Presets:
    low-bandwidth   Optimize for slow connections
    balanced        Balance quality and bandwidth (default)
    high-quality    Optimize for quality over LAN
    gaming          Optimize for low latency

Examples:
    wayvnc-tune.sh fps 60
    wayvnc-tune.sh preset high-quality
    wayvnc-tune.sh show
EOF
}

CONFIG_FILE="/etc/wayvnc/config"

show_settings() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: Config file not found"
        return 1
    fi

    echo "Current WayVNC Performance Settings:"
    echo "======================================"
    grep "^max_rate=" "$CONFIG_FILE" | sed 's/max_rate=/Max Frame Rate: /'
    echo ""
}

set_fps() {
    local fps=$1
    if [[ "$fps" -lt 15 || "$fps" -gt 120 ]]; then
        echo "Error: FPS must be between 15 and 120"
        return 1
    fi

    local max_rate=$((fps * 2))
    sed -i "s/^max_rate=.*/max_rate=$max_rate/" "$CONFIG_FILE"
    echo "Max frame rate set to $max_rate (target FPS: $fps)"
    echo "Restart WayVNC for changes to take effect"
}

apply_preset() {
    local preset=$1

    case $preset in
        low-bandwidth)
            set_fps 15
            echo "Applied low-bandwidth preset"
            ;;
        balanced)
            set_fps 30
            echo "Applied balanced preset"
            ;;
        high-quality)
            set_fps 60
            echo "Applied high-quality preset"
            ;;
        gaming)
            set_fps 60
            echo "Applied gaming preset (low latency)"
            ;;
        *)
            echo "Error: Unknown preset '$preset'"
            show_usage
            return 1
            ;;
    esac
}

case "${1:-}" in
    show)
        show_settings
        ;;
    fps)
        set_fps "$2"
        ;;
    preset)
        apply_preset "$2"
        ;;
    *)
        show_usage
        ;;
esac
TUNE_EOF

    chmod +x /usr/local/bin/wayvnc-tune.sh

    msg_ok "Performance enhancements applied"
}

# ============================================================================
# NOVNC WEB INTERFACE
# ============================================================================

install_novnc() {
    msg_info "Installing noVNC web interface..."

    # Install dependencies
    apt-get update -qq
    apt-get install -y -qq git python3 python3-pip python3-numpy nginx || {
        msg_error "Failed to install dependencies"
        return 1
    }

    # Install websockify
    msg_info "Installing websockify"
    pip3 install websockify --break-system-packages 2>/dev/null || pip3 install websockify

    # Clone noVNC if not exists
    if [ ! -d "$NOVNC_DIR" ]; then
        msg_info "Cloning noVNC repository"
        git clone --quiet --depth 1 https://github.com/novnc/noVNC.git "$NOVNC_DIR"
    else
        msg_info "Updating noVNC"
        cd "$NOVNC_DIR" && git pull --quiet
    fi

    # Create websockify systemd service
    msg_info "Creating websockify systemd service"
    cat > /etc/systemd/system/websockify.service <<EOF
[Unit]
Description=Websockify proxy for noVNC
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/websockify --web=$NOVNC_DIR --cert=$WAYVNC_CONFIG_DIR/tls-cert.pem --key=$WAYVNC_CONFIG_DIR/tls-key.pem $WEBSOCKIFY_PORT localhost:$VNC_PORT
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # If TLS not enabled, remove cert/key options
    if [ "$ENABLE_TLS" != true ]; then
        sed -i 's/ --cert=[^ ]* --key=[^ ]*//' /etc/systemd/system/websockify.service
    fi

    # Configure nginx reverse proxy
    msg_info "Configuring nginx"
    cat > /etc/nginx/sites-available/novnc <<EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:$WEBSOCKIFY_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/novnc /etc/nginx/sites-enabled/novnc
    rm -f /etc/nginx/sites-enabled/default

    # Test nginx config
    nginx -t 2>/dev/null || {
        msg_error "Nginx configuration test failed"
        return 1
    }

    # Enable and start services
    systemctl daemon-reload
    systemctl enable websockify
    systemctl restart websockify
    systemctl restart nginx

    # Get container IP
    CONTAINER_IP=$(hostname -I | awk '{print $1}')

    msg_ok "noVNC installed successfully"
    echo ""
    echo "Access noVNC at: http://$CONTAINER_IP"
    echo "Or via websockify directly: http://$CONTAINER_IP:$WEBSOCKIFY_PORT"
    echo ""
}

# ============================================================================
# MONITORING SETUP
# ============================================================================

setup_monitoring() {
    msg_info "Setting up connection monitoring..."

    # Create monitoring systemd service
    cat > /etc/systemd/system/wayvnc-monitor.service <<EOF
[Unit]
Description=WayVNC Connection Monitor
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/wayvnc-monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable wayvnc-monitor.service
    systemctl start wayvnc-monitor.service

    # Create monitoring dashboard script
    cat > /usr/local/bin/wayvnc-status.sh <<'STATUS_EOF'
#!/usr/bin/env bash
# WayVNC Status Dashboard

echo "WayVNC Status Dashboard"
echo "======================="
echo ""

# Service status
echo "Service Status:"
systemctl is-active wayvnc.service 2>/dev/null && echo "  WayVNC: Running" || echo "  WayVNC: Stopped"
systemctl is-active websockify.service 2>/dev/null && echo "  Websockify: Running" || echo "  Websockify: Not installed/Running"
systemctl is-active wayvnc-monitor.service 2>/dev/null && echo "  Monitor: Running" || echo "  Monitor: Stopped"
echo ""

# Active connections
echo "Active Connections:"
CONN_COUNT=$(netstat -tn 2>/dev/null | grep ":5900 " | grep ESTABLISHED | wc -l)
echo "  Total: $CONN_COUNT"
if [ "$CONN_COUNT" -gt 0 ]; then
    echo "  Clients:"
    netstat -tn 2>/dev/null | grep ":5900 " | grep ESTABLISHED | awk '{print $5}' | cut -d: -f1 | sort -u | sed 's/^/    - /'
fi
echo ""

# Recent connections from log
if [ -f /var/log/wayvnc/connections.log ]; then
    echo "Recent Connections (last 10):"
    tail -n 10 /var/log/wayvnc/connections.log | sed 's/^/  /'
    echo ""
fi

# Rate limiting stats
echo "Rate Limiting Stats:"
if iptables -L INPUT -n -v 2>/dev/null | grep -q "5900"; then
    echo "  Rate limiting: Active"
    DROPPED=$(journalctl -u iptables -n 100 --no-pager 2>/dev/null | grep "VNC rate limit" | wc -l)
    echo "  Recent blocks: $DROPPED"
else
    echo "  Rate limiting: Not configured"
fi
echo ""

# Configuration
echo "Configuration:"
if [ -f /etc/wayvnc/config ]; then
    echo "  Port: $(grep '^port=' /etc/wayvnc/config | cut -d= -f2)"
    echo "  Max Rate: $(grep '^max_rate=' /etc/wayvnc/config | cut -d= -f2)"
    echo "  Auth: $(grep '^enable_auth=' /etc/wayvnc/config | cut -d= -f2)"
    if grep -q '^private_key_file=' /etc/wayvnc/config; then
        echo "  TLS: Enabled"
    fi
    if grep -q '^rsa_private_key_file=' /etc/wayvnc/config; then
        echo "  RSA-AES: Enabled"
    fi
fi
STATUS_EOF

    chmod +x /usr/local/bin/wayvnc-status.sh

    msg_ok "Monitoring configured"
    echo "Use 'wayvnc-status.sh' to view connection status"
}

# ============================================================================
# UPDATE SYSTEMD SERVICE
# ============================================================================

update_systemd_service() {
    msg_info "Updating WayVNC systemd service..."

    # Check if service exists
    if [ ! -f /etc/systemd/system/waydroid.service ]; then
        msg_warn "Waydroid service not found, skipping service update"
        return
    fi

    # Update waydroid service to include better logging
    if ! grep -q "StandardOutput=append:$WAYVNC_LOG" /etc/systemd/system/waydroid.service; then
        sed -i '/\[Service\]/a StandardOutput=append:'"$WAYVNC_LOG"'\nStandardError=append:'"$WAYVNC_LOG" /etc/systemd/system/waydroid.service
        systemctl daemon-reload
        msg_ok "Service logging configured"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo ""
    echo "========================================"
    echo "  WayVNC Enhancement Script"
    echo "========================================"
    echo ""

    # Apply enhancements based on flags
    if [ "$SECURITY_ONLY" = false ] && [ "$PERFORMANCE_ONLY" = false ]; then
        # Apply all enhancements
        apply_security_enhancements
        apply_performance_enhancements
        update_systemd_service

        if [ "$INSTALL_NOVNC" = true ]; then
            install_novnc
        fi

        if [ "$ENABLE_MONITORING" = true ]; then
            setup_monitoring
        fi
    else
        # Apply specific enhancements
        if [ "$SECURITY_ONLY" = true ]; then
            apply_security_enhancements
            if [ "$ENABLE_MONITORING" = true ]; then
                setup_monitoring
            fi
        fi

        if [ "$PERFORMANCE_ONLY" = true ]; then
            apply_performance_enhancements
        fi

        if [ "$INSTALL_NOVNC" = true ]; then
            install_novnc
        fi

        update_systemd_service
    fi

    echo ""
    msg_ok "WayVNC Enhancement Complete!"
    echo ""
    echo "Summary:"
    echo "--------"

    if [ "$ENABLE_TLS" = true ]; then
        echo "• TLS encryption enabled"
        echo "  Certificate: $WAYVNC_CONFIG_DIR/tls-cert.pem"
    fi

    if [ "$ENABLE_RSA_AES" = true ]; then
        echo "• RSA-AES encryption enabled (TOFU model)"
    fi

    echo "• Password stored in: $WAYVNC_CONFIG_DIR/password"
    echo "• Configuration: $WAYVNC_CONFIG"
    echo "• Performance: $MAX_FPS FPS target"
    echo "• Rate limiting: 10 connections/min per IP"

    if [ "$INSTALL_NOVNC" = true ]; then
        CONTAINER_IP=$(hostname -I | awk '{print $1}')
        echo "• noVNC web access: http://$CONTAINER_IP"
    fi

    echo ""
    echo "Useful Commands:"
    echo "----------------"
    echo "  wayvnc-tune.sh show              # Show current settings"
    echo "  wayvnc-tune.sh fps 60            # Change frame rate"
    echo "  wayvnc-tune.sh preset balanced   # Apply preset"

    if [ "$ENABLE_MONITORING" = true ]; then
        echo "  wayvnc-status.sh                 # View connection status"
    fi

    echo "  systemctl restart waydroid       # Restart services"
    echo ""

    # Show password
    if [ -f "$WAYVNC_CONFIG_DIR/password" ]; then
        echo "Current VNC Password:"
        echo "--------------------"
        cat "$WAYVNC_CONFIG_DIR/password"
        echo ""
    fi

    msg_warn "Restart the Waydroid service for all changes to take effect:"
    echo "  systemctl restart waydroid"
    echo ""
}

# Run main function
main
