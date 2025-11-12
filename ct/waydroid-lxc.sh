#!/usr/bin/env bash

# Waydroid LXC Container Setup Script
# Copyright (c) 2025
# License: MIT
# https://github.com/iceteaSA/waydroid-proxmox

# Parse parameters
GPU_TYPE=${1:-intel}
USE_GAPPS=${2:-yes}
SOFTWARE_RENDERING=${3:-0}
GPU_DEVICE=${4:-}
RENDER_NODE=${5:-}

# Source community script functions if available
# FUNCTIONS_FILE_PATH should contain actual shell code, not a file path
if [ -n "${FUNCTIONS_FILE_PATH}" ]; then
    # Safely evaluate functions from community script environment
    eval "$FUNCTIONS_FILE_PATH" 2>/dev/null || true
    # Try to call community functions if they exist
    command -v color &>/dev/null && color
    command -v verb_ip6 &>/dev/null && verb_ip6
    command -v catch_errors &>/dev/null && catch_errors
    command -v setting_up_container &>/dev/null && setting_up_container
    command -v network_check &>/dev/null && network_check
    command -v update_os &>/dev/null && update_os
else
    # Fallback color definitions
    BL="\033[36m"
    RD="\033[01;31m"
    GN="\033[1;92m"
    YW="\033[1;93m"
    CL="\033[m"
    CM="${GN}✓${CL}"
    CROSS="${RD}✗${CL}"

    # Fallback functions
    msg_info() {
        echo -e "${BL}[INFO]${CL} $1"
    }

    msg_ok() {
        echo -e "${CM} $1"
    }

    msg_error() {
        echo -e "${CROSS} $1"
    }

    msg_warn() {
        echo -e "${YW}[WARN]${CL} $1"
    }

    # Silent execution helper function
    silent_exec() {
        if [ "${VERBOSE}" = "yes" ]; then
            "$@"
        else
            "$@" &>/dev/null
        fi
    }

    # Basic setup
    silent_exec apt-get update
    silent_exec apt-get upgrade -y
fi

# Define silent_exec if not already defined
if ! command -v silent_exec &>/dev/null; then
    silent_exec() {
        if [ "${VERBOSE}" = "yes" ]; then
            "$@"
        else
            "$@" &>/dev/null
        fi
    }
fi

echo -e "${GN}═══════════════════════════════════════════════${CL}"
echo -e "${GN}  Waydroid Container Setup${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}"
echo -e "${BL}GPU Type:${CL} ${GN}${GPU_TYPE}${CL}"
echo -e "${BL}Software Rendering:${CL} ${GN}$([ "$SOFTWARE_RENDERING" = "1" ] && echo "Yes" || echo "No")${CL}"
echo -e "${BL}GAPPS:${CL} ${GN}${USE_GAPPS}${CL}"
[ -n "$GPU_DEVICE" ] && echo -e "${BL}GPU Device:${CL} ${GN}${GPU_DEVICE}${CL}"
[ -n "$RENDER_NODE" ] && echo -e "${BL}Render Node:${CL} ${GN}${RENDER_NODE}${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

msg_info "Installing Dependencies"
silent_exec apt-get install -y \
  curl \
  sudo \
  gnupg \
  ca-certificates \
  lsb-release \
  software-properties-common \
  wget \
  unzip
msg_ok "Dependencies Installed"

msg_info "Installing Wayland and Compositor"
silent_exec apt-get install -y \
  wayland-protocols \
  weston \
  sway \
  xwayland
msg_ok "Wayland and Compositor Installed"

# Install GPU-specific packages
if [ "$SOFTWARE_RENDERING" = "0" ]; then
    msg_info "Installing GPU drivers for ${GPU_TYPE}..."

    case $GPU_TYPE in
        intel)
            silent_exec apt-get install -y \
              intel-media-va-driver \
              i965-va-driver \
              mesa-va-drivers \
              mesa-vulkan-drivers \
              libgl1-mesa-dri
            msg_ok "Intel GPU drivers installed"
            ;;
        amd)
            silent_exec apt-get install -y \
              mesa-va-drivers \
              mesa-vulkan-drivers \
              libgl1-mesa-dri \
              firmware-amd-graphics
            msg_ok "AMD GPU drivers installed"
            ;;
        *)
            msg_info "No specific GPU drivers needed for ${GPU_TYPE}"
            ;;
    esac
else
    msg_info "Installing software rendering support..."
    silent_exec apt-get install -y \
      libgl1-mesa-dri \
      mesa-utils
    msg_ok "Software rendering support installed"
fi

msg_info "Adding Waydroid Repository"
if ! curl -fsSL --connect-timeout 30 --max-time 60 https://repo.waydro.id/waydroid.gpg | gpg --dearmor -o /usr/share/keyrings/waydroid-archive-keyring.gpg; then
    msg_error "Failed to download Waydroid GPG key"
    exit 1
fi
echo "deb [signed-by=/usr/share/keyrings/waydroid-archive-keyring.gpg] https://repo.waydro.id/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/waydroid.list
silent_exec apt-get update
msg_ok "Waydroid Repository Added"

msg_info "Installing Waydroid"
silent_exec apt-get install -y waydroid
msg_ok "Waydroid Installed"

msg_info "Installing WayVNC and Dependencies"
silent_exec apt-get install -y \
  wayvnc \
  tigervnc-viewer \
  tigervnc-common
msg_ok "WayVNC Installed"

msg_info "Installing Additional Tools"
silent_exec apt-get install -y \
  python3 \
  python3-pip \
  python3-venv \
  git \
  net-tools
msg_ok "Additional Tools Installed"

# Configure GPU access (only if hardware rendering)
if [ "$SOFTWARE_RENDERING" = "0" ]; then
    msg_info "Configuring GPU Access"

    # Add render group and configure permissions
    groupadd -f render
    usermod -aG render root
    usermod -aG video root

    # Create device node configuration
    mkdir -p /var/lib/waydroid/lxc/waydroid/

    case $GPU_TYPE in
        intel|amd)
            cat > /etc/udev/rules.d/99-waydroid-gpu.rules <<EOF
# GPU devices for Waydroid
SUBSYSTEM=="drm", KERNEL=="card[0-9]*", TAG+="waydroid", MODE="0666"
SUBSYSTEM=="drm", KERNEL=="renderD*", TAG+="waydroid", MODE="0666"
EOF
            ;;
    esac

    msg_ok "GPU Access Configured"
else
    msg_info "Skipping GPU configuration (software rendering mode)"
fi

msg_info "Setting up Waydroid Service"
systemctl enable waydroid-container.service
msg_ok "Waydroid Service Configured"

msg_info "Creating WayVNC Configuration"
mkdir -p /root/.config/wayvnc

# Generate a random VNC password
VNC_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
echo "$VNC_PASSWORD" > /root/.config/wayvnc/password
chmod 600 /root/.config/wayvnc/password

cat > /root/.config/wayvnc/config <<EOF
address=0.0.0.0
port=5900
enable_auth=true
username=waydroid
password_file=/root/.config/wayvnc/password
# Performance settings
max_rate=60
# Security settings
require_encryption=false
EOF

# Also save password to a retrievable location for the user
echo "$VNC_PASSWORD" > /root/vnc-password.txt
chmod 600 /root/vnc-password.txt

msg_ok "WayVNC Configuration Created (Password: /root/vnc-password.txt)"

msg_info "Creating Startup Scripts"
cat > /usr/local/bin/start-waydroid.sh <<EOFSCRIPT
#!/bin/bash
# Start Waydroid with VNC access

# Set environment variables
export XDG_RUNTIME_DIR=/run/user/0
export WAYLAND_DISPLAY=wayland-0

# GPU-specific environment variables
GPU_TYPE="${GPU_TYPE}"
SOFTWARE_RENDERING="${SOFTWARE_RENDERING}"
GPU_DEVICE="${GPU_DEVICE}"
RENDER_NODE="${RENDER_NODE}"

if [ "\$SOFTWARE_RENDERING" = "0" ]; then
    case \$GPU_TYPE in
        intel)
            export MESA_LOADER_DRIVER_OVERRIDE=iris
            export LIBVA_DRIVER_NAME=iHD
            ;;
        amd)
            export MESA_LOADER_DRIVER_OVERRIDE=radeonsi
            export LIBVA_DRIVER_NAME=radeonsi
            ;;
    esac

    # Set specific GPU device if specified
    if [ -n "\$GPU_DEVICE" ]; then
        export DRI_PRIME=\$(basename "\$GPU_DEVICE" | sed 's/card//')
    fi
else
    export LIBGL_ALWAYS_SOFTWARE=1
fi

# Create runtime directory if it doesn't exist
mkdir -p \$XDG_RUNTIME_DIR

# Start Sway compositor in background
sway &
SWAY_PID=\$!
sleep 3

# Start WayVNC
wayvnc 0.0.0.0 5900 &
WAYVNC_PID=\$!

# Initialize Waydroid if not already done
if [ ! -d "/var/lib/waydroid/overlay" ]; then
    echo "Initializing Waydroid..."
    if [ "${USE_GAPPS}" = "yes" ]; then
        waydroid init -s GAPPS -f
    else
        waydroid init -f
    fi
fi

# Start Waydroid container
waydroid container start

# Start Waydroid session
waydroid session start &

echo "Waydroid started. VNC available on port 5900"
echo "Sway PID: \$SWAY_PID"
echo "WayVNC PID: \$WAYVNC_PID"
[ -n "\$GPU_DEVICE" ] && echo "Using GPU: \$GPU_DEVICE"
[ -n "\$RENDER_NODE" ] && echo "Using Render Node: \$RENDER_NODE"

# Keep script running
wait
EOFSCRIPT

chmod +x /usr/local/bin/start-waydroid.sh
msg_ok "Startup Scripts Created"

msg_info "Creating Systemd Service for Auto-start"
cat > /etc/systemd/system/waydroid-vnc.service <<EOF
[Unit]
Description=Waydroid with VNC Access
After=network.target waydroid-container.service
Wants=waydroid-container.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=forking
ExecStart=/usr/local/bin/start-waydroid.sh
ExecStartPost=/bin/sleep 10
ExecStartPost=/bin/sh -c 'if ! pgrep -f wayvnc; then exit 1; fi'
Restart=on-failure
RestartSec=15
TimeoutStartSec=120
TimeoutStopSec=30
User=root
Environment="XDG_RUNTIME_DIR=/run/user/0"
Environment="WAYLAND_DISPLAY=wayland-0"
# Watchdog
WatchdogSec=60
# Resource limits
MemoryHigh=3G
MemoryMax=4G
CPUQuota=200%

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
msg_ok "Systemd Service Created"

msg_info "Creating Home Assistant Integration API"
cat > /usr/local/bin/waydroid-api.py <<'EOFAPI'
#!/usr/bin/env python3
"""
Enhanced HTTP API for Home Assistant integration with Waydroid
Allows remote control of Android apps via REST API with authentication and logging
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import subprocess
import logging
import re
import os
import hashlib
import secrets
from datetime import datetime
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/waydroid-api.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Configuration
API_TOKEN_FILE = '/etc/waydroid-api/token'
MAX_PACKAGE_NAME_LENGTH = 200
ALLOWED_PACKAGE_PATTERN = re.compile(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$')

class WaydroidAPIHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        """Override to use our logger"""
        logger.info(f"{self.client_address[0]} - {format % args}")

    def _check_auth(self):
        """Check if request has valid authentication token"""
        # If no token file exists, skip auth (backward compatibility)
        if not os.path.exists(API_TOKEN_FILE):
            return True

        try:
            with open(API_TOKEN_FILE, 'r') as f:
                valid_token = f.read().strip()
        except Exception as e:
            logger.error(f"Failed to read token file: {e}")
            return False

        auth_header = self.headers.get('Authorization', '')
        if auth_header.startswith('Bearer '):
            token = auth_header[7:]
            return secrets.compare_digest(token, valid_token)

        return False

    def _set_headers(self, status=200, extra_headers=None):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('X-API-Version', '2.0')
        if extra_headers:
            for key, value in extra_headers.items():
                self.send_header(key, value)
        self.end_headers()

    def _validate_package_name(self, package):
        """Validate package name to prevent command injection"""
        if not package or len(package) > MAX_PACKAGE_NAME_LENGTH:
            return False
        return ALLOWED_PACKAGE_PATTERN.match(package) is not None

    def _send_json(self, data, status=200):
        """Send JSON response"""
        self._set_headers(status)
        self.wfile.write(json.dumps(data).encode())

    def do_GET(self):
        # Check authentication for all endpoints except /health
        if self.path != '/health' and not self._check_auth():
            self._send_json({'error': 'Unauthorized'}, 401)
            logger.warning(f"Unauthorized access attempt from {self.client_address[0]}")
            return

        if self.path == '/health':
            self._send_json({
                'status': 'healthy',
                'timestamp': datetime.utcnow().isoformat(),
                'version': '2.0'
            })

        elif self.path == '/status':
            try:
                result = subprocess.run(['waydroid', 'status'],
                                      capture_output=True, text=True, timeout=5)
                response = {
                    'status': 'running' if result.returncode == 0 else 'stopped',
                    'output': result.stdout.strip(),
                    'timestamp': datetime.utcnow().isoformat()
                }
                logger.info(f"Status check: {response['status']}")
            except subprocess.TimeoutExpired:
                response = {'status': 'error', 'message': 'Waydroid status check timed out'}
                logger.error("Waydroid status check timed out")
            except Exception as e:
                response = {'status': 'error', 'message': str(e)}
                logger.error(f"Waydroid status check failed: {e}")
            self._send_json(response)

        elif self.path == '/apps':
            try:
                result = subprocess.run(['waydroid', 'app', 'list'],
                                      capture_output=True, text=True, timeout=10)
                apps = [app.strip() for app in result.stdout.split('\n') if app.strip()]
                response = {
                    'apps': apps,
                    'count': len(apps),
                    'timestamp': datetime.utcnow().isoformat()
                }
                logger.info(f"App list retrieved: {len(apps)} apps")
            except Exception as e:
                response = {'error': str(e)}
                logger.error(f"Failed to list apps: {e}")
            self._send_json(response)

        elif self.path == '/version':
            try:
                result = subprocess.run(['waydroid', '--version'],
                                      capture_output=True, text=True, timeout=5)
                response = {
                    'waydroid_version': result.stdout.strip(),
                    'api_version': '2.0',
                    'timestamp': datetime.utcnow().isoformat()
                }
            except Exception as e:
                response = {'error': str(e)}
                logger.error(f"Failed to get version: {e}")
            self._send_json(response)

        else:
            self._send_json({'error': 'Not found'}, 404)

    def do_POST(self):
        # Check authentication
        if not self._check_auth():
            self._send_json({'error': 'Unauthorized'}, 401)
            logger.warning(f"Unauthorized POST attempt from {self.client_address[0]} to {self.path}")
            return

        content_length = int(self.headers.get('Content-Length', 0))
        if content_length > 10240:  # Max 10KB
            self._send_json({'error': 'Request too large'}, 413)
            return

        body = self.rfile.read(content_length)

        try:
            data = json.loads(body.decode())
        except json.JSONDecodeError as e:
            self._send_json({'error': f'Invalid JSON: {str(e)}'}, 400)
            logger.warning(f"Invalid JSON from {self.client_address[0]}: {e}")
            return

        if self.path == '/app/launch':
            package = data.get('package', '').strip()
            if not package:
                self._send_json({'error': 'Package name required'}, 400)
                return

            if not self._validate_package_name(package):
                self._send_json({'error': 'Invalid package name format'}, 400)
                logger.warning(f"Invalid package name rejected: {package}")
                return

            try:
                logger.info(f"Launching app: {package}")
                result = subprocess.run(['waydroid', 'app', 'launch', package],
                             capture_output=True, text=True, timeout=15, check=False)
                if result.returncode == 0:
                    self._send_json({
                        'success': True,
                        'package': package,
                        'timestamp': datetime.utcnow().isoformat()
                    })
                    logger.info(f"Successfully launched app: {package}")
                else:
                    self._send_json({
                        'success': False,
                        'error': result.stderr.strip() or result.stdout.strip()
                    }, 500)
                    logger.error(f"Failed to launch app {package}: {result.stderr}")
            except subprocess.TimeoutExpired:
                self._send_json({'error': 'App launch timed out'}, 500)
                logger.error(f"App launch timed out: {package}")
            except Exception as e:
                self._send_json({'error': str(e)}, 500)
                logger.error(f"Exception launching app {package}: {e}")

        elif self.path == '/app/stop':
            package = data.get('package', '').strip()
            if not package:
                self._send_json({'error': 'Package name required'}, 400)
                return

            if not self._validate_package_name(package):
                self._send_json({'error': 'Invalid package name format'}, 400)
                return

            try:
                logger.info(f"Stopping app: {package}")
                # Use adb to stop the app
                result = subprocess.run(['waydroid', 'shell', 'am', 'force-stop', package],
                             capture_output=True, text=True, timeout=10, check=False)
                self._send_json({
                    'success': True,
                    'package': package,
                    'timestamp': datetime.utcnow().isoformat()
                })
                logger.info(f"Successfully stopped app: {package}")
            except Exception as e:
                self._send_json({'error': str(e)}, 500)
                logger.error(f"Failed to stop app {package}: {e}")

        elif self.path == '/app/intent':
            intent = data.get('intent', '').strip()
            if not intent:
                self._send_json({'error': 'Intent required'}, 400)
                return

            # Basic intent validation
            if len(intent) > 500 or ';' in intent or '|' in intent:
                self._send_json({'error': 'Invalid intent format'}, 400)
                logger.warning(f"Invalid intent rejected: {intent[:50]}...")
                return

            try:
                logger.info(f"Sending intent: {intent[:100]}...")
                result = subprocess.run(['waydroid', 'app', 'intent', intent],
                             capture_output=True, text=True, timeout=15, check=False)
                self._send_json({
                    'success': result.returncode == 0,
                    'output': result.stdout.strip(),
                    'timestamp': datetime.utcnow().isoformat()
                })
                logger.info(f"Intent sent successfully")
            except Exception as e:
                self._send_json({'error': str(e)}, 500)
                logger.error(f"Failed to send intent: {e}")

        elif self.path == '/container/restart':
            try:
                logger.warning("Container restart requested")
                subprocess.run(['waydroid', 'container', 'restart'],
                             timeout=30, check=False)
                self._send_json({
                    'success': True,
                    'message': 'Container restart initiated',
                    'timestamp': datetime.utcnow().isoformat()
                })
            except Exception as e:
                self._send_json({'error': str(e)}, 500)
                logger.error(f"Failed to restart container: {e}")

        else:
            self._send_json({'error': 'Not found'}, 404)

def generate_token():
    """Generate a secure random token"""
    return secrets.token_urlsafe(32)

def run_server(port=8080):
    # Create token directory if it doesn't exist
    token_dir = os.path.dirname(API_TOKEN_FILE)
    if token_dir:
        os.makedirs(token_dir, exist_ok=True)

    # Generate token if it doesn't exist
    if not os.path.exists(API_TOKEN_FILE):
        token = generate_token()
        try:
            with open(API_TOKEN_FILE, 'w') as f:
                f.write(token)
            os.chmod(API_TOKEN_FILE, 0o600)
            logger.info(f"Generated new API token and saved to {API_TOKEN_FILE}")
            logger.info(f"API Token: {token}")
            logger.info("Please save this token securely. It will not be displayed again.")
        except Exception as e:
            logger.error(f"Failed to save token: {e}")
            logger.warning("Running without authentication!")
    else:
        logger.info(f"Using existing API token from {API_TOKEN_FILE}")

    server_address = ('', port)
    httpd = HTTPServer(server_address, WaydroidAPIHandler)
    logger.info(f'Starting Waydroid API server v2.0 on port {port}')
    logger.info(f'Endpoints: /health, /status, /version, /apps, /app/launch, /app/stop, /app/intent, /container/restart')

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        logger.info("API server shutting down")
        httpd.shutdown()

if __name__ == '__main__':
    run_server()
EOFAPI

chmod +x /usr/local/bin/waydroid-api.py
msg_ok "Home Assistant API Created"

msg_info "Creating API Service"
cat > /etc/systemd/system/waydroid-api.service <<EOF
[Unit]
Description=Waydroid Home Assistant API
After=waydroid-vnc.service network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/waydroid-api.py
ExecStartPost=/bin/sleep 3
ExecStartPost=/usr/bin/curl -sf http://localhost:8080/health || exit 1
Restart=always
RestartSec=10
TimeoutStartSec=30
User=root
# Health check
ExecReload=/bin/kill -HUP \$MAINPID
# Watchdog
WatchdogSec=30
# Resource limits
MemoryHigh=256M
MemoryMax=512M

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
msg_ok "API Service Created"

# Cleanup using community script pattern if available
if command -v cleanup_lxc &>/dev/null; then
    msg_info "Cleaning up"
    cleanup_lxc
    msg_ok "Cleanup Complete"
else
    msg_info "Cleaning up"
    silent_exec apt-get autoremove -y
    silent_exec apt-get autoclean -y
    msg_ok "Cleanup Complete"
fi

# Customize MOTD if function is available
if command -v motd_ssh &>/dev/null; then
    motd_ssh
    customize
fi

echo -e "\n${GN}═══════════════════════════════════════════════${CL}"
echo -e "${GN}  Waydroid LXC Setup Complete!${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"
echo -e "${BL}Configuration:${CL}"
echo -e "  GPU Type: ${GN}${GPU_TYPE}${CL}"
echo -e "  Rendering: ${GN}$([ "$SOFTWARE_RENDERING" = "1" ] && echo "Software" || echo "Hardware Accelerated")${CL}"
[ -n "$GPU_DEVICE" ] && echo -e "  GPU Device: ${GN}${GPU_DEVICE}${CL}"
[ -n "$RENDER_NODE" ] && echo -e "  Render Node: ${GN}${RENDER_NODE}${CL}"
echo -e "  GAPPS: ${GN}${USE_GAPPS}${CL}\n"
echo -e "${BL}Next steps:${CL}"
echo -e "1. Start Waydroid: ${GN}systemctl start waydroid-vnc${CL}"
echo -e "2. Enable auto-start: ${GN}systemctl enable waydroid-vnc${CL}"
echo -e "3. Start API: ${GN}systemctl start waydroid-api${CL}"
echo -e "4. Enable API: ${GN}systemctl enable waydroid-api${CL}"
echo -e "5. Access VNC: ${GN}<LXC-IP>:5900${CL}"
echo -e "6. API endpoint: ${GN}http://<LXC-IP>:8080${CL}\n"

if [ "$SOFTWARE_RENDERING" = "1" ]; then
    msg_warn "Software rendering is slower than hardware acceleration"
    echo -e "  Graphics performance may be limited\n"
fi
