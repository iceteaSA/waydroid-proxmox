# Upgrade Guide - v1.x to v2.0

This guide will help you safely upgrade your Waydroid Proxmox installation from v1.x to v2.0, which includes critical security patches and new features.

## Table of Contents

- [Overview](#overview)
- [What's New in v2.0](#whats-new-in-v20)
- [Before You Begin](#before-you-begin)
- [Upgrade Process](#upgrade-process)
- [Rollback Instructions](#rollback-instructions)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)

## Overview

Version 2.0 brings major security improvements, bug fixes, and new features to the Waydroid Proxmox setup. The upgrade script automates the migration process while preserving your Android data and existing configuration.

**Key Features of the Upgrade Script:**
- ✅ Automatic backup and rollback capability
- ✅ Pre-flight validation checks
- ✅ Service state preservation
- ✅ Dry-run mode for testing
- ✅ Interactive and non-interactive modes
- ✅ Comprehensive upgrade reports

## What's New in v2.0

### Critical Security Patches (Always Applied)

1. **VNC Security**
   - Changed binding from `0.0.0.0` to `127.0.0.1` (localhost only)
   - Prevents external VNC access without SSH tunnel
   - Adds TLS/VeNCrypt encryption support

2. **API Security**
   - Localhost binding (prevents external API access)
   - Rate limiting (10 requests/minute per IP)
   - Enhanced authentication with Bearer tokens
   - Input validation and sanitization

3. **GPU Permissions**
   - Fixed overly permissive 666 → 660 permissions
   - Proper render group management
   - Device access hardening

4. **Systemd Services**
   - Fixed service type (forking → simple)
   - Added security directives (ProtectSystem, PrivateTmp)
   - Resource limits and watchdogs
   - Health check integration

5. **Package Security**
   - GPG key verification for Waydroid packages
   - Package signature validation
   - Secure repository configuration

### New Features (Optional)

#### 1. LXC Tuning System
Container optimization and security hardening:
- CPU pinning and NUMA optimization
- Memory limits and zswap tuning
- I/O priority configuration
- Capability reduction
- AppArmor profile hardening
- Automated health monitoring

**Script:** `/root/waydroid-proxmox/scripts/tune-lxc.sh`

#### 2. VNC Enhancements
Improved VNC functionality:
- TLS 1.3 encryption
- RSA-AES encryption
- noVNC web interface
- Performance tuning (FPS, quality)
- Connection monitoring
- Multi-user support

**Script:** `/root/waydroid-proxmox/scripts/enhance-vnc.sh`

#### 3. Audio Passthrough
Full audio support in Android:
- PulseAudio support
- PipeWire support
- Auto-detection of host audio system
- Volume control integration
- Comprehensive troubleshooting

**Script:** `/root/waydroid-proxmox/scripts/setup-audio.sh`

#### 4. Clipboard Sharing
Bidirectional clipboard sync:
- Copy from Android → VNC client
- Copy from VNC client → Android
- Format conversion support
- Automatic reconnection
- Systemd service with health monitoring

**Script:** `/root/waydroid-proxmox/scripts/setup-clipboard.sh`

#### 5. App Installation System
Easy Android app management:
- Install from local APK files
- Install from URL with verification
- F-Droid repository integration
- Batch installation from YAML/JSON
- Update checking
- Rollback to previous versions

**Script:** `/usr/local/bin/install-apps`

### Component Updates

1. **REST API v3.0**
   - New endpoints: `/logs`, `/properties`, `/screenshot`, `/metrics`, `/webhooks`
   - API versioning support
   - Prometheus metrics integration
   - Webhook callbacks for events

2. **Enhanced Tools**
   - Improved health check system (10-point monitoring)
   - Advanced backup/restore with validation
   - Performance monitoring dashboard
   - Automated update system

## Before You Begin

### Requirements

- Running Waydroid LXC container (v1.0 or later)
- Root access to the container
- At least 1GB free disk space
- Network connectivity for package updates
- 5-10 minutes for the upgrade process

### Important Notes

1. **Android Data is Safe**: The upgrade process does NOT modify your Android apps or data in `/var/lib/waydroid/data`

2. **Services Will Be Restarted**: VNC and API services will be temporarily stopped during the upgrade

3. **Backup Recommended**: While the script creates automatic backups, consider running a manual backup first:
   ```bash
   /root/waydroid-proxmox/scripts/backup-restore.sh backup --full
   ```

4. **SSH Access Required**: After upgrade, VNC will only be accessible via SSH tunnel (security improvement)

### Checking Current Version

```bash
cd /root/waydroid-proxmox
bash scripts/upgrade-from-v1.sh --check
```

This will show your current version and available upgrades.

## Upgrade Process

### Method 1: Interactive Upgrade (Recommended)

This method guides you through feature selection:

```bash
cd /root/waydroid-proxmox
bash scripts/upgrade-from-v1.sh
```

You'll be prompted to:
1. Confirm the upgrade
2. Select which optional features to install
3. Review the upgrade plan
4. Proceed with the upgrade

### Method 2: Security Patches Only

Apply only critical security fixes without new features:

```bash
cd /root/waydroid-proxmox
bash scripts/upgrade-from-v1.sh --security-only
```

### Method 3: Full Upgrade (All Features)

Install all v2.0 features non-interactively:

```bash
cd /root/waydroid-proxmox
bash scripts/upgrade-from-v1.sh --non-interactive --yes --all-features
```

### Method 4: Selective Features

Choose specific features to install:

```bash
cd /root/waydroid-proxmox
bash scripts/upgrade-from-v1.sh --features vnc,audio,clipboard
```

Available features:
- `lxc-tuning` or `lxc` - LXC container optimization
- `vnc` - VNC enhancements
- `audio` - Audio passthrough
- `clipboard` - Clipboard sharing
- `apps` or `app-system` - App installation system

### Method 5: Dry Run (Preview Changes)

Test the upgrade without making changes:

```bash
cd /root/waydroid-proxmox
bash scripts/upgrade-from-v1.sh --dry-run --all-features
```

## Step-by-Step Walkthrough

### 1. Prepare for Upgrade

Enter your Waydroid container:
```bash
# From Proxmox host
pct enter <CTID>

# Inside container
cd /root/waydroid-proxmox
```

Update the repository (if you haven't already):
```bash
git pull origin main
```

### 2. Run Pre-Upgrade Check

```bash
bash scripts/upgrade-from-v1.sh --check
```

This shows:
- Current version
- Target version
- Available improvements

### 3. Optional: Test with Dry Run

```bash
bash scripts/upgrade-from-v1.sh --dry-run
```

This previews all changes without applying them.

### 4. Execute Upgrade

For interactive upgrade:
```bash
bash scripts/upgrade-from-v1.sh
```

The script will:
1. ✅ Run preflight checks
2. ✅ Create automatic backup
3. ✅ Ask which features to install
4. ✅ Stop services temporarily
5. ✅ Apply security patches
6. ✅ Install selected features
7. ✅ Restart services
8. ✅ Verify upgrade success
9. ✅ Generate upgrade report

### 5. Review Results

The script generates a comprehensive report:
```bash
cat /var/lib/waydroid-upgrade/upgrade-report-*.txt
```

Check service status:
```bash
systemctl status waydroid-vnc
systemctl status waydroid-api
```

### 6. Test Functionality

Test VNC access (now requires SSH tunnel):
```bash
# From your local machine
ssh -L 5900:localhost:5900 root@<container-ip>
# Then connect VNC client to localhost:5900
```

Test API:
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:8080/status
```

### 7. Optional: Configure New Features

If you installed optional features, configure them:

**LXC Tuning** (run from Proxmox host):
```bash
# Copy script to host
pct pull <CTID> /root/tune-lxc.sh /tmp/tune-lxc.sh

# Run on host
bash /tmp/tune-lxc.sh <CTID> --preset performance
```

**Audio Setup**:
```bash
/root/waydroid-proxmox/scripts/setup-audio.sh --configure
```

**Clipboard Sharing**:
```bash
systemctl enable waydroid-clipboard-sync
systemctl start waydroid-clipboard-sync
```

**Install Apps**:
```bash
install-apps install /path/to/app.apk
# or
install-apps install-fdroid org.fdroid.fdroid
```

## Rollback Instructions

If you need to revert the upgrade:

### Automatic Rollback

If the upgrade fails, you'll be prompted to rollback automatically.

### Manual Rollback

```bash
bash /var/lib/waydroid-upgrade/rollback.sh
```

This will:
- Restore all backed-up files
- Restore service configurations
- Restore previous version
- Restart services in their previous state

### Verify Rollback

```bash
cat /etc/waydroid-proxmox.version
systemctl status waydroid-vnc waydroid-api
```

## Post-Upgrade Tasks

### Update VNC Access Method

VNC now binds to localhost for security. Update your access method:

**Option 1: SSH Tunnel (Recommended)**
```bash
ssh -L 5900:localhost:5900 root@<container-ip>
# Connect VNC to localhost:5900
```

**Option 2: noVNC Web Interface** (if installed)
```bash
# Access via: https://<container-ip>:6080
```

### Update API Access

API now requires localhost access or SSH tunnel:

```bash
# From within container
curl -H "Authorization: Bearer TOKEN" http://localhost:8080/status

# Or from host via SSH tunnel
ssh -L 8080:localhost:8080 root@<container-ip>
curl -H "Authorization: Bearer TOKEN" http://localhost:8080/status
```

### Review Security Changes

Check applied security patches:
```bash
# VNC binding
grep "address=" /root/.config/wayvnc/config

# GPU permissions
ls -l /dev/dri/

# Service security
systemctl cat waydroid-vnc | grep -A5 "\[Service\]"
```

### Configure Monitoring

If health monitoring was installed:
```bash
# Run health check
/root/waydroid-proxmox/scripts/health-check.sh

# Set up automated checks
crontab -e
# Add: */15 * * * * /root/waydroid-proxmox/scripts/health-check.sh --quiet
```

## Troubleshooting

### Upgrade Fails During Execution

1. **Check the upgrade log**:
   ```bash
   tail -f /var/lib/waydroid-upgrade/upgrade.log
   ```

2. **Review the error**:
   - Look for specific error messages
   - Check service status
   - Verify disk space

3. **Rollback if needed**:
   ```bash
   bash /var/lib/waydroid-upgrade/rollback.sh
   ```

### Services Won't Start After Upgrade

1. **Check service status**:
   ```bash
   systemctl status waydroid-vnc
   journalctl -u waydroid-vnc -n 50
   ```

2. **Reload systemd daemon**:
   ```bash
   systemctl daemon-reload
   ```

3. **Restart services manually**:
   ```bash
   systemctl restart waydroid-container
   systemctl restart waydroid-vnc
   systemctl restart waydroid-api
   ```

### VNC Not Accessible

After upgrade, VNC binds to localhost. This is a security feature.

**Solution**: Use SSH tunnel:
```bash
ssh -L 5900:localhost:5900 root@<container-ip>
```

Then connect your VNC client to `localhost:5900`.

### API Returns Connection Refused

API now binds to localhost. Use SSH tunnel:
```bash
ssh -L 8080:localhost:8080 root@<container-ip>
```

Then access: `http://localhost:8080`

### GPU Permissions Issues

If apps can't access GPU after upgrade:

1. **Check current permissions**:
   ```bash
   ls -l /dev/dri/
   ```

2. **Verify render group**:
   ```bash
   getent group render
   id waydroid  # Should show render group
   ```

3. **Manually fix if needed**:
   ```bash
   chmod 660 /dev/dri/card*
   chmod 660 /dev/dri/renderD*
   chown root:render /dev/dri/*
   ```

### Backup Directory Full

If you have many backups:

```bash
# Clean old backups (keeps last 5)
/root/waydroid-proxmox/scripts/backup-restore.sh clean

# Or manually remove old ones
rm -rf /var/lib/waydroid-upgrade/backup-20*
```

### Features Not Working

If optional features aren't working:

1. **Clipboard Sharing**:
   ```bash
   systemctl status waydroid-clipboard-sync
   journalctl -u waydroid-clipboard-sync -f
   ```

2. **Audio**:
   ```bash
   /root/waydroid-proxmox/scripts/setup-audio.sh --test
   ```

3. **App System**:
   ```bash
   which install-apps
   install-apps --help
   ```

## FAQ

### Q: Will my Android apps and data be affected?

**A:** No. The upgrade process only updates system components and configurations. Your Android apps and data in `/var/lib/waydroid/data` are not touched.

### Q: How long does the upgrade take?

**A:** Typically 5-10 minutes depending on selected features and network speed.

### Q: Can I upgrade without stopping services?

**A:** No. Services must be stopped temporarily to ensure safe configuration updates. They are automatically restarted after the upgrade.

### Q: What if I only want security patches?

**A:** Use the `--security-only` flag:
```bash
bash scripts/upgrade-from-v1.sh --security-only
```

### Q: Can I install features later?

**A:** Yes! You can run the upgrade script again and select different features. It will skip already-applied security patches.

### Q: How do I verify the upgrade was successful?

**A:** Check:
1. Version file: `cat /etc/waydroid-proxmox.version`
2. Services: `systemctl status waydroid-vnc waydroid-api`
3. Upgrade report: `cat /var/lib/waydroid-upgrade/upgrade-report-*.txt`

### Q: What if the upgrade fails?

**A:** The script automatically offers to rollback. You can also manually rollback:
```bash
bash /var/lib/waydroid-upgrade/rollback.sh
```

### Q: Can I run the upgrade multiple times?

**A:** Yes. The script is idempotent - it will skip already-applied changes.

### Q: Why can't I access VNC from outside anymore?

**A:** This is a security improvement. VNC now binds to localhost only. Use SSH tunnel:
```bash
ssh -L 5900:localhost:5900 root@<container-ip>
```

### Q: How do I revert a specific feature?

**A:** Features can be removed individually:
- Clipboard: `systemctl disable waydroid-clipboard-sync && systemctl stop waydroid-clipboard-sync`
- Audio: Remove PulseAudio configuration
- App system: `rm /usr/local/bin/install-apps`

### Q: Is the upgrade reversible?

**A:** Yes, completely. The rollback script restores all configurations and services to their pre-upgrade state.

### Q: What happens to custom configurations?

**A:** Custom configurations are preserved. The upgrade only updates security-sensitive settings and adds new features.

### Q: Can I upgrade from very old versions?

**A:** The minimum supported version is 1.0.0. Use `--force` to bypass version checks, but review the upgrade log carefully.

### Q: Do I need to update Waydroid itself?

**A:** The upgrade script updates the integration layer. Waydroid itself can be updated separately:
```bash
/root/waydroid-proxmox/scripts/update-system.sh --component waydroid
```

## Additional Resources

- **Main Documentation**: `/root/waydroid-proxmox/README.md`
- **Security Improvements**: `/root/waydroid-proxmox/HANDOFF.md`
- **API v3.0 Guide**: `/root/waydroid-proxmox/docs/API_IMPROVEMENTS_v3.0.md`
- **LXC Tuning**: `/root/waydroid-proxmox/docs/LXC_TUNING.md`
- **VNC Enhancements**: `/root/waydroid-proxmox/docs/VNC-ENHANCEMENTS.md`
- **Clipboard Sharing**: `/root/waydroid-proxmox/docs/CLIPBOARD-SHARING.md`
- **App Installation**: `/root/waydroid-proxmox/docs/APP_INSTALLATION.md`

## Support

If you encounter issues:

1. Check the upgrade log: `/var/lib/waydroid-upgrade/upgrade.log`
2. Review the upgrade report: `/var/lib/waydroid-upgrade/upgrade-report-*.txt`
3. Check service logs: `journalctl -u waydroid-vnc -u waydroid-api`
4. Consult troubleshooting section above
5. Open an issue on GitHub with logs attached

## Summary

The v2.0 upgrade brings critical security improvements and powerful new features. The automated upgrade script makes the process safe and reversible. Always review the upgrade report and test functionality after upgrading.

**Recommended Upgrade Path:**
1. Check current version: `--check`
2. Test with dry run: `--dry-run`
3. Run interactive upgrade: (default)
4. Verify services and access
5. Configure new features as needed

Happy upgrading!
