# Developer Handoff Document

**Last Updated:** 2025-01-13
**Branch:** `claude/continue-from-hand-011CV5J8B478BmZpAWDrfpde`
**Status:** ✅ Third session completed - Complete refactor to use Proxmox VE helper scripts

---

## 📋 Quick Context

This project provides an automated installer for running Android (via Waydroid) in Proxmox LXC containers with full GPU passthrough and Home Assistant integration. The installer supports Intel, AMD, and NVIDIA (software rendering) GPUs with multi-GPU selection capabilities.

### Current State
- ✅ Interactive installer with GPU/GAPPS selection
- ✅ Multi-GPU detection and selection
- ✅ Intel N150 optimization
- ✅ AMD GPU support
- ✅ **FULL Proxmox VE helper script integration** (NEW!)
- ✅ VNC access via WayVNC with TLS/VeNCrypt encryption (localhost only)
- ✅ Enhanced REST API v3.0 with rate limiting, webhooks, and Prometheus metrics
- ✅ Comprehensive health check and monitoring system
- ✅ Automated backup and restore functionality
- ✅ System update and upgrade automation with component-specific updates
- ✅ Performance optimization tools
- ✅ Systemd service health checks and watchdogs
- ✅ Real-time performance monitoring dashboard with JSON export
- ✅ Comprehensive error handling and logging
- ✅ LXC performance tuning and security hardening
- ✅ Audio passthrough (PulseAudio/PipeWire)
- ✅ Bidirectional clipboard sharing (VNC ↔ Android)
- ✅ App installation system with F-Droid support
- ✅ All critical security vulnerabilities fixed
- ✅ **Proper template downloading with version detection** (FIXED!)

### Recent Changes (Third Session - 2025-01-13)

**CRITICAL FIX - Template Download Issue:**
1. **Complete Refactor to Use Proxmox VE Helper Scripts:**
   - Downloaded official build.func and core.func from community-scripts/ProxmoxVE
   - Refactored install.sh to follow the jellyfin-install.sh pattern
   - Fixed template download by using `build_container()` function instead of manual `pveam download`
   - Template now correctly resolves to full version (e.g., debian-12-standard_12.7-1_amd64.tar.zst)
   - Old broken approach: `pveam download local-btrfs debian-12-standard_amd64.tar.zst` ❌
   - New working approach: `build_container()` handles template download with proper version detection ✅

2. **New Project Structure:**
   - Added `/misc/build.func` - Main Proxmox VE build and container creation functions (50K)
   - Added `/misc/core.func` - Core utility functions (colors, messaging, error handling) (13K)
   - Added `/examples/jellyfin-install.sh` - Reference implementation from community scripts
   - Backed up old install.sh to install.sh.old

3. **Improved Installation Flow:**
   - install.sh now sources community helper functions
   - Proper storage detection with BTRFS priority: local-lxc > local-btrfs > local-zfs > local
   - Automatic template version detection and download
   - Better error handling with proper exit codes
   - Template download retry logic with exponential backoff

4. **Maintained All Waydroid Features:**
   - GPU selection (Intel/AMD/NVIDIA/Software) - unchanged
   - Multi-GPU device detection and selection - unchanged
   - GAPPS option - unchanged
   - Privileged/Unprivileged containers - unchanged
   - All LXC configuration for Waydroid - unchanged

### Previous Changes (Second 2-Hour Session - 2025-01-12)

**Security Fixes (All Critical Issues Resolved):**
1. **Command Injection Fixes:**
   - Fixed eval injection vulnerability in health-check.sh (line 47)
   - Fixed command injection in install.sh (quoted all variables)
   - Added comprehensive input validation across all scripts
   - Fixed unsafe config sourcing in configure-intel-n150.sh

2. **Path Traversal & File Security:**
   - Fixed tar extraction vulnerabilities in backup-restore.sh (added --no-absolute-names, path validation)
   - Fixed race conditions in health-check.sh (atomic file operations with flock)
   - Fixed path traversal vulnerabilities across all scripts

3. **Network Security:**
   - Fixed VNC security: Changed binding from 0.0.0.0 to 127.0.0.1 (localhost only)
   - Fixed API binding: Changed from all interfaces to localhost only
   - Added TLS/VeNCrypt encryption support for VNC

4. **Permission Hardening:**
   - Fixed GPU permissions: Changed 666 → 660 in optimize-performance.sh and waydroid-lxc.sh
   - Added proper file permission checks and validation

5. **Package Security:**
   - Fixed GPG key verification in waydroid-lxc.sh
   - Added package signature validation

**Robustness Improvements:**
1. **Error Handling:**
   - Added cleanup functions to install.sh and waydroid-lxc.sh
   - Added preflight checks and post-installation verification to install.sh
   - Added exponential backoff for container readiness checks
   - Improved error recovery and rollback mechanisms

2. **Bug Fixes:**
   - Fixed zram calculation bug in optimize-performance.sh
   - Fixed systemd service type (forking → simple) in waydroid-lxc.sh
   - Added service restart verification to update-system.sh
   - Fixed race conditions with atomic file operations

**New Features:**

1. **LXC Tuning System** (scripts/tune-lxc.sh, docs/LXC_TUNING.md)
   - Performance optimizations: CPU pinning, memory limits, I/O priorities
   - Security hardening: Capability reduction, device whitelisting, AppArmor profiles
   - Monitoring system with automated health checks
   - Preset configurations for different workloads

2. **Enhanced VNC** (scripts/enhance-vnc.sh, docs/VNC-ENHANCEMENTS.md)
   - TLS/VeNCrypt encryption support
   - RSA-AES encryption for secure connections
   - noVNC web interface integration
   - Connection monitoring and rate limiting
   - Performance tuning utilities
   - Multi-user support with separate sessions

3. **REST API v3.0** (in ct/waydroid-lxc.sh, docs/API_IMPROVEMENTS_v3.0.md)
   - New endpoints:
     - `/logs` - Retrieve Waydroid logs with filtering
     - `/properties` - Get/set Waydroid properties
     - `/screenshot` - Capture Android screen
     - `/metrics` - Prometheus-compatible metrics
     - `/webhooks` - Register callbacks for events
   - Per-IP rate limiting (10 req/min)
   - API versioning support (/v1, /v2, /v3)
   - Webhooks/callbacks for container events
   - Prometheus metrics integration
   - Enhanced security and validation

4. **Audio Passthrough** (scripts/setup-audio.sh)
   - PulseAudio support with network socket
   - PipeWire support with socket passthrough
   - Auto-detection of host audio system
   - Configuration and testing utilities
   - Comprehensive troubleshooting

5. **Clipboard Sharing** (scripts/setup-clipboard.sh, docs/CLIPBOARD-SHARING.md)
   - Bidirectional sync between VNC and Android
   - Wayland clipboard integration (wl-clipboard)
   - Systemd service with health monitoring
   - Automatic reconnection on failures
   - Format conversion support

6. **App Installation System** (scripts/install-apps.sh, docs/APP_INSTALLATION.md)
   - Install from local APK files
   - Install from URL with integrity checking
   - Install from F-Droid repository
   - Batch installation from YAML/JSON config
   - APK verification and signature checking
   - Update checking and notifications
   - Rollback to previous versions

**Script Improvements:**

1. **update-system.sh:**
   - Component-specific updates (system/waydroid/drivers)
   - Timeout handling for slow operations
   - Service restart verification
   - Better error reporting

2. **monitor-performance.sh:**
   - Command availability checks
   - GPU monitoring optimization
   - Alerting on threshold violations
   - JSON export support
   - Historical logging

3. **test-setup.sh:**
   - Proper exit codes (0=success, 1=failure)
   - Comprehensive test coverage
   - JSON output mode
   - Verbose debugging mode
   - Fix suggestions for failures

4. **All Scripts:**
   - Better error handling with specific messages
   - Input validation and sanitization
   - Comprehensive logging
   - Security hardening

### Previous Session (First 2-Hour Session)
**Security Enhancements:**
1. Fixed dangerous `source <(echo)` pattern in ct/waydroid-lxc.sh
2. Added API authentication with Bearer tokens (API v2.0)
3. Added VNC password protection
4. Implemented input validation for package names and intents
5. Added request size limits and timeout protection

**New Features:**
1. Health check system (scripts/health-check.sh) - 10-point comprehensive monitoring
2. Backup/restore tool (scripts/backup-restore.sh) - Full data protection
3. Update system (scripts/update-system.sh) - Automated updates with safety
4. Performance optimizer (scripts/optimize-performance.sh) - System tuning
5. Performance monitor (scripts/monitor-performance.sh) - Real-time dashboard
6. Systemd watchdogs and health checks for all services

**Code Quality:**
1. Replaced unsafe `$STD` variable with `silent_exec()` function
2. Added comprehensive error handling to install.sh
3. Added curl timeouts and retry logic
4. Improved logging throughout API and services
5. Added resource limits to systemd services

### Earlier Changes
1. **Initial implementation** - Full Waydroid LXC setup with GPU passthrough
2. **Interactive installer** - GPU selection (Intel/AMD/NVIDIA), GAPPS option, privileged/unprivileged containers
3. **Multi-GPU selection** - Detect multiple GPUs, allow device selection, community script integration

---

## 🔗 Essential Links

### Documentation References
- **Waydroid Official Docs**: https://docs.waydro.id
- **Waydroid GitHub**: https://github.com/waydroid/waydroid
- **Waydroid Docs Repo**: https://github.com/waydroid/docs
- **Proxmox Community Scripts**: https://github.com/community-scripts/ProxmoxVE
- **Jellyfin Install Example**: https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/jellyfin-install.sh
- **Community Script Functions**: https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func
- **Community Core Functions**: https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/core.func

### Technical References
- **LXC Container Config**: https://linuxcontainers.org/lxc/manpages/man5/lxc.container.conf.5.html
- **Intel i915 Driver**: https://wiki.archlinux.org/title/Intel_graphics
- **Mesa Drivers**: https://docs.mesa3d.org/
- **Wayland Protocol**: https://wayland.freedesktop.org/docs/html/
- **WayVNC**: https://github.com/any1/wayvnc

### Home Assistant Integration
- **REST Command**: https://www.home-assistant.io/integrations/rest_command/
- **RESTful Sensor**: https://www.home-assistant.io/integrations/rest/
- **Android Intents**: https://developer.android.com/guide/components/intents-filters
- **ADB Commands**: https://developer.android.com/studio/command-line/adb

---

## 📁 Project Structure

```
waydroid-proxmox/
├── ct/
│   └── waydroid-lxc.sh          # Container setup (runs inside LXC) [API v3.0]
├── install/
│   ├── install.sh               # Main installer (uses Proxmox VE helper scripts) [REFACTORED]
│   └── install.sh.old           # Backup of original installer
├── misc/                         # [NEW] Proxmox VE helper scripts
│   ├── build.func               # Container build and creation functions (50K)
│   └── core.func                # Core utilities (colors, messaging, error handling) (13K)
├── examples/                     # [NEW] Reference implementations
│   └── jellyfin-install.sh      # Jellyfin install example from community scripts
├── scripts/
│   ├── helper-functions.sh      # Shared utility functions
│   ├── configure-intel-n150.sh  # Intel GPU host configuration [SECURED]
│   ├── test-setup.sh            # Verification script [ENHANCED]
│   ├── health-check.sh          # Comprehensive health monitoring [SECURED]
│   ├── backup-restore.sh        # Backup and restore tool [SECURED]
│   ├── update-system.sh         # System update automation [ENHANCED]
│   ├── optimize-performance.sh  # Performance tuning [SECURED]
│   ├── monitor-performance.sh   # Real-time monitoring dashboard [ENHANCED]
│   ├── tune-lxc.sh              # LXC performance & security tuning
│   ├── enhance-vnc.sh           # VNC encryption & noVNC setup
│   ├── setup-audio.sh           # Audio passthrough configuration
│   ├── setup-clipboard.sh       # Clipboard sharing setup
│   └── install-apps.sh          # App installation system
├── config/
│   └── intel-n150.conf          # Intel N150 specific settings
├── docs/
│   ├── INSTALLATION.md          # Detailed installation guide
│   ├── HOME_ASSISTANT.md        # HA integration guide
│   ├── CONFIGURATION.md         # Advanced configuration
│   ├── LXC_TUNING.md            # LXC optimization guide
│   ├── VNC-ENHANCEMENTS.md      # VNC security & features
│   ├── API_IMPROVEMENTS_v3.0.md # API v3.0 documentation
│   ├── CLIPBOARD-SHARING.md     # Clipboard integration guide
│   └── APP_INSTALLATION.md      # App management guide
├── README.md                    # Project overview
├── LICENSE                      # MIT License
└── HANDOFF.md                   # This file
```

---

## 🔧 Key Components

### 1. Main Installer (`install/install.sh`)
**Purpose:** Creates and configures LXC container on Proxmox host

**Key Features:**
- Interactive GPU selection (Intel/AMD/NVIDIA/Software)
- Multi-GPU device detection and selection
- Container type selection (privileged/unprivileged)
- GAPPS installation option
- Automatic GPU passthrough configuration
- Kernel module loading (binder_linux, ashmem_linux)

**Parameters Passed to Container:**
```bash
bash /tmp/waydroid-setup.sh "$GPU_TYPE" "$USE_GAPPS" "$SOFTWARE_RENDERING" "$GPU_DEVICE" "$RENDER_NODE"
```

**LXC Config Entries:**
```conf
lxc.mount.entry: /dev/dri/card0 dev/dri/card0 none bind,optional,create=file 0 0
lxc.mount.entry: /dev/dri/renderD128 dev/dri/renderD128 none bind,optional,create=file 0 0
```

### 2. Container Setup (`ct/waydroid-lxc.sh`)
**Purpose:** Installs and configures Waydroid inside the LXC container

**Key Features:**
- Community script compatibility (sources $FUNCTIONS_FILE_PATH)
- GPU-specific driver installation (Intel: i965-va-driver, AMD: firmware-amd-graphics)
- Waydroid repository addition and installation
- WayVNC configuration for remote access
- Python REST API for Home Assistant integration
- Systemd service creation

**Environment Variables Set:**
```bash
# Intel
MESA_LOADER_DRIVER_OVERRIDE=iris
LIBVA_DRIVER_NAME=iHD

# AMD
MESA_LOADER_DRIVER_OVERRIDE=radeonsi
LIBVA_DRIVER_NAME=radeonsi

# Software Rendering
LIBGL_ALWAYS_SOFTWARE=1
```

### 3. Home Assistant API v3.0 (`waydroid-api.py`)
**Authentication:** Bearer token (auto-generated, stored in `/etc/waydroid-api/token`)

**GET Endpoints:**
- `/health` - Health check (no auth required)
- `/status` - Get Waydroid status (requires auth)
- `/version` - Get Waydroid and API versions (requires auth)
- `/apps` - List installed apps with count (requires auth)
- `/logs` - Retrieve Waydroid logs with filtering (requires auth)
- `/properties` - Get Waydroid properties (requires auth)
- `/screenshot` - Capture Android screen (requires auth)
- `/metrics` - Prometheus-compatible metrics (requires auth)

**POST Endpoints:**
- `/app/launch` - Launch app by package name (requires auth)
- `/app/stop` - Force stop app (requires auth)
- `/app/intent` - Send Android intent (requires auth)
- `/container/restart` - Restart Waydroid container (requires auth)
- `/properties` - Set Waydroid properties (requires auth)
- `/webhooks` - Register callback URLs for events (requires auth)

**Security Features:**
- Input validation (package names, intents, URLs)
- Request size limits (max 10KB)
- Timeout protection (5-15s per operation)
- Per-IP rate limiting (10 requests/minute)
- Comprehensive logging to `/var/log/waydroid-api.log`
- Localhost-only binding (127.0.0.1)
- API versioning support (/v1, /v2, /v3)

**New Features in v3.0:**
- Webhooks for container lifecycle events
- Prometheus metrics endpoint
- Screenshot capture capability
- Log retrieval with filtering
- Property management
- Enhanced error reporting

**Usage Example:**
```bash
# Get token
TOKEN=$(cat /etc/waydroid-api/token)

# Make authenticated request
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/status

# Get metrics (Prometheus)
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/metrics

# Register webhook
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"url": "http://homeassistant:8123/webhook/waydroid", "events": ["started", "stopped"]}' \
  http://localhost:8080/webhooks
```

---

## 🎯 Testing Checklist

Before committing changes, test these scenarios:

### GPU Scenarios
- [ ] Intel single GPU
- [ ] Intel multi-GPU (iGPU + dGPU)
- [ ] AMD single GPU
- [ ] AMD multi-GPU
- [ ] Intel + AMD hybrid
- [ ] NVIDIA (software rendering)
- [ ] Software rendering (no GPU)

### Container Types
- [ ] Privileged with GPU passthrough
- [ ] Unprivileged with software rendering

### GAPPS Options
- [ ] With GAPPS (Play Store)
- [ ] Without GAPPS (vanilla)

### Integration Tests
- [ ] VNC connection works (port 5900)
- [ ] API responds to /status
- [ ] App launch via API works
- [ ] Waydroid initializes correctly
- [ ] GPU acceleration active (if hardware)

---

## 🛠️ New Tools and Scripts

### Health Check System (`scripts/health-check.sh`)
Comprehensive 10-point health monitoring system that checks:
- System resources (CPU, memory, disk)
- Kernel modules (binder, ashmem)
- GPU devices and permissions
- Waydroid installation and services
- VNC and API servers
- Network connectivity
- Recent errors and logs

**Usage:**
```bash
./scripts/health-check.sh          # Run health check
crontab -e                          # Add to cron for automated monitoring
*/10 * * * * /path/to/health-check.sh
```

### Backup and Restore (`scripts/backup-restore.sh`)
Complete backup solution for Waydroid data:
- Supports data-only and full backups
- Automatic cleanup of old backups
- Export/import functionality
- Preserves configurations and apps

**Usage:**
```bash
./scripts/backup-restore.sh backup --full    # Full backup including images
./scripts/backup-restore.sh list             # List backups
./scripts/backup-restore.sh restore <name>   # Restore from backup
./scripts/backup-restore.sh export <name>    # Export to tar.gz
```

### System Update (`scripts/update-system.sh`)
Safe automated update system:
- Updates system packages
- Updates Waydroid
- Updates GPU drivers
- Automatic backup before updates
- Post-update health checks

**Usage:**
```bash
./scripts/update-system.sh              # Full update
./scripts/update-system.sh --dry-run    # Preview updates
./scripts/update-system.sh --system-only # Only update packages
```

### Performance Optimization (`scripts/optimize-performance.sh`)
System tuning for optimal performance:
- Kernel parameter optimization
- CPU governor configuration
- I/O scheduler tuning
- Memory and GPU optimizations
- Waydroid property tuning

**Usage:**
```bash
./scripts/optimize-performance.sh       # Apply all optimizations
```

### Performance Monitor (`scripts/monitor-performance.sh`)
Real-time performance dashboard:
- CPU, memory, disk usage
- Service status monitoring
- Network statistics
- GPU usage (if available)
- API and VNC monitoring
- JSON export support
- Alert thresholds

**Usage:**
```bash
./scripts/monitor-performance.sh                # Live dashboard
./scripts/monitor-performance.sh --once         # Single snapshot
./scripts/monitor-performance.sh --interval 5   # Custom refresh
./scripts/monitor-performance.sh --json         # JSON output
```

### LXC Tuning (`scripts/tune-lxc.sh`)
Comprehensive LXC container optimization:
- Performance tuning: CPU pinning, memory limits, I/O scheduler
- Security hardening: Capability reduction, device whitelisting
- Monitoring system with health checks
- Preset configurations (performance/balanced/security)

**Usage:**
```bash
./scripts/tune-lxc.sh --preset performance     # Apply performance optimizations
./scripts/tune-lxc.sh --preset security        # Apply security hardening
./scripts/tune-lxc.sh --monitor                # Start monitoring system
./scripts/tune-lxc.sh --status                 # Show current configuration
```

### VNC Enhancements (`scripts/enhance-vnc.sh`)
Secure and feature-rich VNC access:
- TLS/VeNCrypt encryption setup
- RSA-AES encryption configuration
- noVNC web interface installation
- Connection monitoring and rate limiting
- Performance tuning

**Usage:**
```bash
./scripts/enhance-vnc.sh --tls                 # Enable TLS encryption
./scripts/enhance-vnc.sh --novnc               # Install noVNC web interface
./scripts/enhance-vnc.sh --monitor             # Monitor VNC connections
./scripts/enhance-vnc.sh --tune                # Apply performance tuning
```

### Audio Passthrough (`scripts/setup-audio.sh`)
Audio integration for Android apps:
- PulseAudio support with network socket
- PipeWire support with socket passthrough
- Auto-detection of host audio system
- Configuration testing and verification

**Usage:**
```bash
./scripts/setup-audio.sh                       # Auto-detect and configure
./scripts/setup-audio.sh --pulseaudio          # Force PulseAudio
./scripts/setup-audio.sh --pipewire            # Force PipeWire
./scripts/setup-audio.sh --test                # Test audio playback
```

### Clipboard Sharing (`scripts/setup-clipboard.sh`)
Bidirectional clipboard integration:
- VNC ↔ Android clipboard sync
- Wayland clipboard support (wl-clipboard)
- Systemd service with health monitoring
- Automatic reconnection on failures

**Usage:**
```bash
./scripts/setup-clipboard.sh                   # Install and configure
./scripts/setup-clipboard.sh --start           # Start clipboard service
./scripts/setup-clipboard.sh --status          # Check service status
./scripts/setup-clipboard.sh --test            # Test clipboard sync
```

### App Installation (`scripts/install-apps.sh`)
Comprehensive app management system:
- Install from local APK, URL, or F-Droid
- Batch installation from config files (YAML/JSON)
- APK verification and signature checking
- Update checking and rollback support

**Usage:**
```bash
./scripts/install-apps.sh --local app.apk              # Install local APK
./scripts/install-apps.sh --url https://example.com/app.apk  # Install from URL
./scripts/install-apps.sh --fdroid com.example.app    # Install from F-Droid
./scripts/install-apps.sh --batch apps.yaml           # Batch install from config
./scripts/install-apps.sh --list                      # List installed apps
./scripts/install-apps.sh --update                    # Check for updates
```

## 🐛 Known Issues & Limitations

### Current Limitations
1. **NVIDIA GPU**: No hardware acceleration support (kernel driver limitations)
2. **Wayland Only**: Requires Wayland compositor (no X11 support)
3. **Network**: Some Android apps may have connectivity issues
4. **SafetyNet**: Banking apps with SafetyNet likely won't work
5. **IPv6 Required**: Kernel must have IPv6 enabled for Android networking

### Potential Issues
- **Binder Modules**: May not be available on all kernels (requires 5.15+)
- **Multiple Displays**: Not tested with multi-monitor setups
- **ARM Apps**: May need libhoudini for ARM translation on x86

### Fixed in Second Session (2025-01-12)
**Critical Security Issues (ALL RESOLVED):**
- ✅ Eval injection in health-check.sh
- ✅ Command injection in install.sh
- ✅ Tar extraction vulnerabilities in backup-restore.sh
- ✅ Unsafe config sourcing in configure-intel-n150.sh
- ✅ GPU permissions too permissive (666 → 660)
- ✅ VNC bound to all interfaces (0.0.0.0 → 127.0.0.1)
- ✅ API bound to all interfaces (now localhost only)
- ✅ Path traversal vulnerabilities
- ✅ Race conditions in health-check.sh
- ✅ GPG key verification missing

**Robustness Issues Fixed:**
- ✅ Missing error handling and cleanup functions
- ✅ No preflight checks in installer
- ✅ Container readiness race conditions
- ✅ Zram calculation bug
- ✅ Systemd service type incorrect (forking → simple)
- ✅ Missing service restart verification

**Feature Gaps Addressed:**
- ✅ Audio passthrough implemented
- ✅ Clipboard sharing implemented
- ✅ App installation system created
- ✅ LXC tuning and security hardening
- ✅ VNC encryption and noVNC support
- ✅ API v3.0 with webhooks and metrics

### Fixed in First Session
- ✅ Command injection vulnerabilities in API
- ✅ Unprotected VNC access
- ✅ Missing error handling in installer
- ✅ No backup/restore functionality
- ✅ No health monitoring
- ✅ No update mechanism

---

## 📝 Development Guidelines

### Before Each Commit

1. **Update This Document** (HANDOFF.md):
   - Update "Last Updated" date
   - Add new changes to "Recent Changes" section
   - Update "Current State" checklist if features added/removed
   - Add new known issues if discovered
   - Update testing checklist if new scenarios added

2. **Run Basic Tests**:
   ```bash
   # Check script syntax
   bash -n install/install.sh
   bash -n ct/waydroid-lxc.sh

   # Verify executable permissions
   ls -la install/*.sh ct/*.sh scripts/*.sh
   ```

3. **Update Documentation**:
   - Update README.md if public-facing features changed
   - Update INSTALLATION.md if installation steps changed
   - Update CONFIGURATION.md if new config options added
   - Update HOME_ASSISTANT.md if API endpoints changed

4. **Commit Message Format**:
   ```
   Brief description (50 chars or less)

   Detailed explanation of changes:
   - What was changed
   - Why it was changed
   - Impact on existing functionality

   Testing:
   - Scenarios tested
   - Known issues discovered

   Related:
   - Links to relevant issues/docs
   ```

### Code Style

**Shell Scripts:**
- Use 4-space indentation
- Quote all variables: `"$VARIABLE"`
- Use `[[` instead of `[` for tests
- Prefer `$()` over backticks
- Use descriptive function names
- Add comments for complex logic

**Example:**
```bash
# Good
if [[ "$GPU_TYPE" = "intel" ]]; then
    msg_info "Installing Intel drivers..."
fi

# Bad
if [ $GPU_TYPE = "intel" ]
then
  echo "Installing Intel drivers"
fi
```

### Community Script Integration

When adding features that should use community functions:

1. **Check if function exists**: `command -v function_name &>/dev/null`
2. **Use if available**: `if command -v cleanup_lxc &>/dev/null; then cleanup_lxc; fi`
3. **Provide fallback**: Always have a fallback implementation
4. **Test standalone**: Ensure scripts work without community functions

---

## 🚀 Future Enhancements (TODO)

### High Priority
- [ ] ARM translation layer (libhoudini/libndk) integration
- [ ] Multi-container support (multiple Android instances)
- [ ] ADB over network auto-configuration
- [ ] Custom Android builds (AOSP integration)

### Medium Priority
- [ ] Gamepad/controller passthrough
- [ ] Camera passthrough
- [ ] Sensor emulation
- [ ] Multi-user VNC sessions
- [ ] Advanced API rate limiting per endpoint

### Low Priority
- [ ] Automated testing framework
- [ ] Container templates for different use cases
- [ ] Integration with Proxmox HA
- [ ] Advanced resource scheduling
- [ ] Custom ROM support

### Completed in Second Session (2025-01-12)
- [✅] Audio passthrough (PulseAudio/PipeWire)
- [✅] Clipboard sharing between host and Android
- [✅] noVNC web interface (browser-based access)
- [✅] Automated app installation from config file
- [✅] Container resource limits tuning guide (LXC_TUNING.md)
- [✅] F-Droid integration option
- [✅] LXC performance and security tuning
- [✅] VNC encryption (TLS/VeNCrypt)
- [✅] API v3.0 with webhooks and metrics
- [✅] All critical security vulnerabilities resolved
- [✅] Comprehensive robustness improvements

### Completed in First Session
- [✅] API authentication and security
- [✅] VNC password protection
- [✅] Backup and restore functionality
- [✅] Health check system
- [✅] Performance monitoring
- [✅] System update automation
- [✅] Performance optimization tools
- [✅] Systemd service watchdogs
- [✅] Comprehensive error handling
- [✅] Input validation and sanitization

---

## 🔍 Debugging Tips

### Container Won't Start
```bash
# Check LXC config
cat /etc/pve/lxc/<ctid>.conf

# Check kernel modules
lsmod | grep -E "binder|ashmem"

# Check container logs
pct enter <ctid>
journalctl -xe
```

### GPU Not Working
```bash
# Inside container
ls -la /dev/dri/
groups  # Should include render, video

# Check Mesa
glxinfo | grep -i renderer
vainfo
```

### Waydroid Issues
```bash
# Check status
waydroid status

# View logs
waydroid log

# Reinitialize
waydroid init -f
```

### API Not Responding
```bash
# Check service
systemctl status waydroid-api

# Check port
netstat -tuln | grep 8080

# Test locally
curl http://localhost:8080/status
```

---

## 📞 Support & Resources

### Getting Help
- **GitHub Issues**: [iceteaSA/waydroid-proxmox/issues](https://github.com/iceteaSA/waydroid-proxmox/issues)
- **Waydroid Issues**: [waydroid/waydroid/issues](https://github.com/waydroid/waydroid/issues)
- **Proxmox Forum**: https://forum.proxmox.com/

### Community
- **Waydroid Telegram**: https://t.me/WayDroid
- **Proxmox Reddit**: https://www.reddit.com/r/Proxmox/
- **Home Assistant Community**: https://community.home-assistant.io/

---

## ✅ Pre-Commit Checklist

Before committing, verify:

- [ ] This HANDOFF.md document is updated
- [ ] All scripts pass syntax check (`bash -n`)
- [ ] Executable permissions are correct (`chmod +x`)
- [ ] No hardcoded paths or secrets in code
- [ ] Documentation matches code changes
- [ ] Commit message is descriptive
- [ ] Changes tested on at least one scenario
- [ ] Known issues documented if discovered

---

## 📊 Metrics & Analytics

### Performance Targets
- **Container Creation**: < 5 minutes
- **Waydroid Init**: < 3 minutes (without GAPPS), < 5 minutes (with GAPPS)
- **Boot Time**: < 30 seconds (after init)
- **RAM Usage**: ~1.5GB (idle), ~2.5GB (with apps)
- **API Response**: < 100ms

### Compatibility Matrix

| Component | Intel | AMD | NVIDIA | Software |
|-----------|-------|-----|--------|----------|
| GPU Passthrough | ✅ | ✅ | ❌ | N/A |
| Hardware Accel | ✅ | ✅ | ❌ | ❌ |
| VA-API | ✅ | ✅ | ❌ | ❌ |
| Vulkan | ✅ | ✅ | ❌ | ❌ |
| Multi-GPU | ✅ | ✅ | ❌ | N/A |

---

## 🎓 Learning Resources

### For New Developers

**LXC Containers:**
- [LXC Getting Started](https://linuxcontainers.org/lxc/getting-started/)
- [Proxmox LXC Documentation](https://pve.proxmox.com/wiki/Linux_Container)

**Waydroid:**
- [Waydroid Architecture](https://github.com/waydroid/waydroid/wiki/Architecture)
- [Waydroid Development](https://github.com/waydroid/waydroid/wiki/Development)

**GPU Passthrough:**
- [Intel GPU Passthrough Guide](https://wiki.archlinux.org/title/Intel_GVT-g)
- [Mesa Documentation](https://docs.mesa3d.org/)

**Home Assistant:**
- [REST API Integration](https://www.home-assistant.io/integrations/rest/)
- [Automations Guide](https://www.home-assistant.io/docs/automation/)

---

## 📊 Session Summary

### Second 2-Hour Session (2025-01-12)
**Primary Achievement:** Resolved all critical security vulnerabilities and added 6 major feature systems

**Security Impact:**
- 10+ critical vulnerabilities fixed
- Complete security audit performed
- All command injection vectors eliminated
- Network exposure minimized (localhost-only bindings)
- File permissions hardened

**Feature Impact:**
- 5 new scripts added (LXC tuning, VNC enhancements, audio, clipboard, app installation)
- 4 new documentation files added
- API upgraded from v2.0 to v3.0
- Comprehensive security hardening across all components

**Quality Impact:**
- Improved error handling in 8+ scripts
- Added input validation everywhere
- Fixed multiple race conditions
- Enhanced logging and monitoring
- Better user experience with fix suggestions

**Files Modified:** 15+ scripts and configuration files
**Files Created:** 9 new files (5 scripts, 4 documentation files)
**Lines Changed:** 1000+ lines of code improvements

---

**Remember:** Update this document before each commit to maintain context continuity!

---

*Last Generated: 2025-01-12 (Second 2-Hour Session)*
*Next Update Required: Before next commit*
