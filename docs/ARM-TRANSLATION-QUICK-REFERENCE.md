# ARM Translation Quick Reference

Quick reference guide for using ARM translation with Waydroid.

## Quick Commands

```bash
# Check current status
sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh status

# Install (automatic detection)
sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh install $(detect_recommended)

# Install libhoudini (Intel CPUs)
sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh install libhoudini

# Install libndk (AMD CPUs)
sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh install libndk

# Test installation
sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh test

# Verify APK needs translation
sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh verify /path/to/app.apk

# Uninstall
sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh uninstall

# Restore from backup
sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh restore
```

## One-Liner Installation

**Intel CPU:**
```bash
sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh install libhoudini && \
sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh test
```

**AMD CPU:**
```bash
sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh install libndk && \
sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh test
```

## When to Use ARM Translation

### You NEED ARM translation if:
- APK shows: `native-code: 'armeabi-v7a' 'arm64-v8a'`
- App won't install: `INSTALL_FAILED_NO_MATCHING_ABIS`
- App is ARM-only (check with verify command)

### You DON'T NEED ARM translation if:
- APK shows: `native-code: 'x86' 'x86_64'`
- APK has no native-code (Java/Kotlin only)
- App already works without translation

## Common Workflows

### Installing ARM App

```bash
# 1. Check if app needs translation
sudo ./scripts/setup-arm-translation.sh verify ~/Downloads/app.apk

# 2. If needed, install translation layer
sudo ./scripts/setup-arm-translation.sh install libhoudini

# 3. Install the app
waydroid app install ~/Downloads/app.apk

# 4. Launch and test
waydroid show-full-ui
```

### Switching Translation Layers

```bash
# From libhoudini to libndk
sudo ./scripts/setup-arm-translation.sh uninstall libhoudini
sudo ./scripts/setup-arm-translation.sh install libndk

# From libndk to libhoudini
sudo ./scripts/setup-arm-translation.sh uninstall libndk
sudo ./scripts/setup-arm-translation.sh install libhoudini
```

### Troubleshooting Workflow

```bash
# 1. Check status
sudo ./scripts/setup-arm-translation.sh status

# 2. View logs
tail -f /var/log/waydroid-arm/setup-*.log

# 3. Check Waydroid logs
waydroid logcat | grep -i native.bridge

# 4. Restart Waydroid
waydroid container stop
waydroid container start

# 5. If still broken, restore
sudo ./scripts/setup-arm-translation.sh restore
```

## Decision Tree

```
Is your CPU Intel or AMD?
├─ Intel → Use libhoudini
└─ AMD → Use libndk

Does the app need ARM translation?
├─ Yes → Install translation layer
└─ No → Install app directly

Is the app not working?
├─ Crashes → Try other translation layer
├─ Won't install → Check translation installed
└─ Slow → This is normal (20-40% overhead)
```

## Key Files

```
Configuration:
  /var/lib/waydroid/waydroid.cfg    - Main config
  /var/lib/waydroid/waydroid.prop   - Runtime properties

Libraries:
  /var/lib/waydroid/rootfs/system/lib64/libhoudini.so
  /var/lib/waydroid/rootfs/system/lib64/libndk_translation.so

Logs & Cache:
  /var/log/waydroid-arm/            - Installation logs
  /var/cache/waydroid-arm/          - Downloads & cache
  /var/cache/waydroid-arm/backup/   - Configuration backups
```

## Important Properties

```ini
# Check with: grep native.bridge /var/lib/waydroid/waydroid.cfg

ro.dalvik.vm.native.bridge=libhoudini.so  # or libndk_translation.so
ro.enable.native.bridge.exec=1
ro.dalvik.vm.isa.arm=x86
ro.dalvik.vm.isa.arm64=x86_64
ro.product.cpu.abilist=x86_64,x86,arm64-v8a,armeabi-v7a,armeabi
```

## Performance Quick Tips

```bash
# 1. Use correct layer for CPU
Intel → libhoudini
AMD → libndk

# 2. Close background apps
waydroid app intent android.settings.SETTINGS

# 3. Increase LXC resources (on Proxmox host)
pct set <VMID> -cores 4 -memory 4096

# 4. Monitor performance
htop
```

## Common Errors & Fixes

### Error: `INSTALL_FAILED_NO_MATCHING_ABIS`
```bash
# Install translation layer
sudo ./scripts/setup-arm-translation.sh install libhoudini
waydroid container stop && waydroid container start
```

### Error: `Native bridge not enabled`
```bash
# Verify installation
sudo ./scripts/setup-arm-translation.sh status
# Reinstall if needed
sudo ./scripts/setup-arm-translation.sh install libhoudini
```

### Error: App crashes on launch
```bash
# Try other translation layer
sudo ./scripts/setup-arm-translation.sh uninstall
sudo ./scripts/setup-arm-translation.sh install libndk
```

### Error: Very poor performance
```bash
# Verify only one layer installed
sudo ./scripts/setup-arm-translation.sh status
# Look for native x86_64 version instead
```

## Comparison Table

| Feature | libhoudini | libndk |
|---------|-----------|--------|
| **Best for** | Intel CPUs | AMD CPUs |
| **Compatibility** | ⭐⭐⭐⭐⭐ Excellent | ⭐⭐⭐ Good |
| **Performance** | ⭐⭐⭐⭐ Very Good | ⭐⭐⭐⭐⭐ Excellent (AMD) |
| **Stability** | ⭐⭐⭐⭐⭐ Very Stable | ⭐⭐⭐ Stable |
| **Size** | ~200 MB | ~150 MB |
| **Source** | WSA 11 | ChromeOS |

## Links

- **Full Documentation**: `/home/user/waydroid-proxmox/docs/ARM-TRANSLATION.md`
- **Script Location**: `/home/user/waydroid-proxmox/scripts/setup-arm-translation.sh`
- **Waydroid Docs**: https://docs.waydro.id/
- **waydroid_script**: https://github.com/casualsnek/waydroid_script

---

**Remember**: ARM translation adds 20-40% performance overhead. Always prefer native x86_64 apps when available!
