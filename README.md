# Waydroid Proxmox LXC

Run Android applications on Proxmox using Waydroid in an LXC container with full GPU passthrough and remote access.

> **Latest Update (v2.0.0)**: Major feature release with API v3.0, clipboard sharing, automated app installation, comprehensive security enhancements, and performance optimization tools. See [Changelog](#changelog) for details.

## Features

### Core Functionality
- **Multi-GPU Support**: Intel, AMD GPU passthrough or software rendering
- **Interactive Setup**: Easy installer with GPU and GAPPS selection
- **Lightweight**: Minimal resource usage with LXC containers
- **Google Play Store**: Optional GAPPS integration
- **Flexible Security**: Privileged (GPU) or unprivileged (software) containers

### Performance & Optimization
- **LXC Performance Tuning**: Automated container optimization for Android workloads
  - CPU scheduling and allocation optimization
  - Memory management and cgroup tuning
  - I/O priority configuration
  - Resource limits and quotas
- **Audio Passthrough**: Automatic PulseAudio/PipeWire audio support with device passthrough
- **Clipboard Sharing**: Seamless clipboard integration between host and Android

### Remote Access & Security
- **VNC Access**: Remote desktop access via WayVNC on port 5900
  - **Enhanced Security**: TLS/RSA-AES encryption, password authentication, rate limiting
  - **Performance Tuning**: Configurable frame rates (15-60 FPS) and quality presets
  - **noVNC Support**: Browser-based access without VNC client installation
  - **Audit Logging**: Comprehensive connection and security event logging
  - **Advanced Features**: Multi-user support, JPEG compression, H.264 encoding

### Home Assistant & Automation
- **REST API v3.0**: Production-ready API with advanced automation features
  - **Webhooks**: Real-time event notifications (app launches, status changes, etc.)
  - **Prometheus Metrics**: Built-in monitoring and metrics export
  - **Rate Limiting**: DoS protection with configurable limits
  - **Screenshot Capture**: Automated visual monitoring and security
  - **Property Management**: Dynamic Android configuration
  - **Enhanced Error Handling**: Machine-readable error codes and detailed responses
- **Automated App Installation**: Batch install Android apps from APK files or Play Store
  - Pre-configured app lists for common use cases
  - Silent installation without user interaction
  - Dependency management and validation

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
│   ├── helper-functions.sh      # Shared functions
│   ├── configure-intel-n150.sh  # Intel N150 configuration
│   ├── tune-lxc.sh             # LXC container optimization
│   ├── enhance-vnc.sh          # WayVNC security & performance enhancements
│   ├── setup-audio.sh          # Audio passthrough configuration
│   ├── setup-clipboard.sh      # Clipboard sharing setup
│   ├── install-apps.sh         # Android app installation
│   ├── optimize-performance.sh  # In-container optimizations
│   ├── monitor-performance.sh   # Performance monitoring
│   ├── health-check.sh         # Container health checks
│   └── test-setup.sh           # Setup verification
├── config/                  # Configuration files
│   └── intel-n150.conf     # Intel N150 specific settings
├── docs/                    # Documentation
│   ├── INSTALLATION.md     # Detailed installation guide
│   ├── HOME_ASSISTANT.md   # Home Assistant integration
│   ├── CONFIGURATION.md    # Configuration options
│   ├── LXC_TUNING.md       # LXC optimization guide
│   ├── VNC-ENHANCEMENTS.md # VNC security & performance guide
│   ├── VNC-QUICK-REFERENCE.md # VNC quick reference
│   ├── CLIPBOARD-SHARING.md # Clipboard integration guide
│   └── APP_INSTALLATION.md  # App installation guide
├── API_IMPROVEMENTS_v3.0.md # API v3.0 feature documentation
└── README.md               # This file
```

## Tools & Scripts

The project includes a comprehensive set of tools for optimizing and enhancing your Waydroid installation:

### Container Optimization
- **tune-lxc.sh**: LXC container performance optimization
  ```bash
  # Analyze current configuration
  ./scripts/tune-lxc.sh --analyze-only <ctid>

  # Apply all optimizations
  ./scripts/tune-lxc.sh <ctid>
  ```
  - Optimizes CPU scheduling, memory management, I/O priorities
  - Configures Android-specific cgroup settings
  - Sets up resource limits and quotas
  - See [LXC Tuning Guide](docs/LXC_TUNING.md) for details

### Remote Access Enhancement
- **enhance-vnc.sh**: VNC security and performance improvements
  ```bash
  # Interactive setup with full options
  ./scripts/enhance-vnc.sh <ctid>

  # Quick security setup
  ./scripts/enhance-vnc.sh --security-only <ctid>
  ```
  - TLS/RSA-AES encryption configuration
  - Password authentication and rate limiting
  - noVNC web interface installation
  - Performance tuning (FPS, quality, compression)
  - See [VNC Enhancements Guide](docs/VNC-ENHANCEMENTS.md) for details

### Audio & Clipboard
- **setup-audio.sh**: Audio passthrough configuration
  ```bash
  # Auto-detect and configure audio
  ./scripts/setup-audio.sh <ctid>

  # Test existing configuration
  ./scripts/setup-audio.sh --test-only <ctid>
  ```
  - Detects host audio system (PulseAudio/PipeWire)
  - Configures LXC device passthrough
  - Sets up audio client in container
  - Provides troubleshooting diagnostics

- **setup-clipboard.sh**: Clipboard sharing setup
  ```bash
  # Setup clipboard sharing
  ./scripts/setup-clipboard.sh <ctid>

  # Verify configuration
  ./scripts/setup-clipboard.sh --verify <ctid>
  ```
  - Bidirectional clipboard sync between host and Android
  - wl-clipboard integration
  - Automatic clipboard monitoring
  - See [Clipboard Sharing Guide](docs/CLIPBOARD-SHARING.md) for details

### App Management
- **install-apps.sh**: Automated Android app installation
  ```bash
  # Interactive installation
  ./scripts/install-apps.sh <ctid>

  # Batch install from list
  ./scripts/install-apps.sh --from-list apps.txt <ctid>

  # Install single APK
  ./scripts/install-apps.sh --apk /path/to/app.apk <ctid>
  ```
  - Silent app installation without user interaction
  - Pre-configured app lists for common use cases
  - APK file installation support
  - Play Store package installation (with GAPPS)
  - See [App Installation Guide](docs/APP_INSTALLATION.md) for details

### Monitoring & Diagnostics
- **monitor-performance.sh**: Real-time performance monitoring
- **health-check.sh**: Container health checks and diagnostics
- **test-setup.sh**: Comprehensive setup verification

## Documentation

### Getting Started
- **[Installation Guide](docs/INSTALLATION.md)**: Detailed step-by-step installation instructions
- **[Configuration](docs/CONFIGURATION.md)**: Customize your Waydroid setup
- **[Troubleshooting](docs/INSTALLATION.md#troubleshooting)**: Common issues and solutions

### Optimization & Enhancement
- **[LXC Tuning Guide](docs/LXC_TUNING.md)**: Optimize container performance for Android workloads
- **[VNC Enhancements](docs/VNC-ENHANCEMENTS.md)**: Security, performance, and feature improvements
- **[VNC Quick Reference](docs/VNC-QUICK-REFERENCE.md)**: Common VNC commands and settings
- **[Clipboard Sharing](docs/CLIPBOARD-SHARING.md)**: Setup and use clipboard integration
- **[App Installation](docs/APP_INSTALLATION.md)**: Automated app installation and management

### Integration & Automation
- **[Home Assistant Integration](docs/HOME_ASSISTANT.md)**: Automate Android apps with Home Assistant
- **[API v3.0 Documentation](API_IMPROVEMENTS_v3.0.md)**: Advanced API features, webhooks, and monitoring

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

## API Endpoints (v3.0)

### Core Endpoints
- `GET /status` - Get Waydroid status
- `GET /apps` - List installed apps
- `POST /app/launch` - Launch an app
- `POST /app/intent` - Send Android intent

### Advanced Features (v3.0)
- `GET /logs` - Retrieve Waydroid logs
- `GET /properties` - Get all Waydroid properties
- `POST /properties/set` - Set Waydroid properties dynamically
- `POST /screenshot` - Capture Android screen (base64 PNG)
- `GET /metrics` - Prometheus metrics export
- `GET /adb/devices` - List ADB devices

### Webhooks & Events
- `POST /webhooks` - Register webhook for real-time events
- `GET /webhooks` - List registered webhooks
- `DELETE /webhooks/{id}` - Remove webhook

### API Features
- **Rate Limiting**: DoS protection (100 req/min unauthenticated, 500 req/min authenticated)
- **Versioning**: Support for v1.0, v2.0, v3.0 with backward compatibility
- **Error Handling**: Machine-readable error codes with detailed context
- **Authentication**: Bearer token authentication with secure storage
- **Monitoring**: Built-in Prometheus metrics and request tracking

See [API v3.0 Documentation](API_IMPROVEMENTS_v3.0.md) and [Home Assistant Integration](docs/HOME_ASSISTANT.md) for complete details and examples.

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

### Performance Optimization

After installation, optimize your container for best performance:

```bash
# On Proxmox host - analyze current configuration
./scripts/tune-lxc.sh --analyze-only <ctid>

# Preview optimizations
./scripts/tune-lxc.sh --dry-run <ctid>

# Apply all optimizations
./scripts/tune-lxc.sh <ctid>
```

The tuning script optimizes:
- **cgroup settings** for Android workloads
- **CPU allocation** and scheduling
- **Memory management** and limits
- **I/O scheduling** priorities
- **Security** capabilities and device access
- **Monitoring** and health checks

See **[LXC Tuning Guide](docs/LXC_TUNING.md)** for details.

### Audio Passthrough

Enable audio in Android apps with automatic PulseAudio/PipeWire passthrough:

```bash
# Auto-detect and configure audio
./scripts/setup-audio.sh <ctid>

# Preview changes before applying
./scripts/setup-audio.sh --dry-run <ctid>

# Test existing audio configuration
./scripts/setup-audio.sh --test-only <ctid>

# Force specific audio system
./scripts/setup-audio.sh --force-pipewire <ctid>
```

The audio script:
- **Detects** host audio system (PulseAudio or PipeWire)
- **Configures** LXC for audio device passthrough
- **Sets up** audio client in container
- **Tests** audio functionality
- **Provides** comprehensive troubleshooting guide

## Security

This project has undergone comprehensive security auditing and includes multiple security enhancements:

### Security Features
- **VNC Encryption**: TLS/RSA-AES encryption for remote access
- **API Authentication**: Bearer token authentication with secure storage (mode 0600)
- **Rate Limiting**: DoS protection on API and VNC endpoints
- **Audit Logging**: Comprehensive logging of security events and authentication attempts
- **Input Validation**: Strict validation of all user inputs to prevent injection attacks
- **Secure Defaults**: All security features enabled by default in new installations

### Security Best Practices
1. **Change Default Credentials**: Always set strong VNC passwords and API tokens
2. **Use TLS**: Enable TLS encryption for VNC connections when accessed over network
3. **Firewall Configuration**: Limit access to VNC (5900) and API (8080) ports
4. **Regular Updates**: Keep Proxmox, LXC, and Waydroid updated
5. **Monitor Logs**: Review audit logs in `/var/log/waydroid-vnc.log` and `/var/log/waydroid-api.log`

### Security Audits
- **2025-01-12**: Comprehensive security audit covering VNC, API, LXC configuration, and system hardening
- Input validation improvements across all scripts
- Secure file permissions enforcement
- Rate limiting implementation
- Enhanced error handling to prevent information disclosure

For security issues, please open a GitHub issue or contact the maintainers directly.

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request
4. Follow existing code style and security practices
5. Update documentation for new features

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

### v2.0.0 (2025-01-12)
- **Major Feature Update** - Comprehensive improvements to security, performance, and automation

#### New Features
- **API v3.0**: Production-ready REST API with webhooks, Prometheus metrics, and advanced automation
- **Clipboard Sharing**: Bidirectional clipboard integration between host and Android
- **App Installation System**: Automated batch installation of Android apps
- **LXC Performance Tuning**: Automated container optimization for Android workloads
- **Audio Passthrough**: Complete audio system with PulseAudio/PipeWire support

#### Security Enhancements
- **VNC Security**: TLS/RSA-AES encryption, password authentication, rate limiting
- **API Security**: Bearer token authentication, rate limiting, audit logging
- **Input Validation**: Comprehensive validation across all scripts and APIs
- **Security Audit**: Complete security review and hardening

#### Performance Improvements
- **VNC Optimization**: Configurable FPS (15-60), quality presets, JPEG/H.264 compression
- **Container Tuning**: CPU scheduling, memory management, I/O priorities optimization
- **Monitoring**: Built-in Prometheus metrics and performance monitoring tools

#### Documentation
- Added 8+ comprehensive guides covering all new features
- API v3.0 complete documentation with examples
- Quick reference guides for VNC and clipboard
- Enhanced troubleshooting documentation

### v1.0.0 (2025-01-12)
- Initial release
- Intel N150 support
- GPU passthrough
- VNC access via WayVNC
- Home Assistant API integration (v2.0)
- Automated installation scripts
