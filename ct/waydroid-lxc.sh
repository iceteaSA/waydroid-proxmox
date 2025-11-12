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
if [ -n "${FUNCTIONS_FILE_PATH}" ]; then
    source <(echo "$FUNCTIONS_FILE_PATH")
    color
    verb_ip6
    catch_errors
    setting_up_container
    network_check
    update_os
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

    # Silent execution helper
    if [ "${VERBOSE}" = "yes" ]; then
        STD=""
    else
        STD="&>/dev/null"
    fi

    # Basic setup
    $STD apt-get update
    $STD apt-get upgrade -y
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
$STD apt-get install -y \
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
$STD apt-get install -y \
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
            $STD apt-get install -y \
              intel-media-va-driver \
              i965-va-driver \
              mesa-va-drivers \
              mesa-vulkan-drivers \
              libgl1-mesa-dri
            msg_ok "Intel GPU drivers installed"
            ;;
        amd)
            $STD apt-get install -y \
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
    $STD apt-get install -y \
      libgl1-mesa-dri \
      mesa-utils
    msg_ok "Software rendering support installed"
fi

msg_info "Adding Waydroid Repository"
curl -fsSL https://repo.waydro.id/waydroid.gpg | gpg --dearmor -o /usr/share/keyrings/waydroid-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/waydroid-archive-keyring.gpg] https://repo.waydro.id/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/waydroid.list
$STD apt-get update
msg_ok "Waydroid Repository Added"

msg_info "Installing Waydroid"
$STD apt-get install -y waydroid
msg_ok "Waydroid Installed"

msg_info "Installing WayVNC and Dependencies"
$STD apt-get install -y \
  wayvnc \
  tigervnc-viewer \
  tigervnc-common
msg_ok "WayVNC Installed"

msg_info "Installing Additional Tools"
$STD apt-get install -y \
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
cat > /root/.config/wayvnc/config <<EOF
address=0.0.0.0
port=5900
enable_auth=false
EOF
msg_ok "WayVNC Configuration Created"

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

[Service]
Type=forking
ExecStart=/usr/local/bin/start-waydroid.sh
Restart=on-failure
RestartSec=10
User=root
Environment="XDG_RUNTIME_DIR=/run/user/0"
Environment="WAYLAND_DISPLAY=wayland-0"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
msg_ok "Systemd Service Created"

msg_info "Creating Home Assistant Integration API"
cat > /usr/local/bin/waydroid-api.py <<'EOFAPI'
#!/usr/bin/env python3
"""
Simple HTTP API for Home Assistant integration with Waydroid
Allows remote control of Android apps via REST API
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import subprocess
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class WaydroidAPIHandler(BaseHTTPRequestHandler):
    def _set_headers(self, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()

    def do_GET(self):
        if self.path == '/status':
            self._set_headers()
            try:
                result = subprocess.run(['waydroid', 'status'],
                                      capture_output=True, text=True, timeout=5)
                response = {
                    'status': 'running' if result.returncode == 0 else 'stopped',
                    'output': result.stdout
                }
            except Exception as e:
                response = {'status': 'error', 'message': str(e)}
            self.wfile.write(json.dumps(response).encode())

        elif self.path == '/apps':
            self._set_headers()
            try:
                result = subprocess.run(['waydroid', 'app', 'list'],
                                      capture_output=True, text=True, timeout=5)
                response = {'apps': result.stdout.split('\n')}
            except Exception as e:
                response = {'error': str(e)}
            self.wfile.write(json.dumps(response).encode())
        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({'error': 'Not found'}).encode())

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)

        try:
            data = json.loads(body.decode())
        except json.JSONDecodeError:
            self._set_headers(400)
            self.wfile.write(json.dumps({'error': 'Invalid JSON'}).encode())
            return

        if self.path == '/app/launch':
            package = data.get('package')
            if not package:
                self._set_headers(400)
                self.wfile.write(json.dumps({'error': 'Package name required'}).encode())
                return

            try:
                subprocess.run(['waydroid', 'app', 'launch', package],
                             timeout=10, check=True)
                self._set_headers()
                self.wfile.write(json.dumps({'success': True, 'package': package}).encode())
            except subprocess.CalledProcessError as e:
                self._set_headers(500)
                self.wfile.write(json.dumps({'error': str(e)}).encode())

        elif self.path == '/app/intent':
            intent = data.get('intent')
            if not intent:
                self._set_headers(400)
                self.wfile.write(json.dumps({'error': 'Intent required'}).encode())
                return

            try:
                subprocess.run(['waydroid', 'app', 'intent', intent],
                             timeout=10, check=True)
                self._set_headers()
                self.wfile.write(json.dumps({'success': True}).encode())
            except subprocess.CalledProcessError as e:
                self._set_headers(500)
                self.wfile.write(json.dumps({'error': str(e)}).encode())
        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({'error': 'Not found'}).encode())

def run_server(port=8080):
    server_address = ('', port)
    httpd = HTTPServer(server_address, WaydroidAPIHandler)
    logger.info(f'Starting Waydroid API server on port {port}')
    httpd.serve_forever()

if __name__ == '__main__':
    run_server()
EOFAPI

chmod +x /usr/local/bin/waydroid-api.py
msg_ok "Home Assistant API Created"

msg_info "Creating API Service"
cat > /etc/systemd/system/waydroid-api.service <<EOF
[Unit]
Description=Waydroid Home Assistant API
After=waydroid-vnc.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/waydroid-api.py
Restart=always
User=root

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
    $STD apt-get autoremove -y
    $STD apt-get autoclean -y
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
