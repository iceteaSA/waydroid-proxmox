# Filesystem Hierarchy Standard (FHS) Compliance

This document outlines the file and directory structure used by Waydroid Proxmox installation, following the Linux Filesystem Hierarchy Standard (FHS) 3.0.

## Overview

All installation paths follow FHS best practices for maintainability, security, and system integration.

---

## Directory Structure

### Executable Binaries

#### `/usr/local/bin/` - Custom Scripts
**Purpose:** Locally-installed executables
**FHS Compliance:** ✅ Correct location for custom system-wide scripts

```
/usr/local/bin/
├── start-waydroid.sh           # Main Waydroid startup orchestration
├── waydroid-api.py             # Home Assistant REST API server
├── waydroid-clipboard          # Clipboard management utility
└── waydroid-clipboard-sync.sh  # Clipboard synchronization daemon
```

**Permissions:**
- Owner: root:root
- Mode: 755 (executable by all, writable by root only)

---

### System Configuration

#### `/etc/wayvnc/` - WayVNC Configuration
**Purpose:** System-wide VNC server configuration
**FHS Compliance:** ✅ **NEW** - Moved from `/root/.config/` for FHS compliance

```
/etc/wayvnc/
├── config      # WayVNC server configuration
└── password    # VNC authentication password (hashed)
```

**Permissions:**
- `config`: 644 (readable by all, writable by root)
- `password`: 600 (readable/writable by root only)

**Migration Note:** Previous installations used `/root/.config/wayvnc/`. This has been moved to `/etc/` for:
- System-wide accessibility
- Service account compatibility
- Standard backup integration
- FHS compliance

#### `/etc/systemd/system/` - Service Definitions
**Purpose:** Systemd service units
**FHS Compliance:** ✅ Correct location for custom services

```
/etc/systemd/system/
├── waydroid-vnc.service              # VNC server service
├── waydroid-api.service              # API server service
├── waydroid-clipboard-sync.service   # Clipboard sync service
└── waydroid-container.service        # Waydroid container service (created by waydroid)
```

#### `/etc/waydroid-api/` - API Configuration
**Purpose:** Home Assistant API configuration
**FHS Compliance:** ✅ Correct location for application config

```
/etc/waydroid-api/
├── token           # API authentication token
├── webhooks.json   # Webhook endpoints
└── rate-limits.json# Rate limiting configuration
```

**Permissions:** All files 600 (root access only)

#### `/etc/apt/sources.list.d/` - Package Repositories
**Purpose:** Third-party package sources
**FHS Compliance:** ✅ Standard Debian/Ubuntu location

```
/etc/apt/sources.list.d/
└── waydroid.list   # Waydroid official repository
```

#### `/etc/modules-load.d/` - Kernel Modules
**Purpose:** Modules to load at boot
**FHS Compliance:** ✅ Systemd standard location

```
/etc/modules-load.d/
└── waydroid.conf   # binder_linux, ashmem_linux
```

#### `/etc/udev/rules.d/` - Device Rules
**Purpose:** GPU device permissions
**FHS Compliance:** ✅ Standard udev location

```
/etc/udev/rules.d/
└── 99-waydroid-gpu.rules   # GPU passthrough permissions
```

---

### Application Data

#### `/var/lib/waydroid/` - Waydroid State Data
**Purpose:** Persistent Waydroid container data
**FHS Compliance:** ✅ Correct location for application state

```
/var/lib/waydroid/
├── overlay/             # Android filesystem overlay
├── waydroid.cfg         # Waydroid configuration
├── waydroid.prop        # Android system properties
├── lxc/                 # LXC container data
└── images/              # Android system images
```

**Size:** Can grow to 5-10GB depending on apps installed

#### `/var/lib/waydroid-clipboard/` - Clipboard State
**Purpose:** Clipboard synchronization cache
**FHS Compliance:** ✅ Correct location for application state

```
/var/lib/waydroid-clipboard/
├── clipboard.cache      # Last synchronized clipboard content
└── sync.state           # Sync daemon state
```

---

### Log Files

#### `/var/log/` - Application Logs
**Purpose:** Application logging
**FHS Compliance:** ✅ Standard log location

```
/var/log/
├── waydroid-api.log         # API server logs
├── waydroid-clipboard.log   # Clipboard sync logs
└── waydroid-arm/            # ARM translation logs
    ├── setup-YYYYMMDD-HHMMSS.log
    └── install.log
```

**Log Rotation:** Configured via `/etc/logrotate.d/waydroid-clipboard`

---

### Cache and Temporary Data

#### `/var/cache/waydroid-arm/` - ARM Translation Cache
**Purpose:** Downloaded ARM translation components
**FHS Compliance:** ✅ Correct for cached/downloadable data

```
/var/cache/waydroid-arm/
├── backup/              # Configuration backups
└── waydroid_script/     # Downloaded translation scripts
```

**Note:** Can be safely deleted and regenerated

#### `/var/backups/waydroid/` - System Backups
**Purpose:** Waydroid backup storage
**FHS Compliance:** ✅ Standard Debian/Ubuntu backup location

```
/var/backups/waydroid/
└── YYYYMMDD-HHMMSS/     # Timestamped backup directories
    ├── waydroid.cfg
    ├── wayvnc/
    ├── vnc-password.txt
    └── data/
```

---

### Runtime Data

#### `/run/user/0/` - Root User Runtime Directory
**Purpose:** Runtime sockets and temporary files
**FHS Compliance:** ✅ Correct for runtime data (XDG_RUNTIME_DIR)

```
/run/user/0/
├── wayland-1           # Sway Wayland socket
├── pipewire-0          # PipeWire audio socket (if used)
└── pulse/              # PulseAudio sockets
    └── native
```

**Note:** Volatile storage, cleared on reboot

---

### User-Specific Data

#### `/home/waydroid/` - Waydroid User Home
**Purpose:** User-specific data and configuration
**FHS Compliance:** ✅ Correct for user data

```
/home/waydroid/
├── .local/share/waydroid/   # User Waydroid data
└── .config/
    └── pulse/               # User PulseAudio config (if needed)
```

#### `/root/` - Root User Reference Files
**Purpose:** User-accessible reference files
**FHS Compliance:** ⚠️ Convenience only - not primary storage

```
/root/
└── vnc-password.txt    # VNC password reference (copy of /etc/wayvnc/password)
```

**Note:** This is a convenience copy for easy access. Primary configuration is in `/etc/wayvnc/`.

---

## User-Facing Scripts (Not Yet Installed)

**Current Location:** Repository directory (`waydroid-proxmox/scripts/`)
**Status:** ⚠️ Not installed system-wide
**Future Plan:** Install to `/opt/waydroid-proxmox/` with symlinks in `/usr/local/bin/`

### Proposed `/opt/` Structure

```
/opt/waydroid-proxmox/
├── bin/                    # Main executables
│   ├── waydroid-backup
│   ├── waydroid-restore
│   ├── waydroid-health-check
│   └── waydroid-optimize
├── scripts/                # Management scripts
│   ├── setup-audio.sh
│   ├── setup-clipboard.sh
│   ├── enhance-vnc.sh
│   └── tune-lxc.sh
├── lib/                    # Helper libraries
│   └── helper-functions.sh
└── doc/                    # Documentation
    ├── README.md
    └── examples/
```

**Symlinks in `/usr/local/bin/`:**
```bash
/usr/local/bin/waydroid-backup -> /opt/waydroid-proxmox/bin/waydroid-backup
/usr/local/bin/waydroid-health -> /opt/waydroid-proxmox/bin/waydroid-health-check
```

---

## Proxmox-Specific Paths

#### `/etc/pve/lxc/<CTID>.conf` - Container Configuration
**Purpose:** LXC container settings
**FHS Compliance:** ✅ Proxmox-specific standard location

```
/etc/pve/lxc/
└── <CTID>.conf    # Container config with device passthrough
```

---

## Migration Guide

### From Previous Versions

If you have an existing installation with configs in `/root/.config/wayvnc/`:

```bash
# Backup existing config
cp -a /root/.config/wayvnc /root/.config/wayvnc.backup

# Move to FHS-compliant location
mv /root/.config/wayvnc /etc/wayvnc

# Fix permissions
chmod 644 /etc/wayvnc/config
chmod 600 /etc/wayvnc/password

# Restart services
systemctl restart waydroid-vnc.service
```

**Note:** The installation scripts now automatically use `/etc/wayvnc/`, so new installations require no manual intervention.

---

## Benefits of FHS Compliance

### Security
- Proper file ownership and permissions
- Credentials in system-protected locations
- Clear separation of user vs. system data

### Maintainability
- Standard backup tools automatically include `/etc/` and `/var/`
- Easy to locate and modify configurations
- Clear upgrade/migration paths

### Compatibility
- Works with configuration management tools (Ansible, Puppet, etc.)
- Integrates with system monitoring
- Follows distribution conventions

### Multi-User Support
- System-wide services don't depend on root home directory
- Service accounts can access configuration
- Proper permissions for shared access

---

## Permissions Reference

| Path | Owner | Mode | Purpose |
|------|-------|------|---------|
| `/etc/wayvnc/config` | root:root | 644 | VNC server config (readable by all) |
| `/etc/wayvnc/password` | root:root | 600 | VNC password (root only) |
| `/etc/waydroid-api/token` | root:root | 600 | API token (root only) |
| `/usr/local/bin/*.sh` | root:root | 755 | Executables (all can run) |
| `/var/lib/waydroid/` | root:root | 755 | App data (root manages) |
| `/var/log/*.log` | root:root | 644 | Logs (readable for debugging) |
| `/root/vnc-password.txt` | root:root | 600 | Reference copy (root only) |

---

## Backup Recommendations

### Essential Paths to Backup

```bash
# Configuration
/etc/wayvnc/
/etc/waydroid-api/
/etc/systemd/system/waydroid-*.service

# Data
/var/lib/waydroid/
/var/lib/waydroid-clipboard/

# Reference
/root/vnc-password.txt
```

### Can Be Regenerated (Optional Backup)

```bash
# Caches
/var/cache/waydroid-arm/

# Logs
/var/log/waydroid-*.log
```

---

## Related Documentation

- [Debian 13 Migration Guide](DEBIAN-13-MIGRATION.md)
- [Installation Guide](QUICKSTART.md)
- [Backup & Restore](scripts/backup-restore.sh)
- [FHS 3.0 Standard](https://refspecs.linuxfoundation.org/FHS_3.0/fhs-3.0.html)

---

**Last Updated:** 2025-11-13
**Version:** 2.0 (FHS Compliance Update)
