# Developer Handoff Document

**Last Updated:** 2025-01-12
**Branch:** `claude/waydroid-lxc-setup-011CV4mwb3C1Cp6KrtRRAAhW`
**Status:** ✅ Multi-GPU selection and community script integration complete

---

## 📋 Quick Context

This project provides an automated installer for running Android (via Waydroid) in Proxmox LXC containers with full GPU passthrough and Home Assistant integration. The installer supports Intel, AMD, and NVIDIA (software rendering) GPUs with multi-GPU selection capabilities.

### Current State
- ✅ Interactive installer with GPU/GAPPS selection
- ✅ Multi-GPU detection and selection
- ✅ Intel N150 optimization
- ✅ AMD GPU support
- ✅ Community script compatibility
- ✅ VNC access via WayVNC (port 5900)
- ✅ REST API for Home Assistant (port 8080)
- ✅ Comprehensive documentation

### Recent Changes (Last 3 Commits)
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
│   └── waydroid-lxc.sh          # Container setup (runs inside LXC)
├── install/
│   └── install.sh               # Main installer (runs on Proxmox host)
├── scripts/
│   ├── helper-functions.sh      # Shared utility functions
│   ├── configure-intel-n150.sh  # Intel GPU host configuration
│   └── test-setup.sh            # Verification script
├── config/
│   └── intel-n150.conf          # Intel N150 specific settings
├── docs/
│   ├── INSTALLATION.md          # Detailed installation guide
│   ├── HOME_ASSISTANT.md        # HA integration guide
│   └── CONFIGURATION.md         # Advanced configuration
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

### 3. Home Assistant API (`waydroid-api.py`)
**Endpoints:**
- `GET /status` - Get Waydroid status
- `GET /apps` - List installed apps
- `POST /app/launch` - Launch app by package name
- `POST /app/intent` - Send Android intent

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
- **Audio**: Audio passthrough not yet implemented
- **ARM Apps**: May need libhoudini for ARM translation on x86

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
- [ ] Audio passthrough (PulseAudio/PipeWire)
- [ ] Clipboard sharing between host and Android
- [ ] noVNC web interface (browser-based access)
- [ ] Backup/restore scripts for Waydroid data
- [ ] ARM translation layer (libhoudini/libndk) integration

### Medium Priority
- [ ] Multi-container support (multiple Android instances)
- [ ] Performance monitoring dashboard
- [ ] Automated app installation from config file
- [ ] ADB over network auto-configuration
- [ ] Container resource limits tuning guide

### Low Priority
- [ ] Custom Android builds (AOSP integration)
- [ ] Gamepad/controller passthrough
- [ ] Camera passthrough
- [ ] Sensor emulation
- [ ] F-Droid integration option

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

**Remember:** Update this document before each commit to maintain context continuity!

---

*Generated: 2025-01-12*
*Next Update Required: Before next commit*
