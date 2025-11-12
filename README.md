# Waydroid Proxmox LXC

Run Android applications on Proxmox using Waydroid in an LXC container with full GPU passthrough and remote access.

## Features

- **Multi-GPU Support**: Intel, AMD GPU passthrough or software rendering
- **Interactive Setup**: Easy installer with GPU and GAPPS selection
- **VNC Access**: Remote desktop access via WayVNC on port 5900
- **Home Assistant Integration**: REST API for automation (port 8080)
- **Lightweight**: Minimal resource usage with LXC containers
- **Google Play Store**: Optional GAPPS integration
- **Flexible Security**: Privileged (GPU) or unprivileged (software) containers

## Use Cases

- **Smart Home Automation**: Control Android-only IoT devices from Home Assistant
- **Gate/Door Control**: Automate apps that only have Android interfaces
- **Security Cameras**: Run Android camera apps with Home Assistant integration
- **Remote Android Testing**: Test Android apps on your Proxmox server
- **Legacy App Support**: Run old Android apps that need specific environments

## Quick Start

```bash
# Clone the repository
git clone https://github.com/iceteaSA/waydroid-proxmox.git
cd waydroid-proxmox

# Make scripts executable
chmod +x install/install.sh scripts/*.sh

# Optional: Configure host for Intel GPU (one-time, Intel users only)
./scripts/configure-intel-n150.sh
# Reboot if i915 was just configured

# Run interactive installer
./install/install.sh
```

The installer will ask you:
1. **Container type**: Privileged (GPU passthrough) or Unprivileged (software rendering)
2. **GPU type**: Intel, AMD, NVIDIA (software), or Software rendering
3. **GAPPS**: Install Google Play Store (yes/no)

After installation:
- **VNC Access**: `<container-ip>:5900`
- **API Endpoint**: `http://<container-ip>:8080`

## Requirements

### Hardware
- **CPU**: Any x86_64 CPU (Intel N150 optimized)
- **GPU**: Intel (recommended), AMD, or software rendering
- **RAM**: 4GB+ (8GB recommended)
- **Storage**: 20GB+ free space

### Software
- Proxmox VE 7.x or 8.x
- Kernel 5.15+ with binder support
- For GPU passthrough: Privileged LXC container

## Architecture

```
┌─────────────────────────────────────────┐
│         Proxmox Host (Intel N150)        │
│  ┌────────────────────────────────────┐ │
│  │     Waydroid LXC Container         │ │
│  │                                    │ │
│  │  ┌──────────┐      ┌───────────┐  │ │
│  │  │  Sway    │◄────►│  WayVNC   │  │ │
│  │  │Compositor│      │  :5900    │  │ │
│  │  └────┬─────┘      └───────────┘  │ │
│  │       │                            │ │
│  │  ┌────▼─────┐      ┌───────────┐  │ │
│  │  │ Waydroid │      │    API    │  │ │
│  │  │ Android  │      │   :8080   │  │ │
│  │  │  System  │      └───────────┘  │ │
│  │  └────┬─────┘                     │ │
│  │       │                            │ │
│  │  ┌────▼─────────────────────────┐ │ │
│  │  │  Intel GPU Passthrough       │ │ │
│  │  │  /dev/dri/card0              │ │ │
│  │  │  /dev/dri/renderD128         │ │ │
│  │  └──────────────────────────────┘ │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

## Project Structure

```
waydroid-proxmox/
├── ct/                      # Container setup scripts
│   └── waydroid-lxc.sh     # Main Waydroid installation
├── install/                 # Installation scripts
│   └── install.sh          # LXC creation and setup
├── scripts/                 # Helper scripts
│   ├── helper-functions.sh # Shared functions
│   ├── configure-intel-n150.sh  # Intel N150 configuration
│   └── test-setup.sh       # Setup verification
├── config/                  # Configuration files
│   └── intel-n150.conf     # Intel N150 specific settings
├── docs/                    # Documentation
│   ├── INSTALLATION.md     # Detailed installation guide
│   ├── HOME_ASSISTANT.md   # Home Assistant integration
│   └── CONFIGURATION.md    # Configuration options
└── README.md               # This file
```

## Documentation

- **[Installation Guide](docs/INSTALLATION.md)**: Detailed step-by-step installation
- **[Home Assistant Integration](docs/HOME_ASSISTANT.md)**: Automate Android apps
- **[Configuration](docs/CONFIGURATION.md)**: Customize your setup
- **[Troubleshooting](docs/INSTALLATION.md#troubleshooting)**: Common issues and solutions

## Home Assistant Example

Control an Android gate app from Home Assistant:

```yaml
# configuration.yaml
rest_command:
  open_gate:
    url: "http://192.168.1.100:8080/app/launch"
    method: POST
    headers:
      Content-Type: "application/json"
    payload: '{"package": "com.example.gatecontrol"}'

automation:
  - alias: "Open Gate"
    trigger:
      - platform: state
        entity_id: input_button.gate
    action:
      - service: rest_command.open_gate
```

## API Endpoints

- `GET /status` - Get Waydroid status
- `GET /apps` - List installed apps
- `POST /app/launch` - Launch an app
- `POST /app/intent` - Send Android intent

See [Home Assistant Integration](docs/HOME_ASSISTANT.md) for details.

## GPU Support

### Intel GPUs (Recommended)
- Full hardware acceleration via Mesa/Iris
- VA-API video decoding
- Best performance and compatibility
- Example: Intel N150, i3/i5/i7 with integrated graphics

### AMD GPUs
- Hardware acceleration via Mesa/RadeonSI
- VA-API video decoding
- Good performance
- Example: AMD Ryzen with Radeon Graphics

### NVIDIA GPUs
- Software rendering only (GPU passthrough not supported)
- Limited performance
- Use for testing or non-GPU-intensive apps

### Software Rendering
- No GPU required
- Works in unprivileged containers
- Limited graphics performance
- Good for headless automation

## Performance

Example with Intel N150 (Alder Lake-N):
- **CPU**: 4 E-cores @ 3.6GHz
- **GPU**: Intel UHD Graphics (24 EUs, Gen 11.5)
- **RAM Usage**: ~1.5GB (Android + compositor)
- **Boot Time**: ~30 seconds
- **GPU Acceleration**: Full hardware acceleration via Mesa/Iris

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## Known Limitations

- **Wayland Only**: Requires Wayland compositor (no X11)
- **Intel GPU**: Currently optimized for Intel GPUs (AMD/NVIDIA may work but untested)
- **Network**: Some Android apps may have network connectivity issues
- **SafetyNet**: Banking apps with SafetyNet may not work

## Troubleshooting

### Container Won't Start
```bash
# Check kernel modules on host
lsmod | grep binder

# Reload if needed
modprobe binder_linux ashmem_linux
```

### No GPU Access
```bash
# Verify GPU devices on host
ls -la /dev/dri/

# Check container config
cat /etc/pve/lxc/<ctid>.conf | grep dri
```

### VNC Not Accessible
```bash
# Check service in container
pct enter <ctid>
systemctl status waydroid-vnc
```

See [full troubleshooting guide](docs/INSTALLATION.md#troubleshooting).

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Credits

- [Waydroid](https://waydro.id/) - Android container solution
- [Proxmox Community Scripts](https://github.com/community-scripts/ProxmoxVE) - Inspiration and structure
- [WayVNC](https://github.com/any1/wayvnc) - VNC server for Wayland

## Support

- **Issues**: [GitHub Issues](https://github.com/iceteaSA/waydroid-proxmox/issues)
- **Discussions**: [GitHub Discussions](https://github.com/iceteaSA/waydroid-proxmox/discussions)
- **Waydroid Docs**: [docs.waydro.id](https://docs.waydro.id)

## Changelog

### v1.0.0 (2025-01-12)
- Initial release
- Intel N150 support
- GPU passthrough
- VNC access via WayVNC
- Home Assistant API integration
- Automated installation scripts
