# Waydroid ARM Translation Layer Guide

## Overview

ARM translation layers enable x86_64 systems to run ARM-only Android applications through binary translation. This is essential because many Android apps are compiled exclusively for ARM architectures and won't run natively on Intel/AMD x86_64 processors.

## Supported Translation Layers

### libhoudini (Intel)
- **Source**: Extracted from Windows Subsystem for Android (WSA)
- **Best for**: Intel CPUs
- **Advantages**:
  - Broader app compatibility
  - More stable and battle-tested
  - Better support for complex apps
- **Disadvantages**:
  - Slightly slower on AMD CPUs
  - Larger installation size (~200MB)

### libndk (Google)
- **Source**: Extracted from ChromeOS firmware (guybrush)
- **Best for**: AMD CPUs
- **Advantages**:
  - Better performance on AMD processors
  - Smaller installation size (~150MB)
  - Active development
- **Disadvantages**:
  - Lower app compatibility
  - May have stability issues with some apps
  - Less widely tested

## Quick Start

### 1. Check Status
```bash
sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh status
```

### 2. Install Recommended Layer
The script automatically detects your CPU and recommends the optimal layer:

**For Intel CPUs:**
```bash
sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh install libhoudini
```

**For AMD CPUs:**
```bash
sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh install libndk
```

### 3. Test Installation
```bash
sudo /home/user/waydroid-proxmox/scripts/setup-arm-translation.sh test
```

### 4. Install ARM Apps
After installation, you can install ARM-only APKs:
```bash
waydroid app install /path/to/arm-app.apk
```

## Detailed Usage

### Installation

```bash
# Show help and menu
sudo ./scripts/setup-arm-translation.sh

# Install specific translation layer
sudo ./scripts/setup-arm-translation.sh install libhoudini
sudo ./scripts/setup-arm-translation.sh install libndk

# Force installation without prompts
sudo ./scripts/setup-arm-translation.sh install libhoudini --force
```

### Verification

```bash
# Check current status
sudo ./scripts/setup-arm-translation.sh status

# Test ARM translation
sudo ./scripts/setup-arm-translation.sh test

# Check if specific APK needs translation
sudo ./scripts/setup-arm-translation.sh verify /path/to/app.apk
```

### Maintenance

```bash
# Uninstall current translation layer
sudo ./scripts/setup-arm-translation.sh uninstall

# Restore from backup
sudo ./scripts/setup-arm-translation.sh restore

# View troubleshooting guide
sudo ./scripts/setup-arm-translation.sh troubleshoot
```

### Information

```bash
# Show performance warnings
sudo ./scripts/setup-arm-translation.sh warnings

# Show known limitations
sudo ./scripts/setup-arm-translation.sh limitations

# Show detailed help
sudo ./scripts/setup-arm-translation.sh help
```

## How It Works

### Architecture Translation Process

1. **Binary Translation**: Converts ARM machine code to x86_64 instructions on-the-fly
2. **Native Bridge**: Android's mechanism for loading and executing ARM libraries
3. **ABI Emulation**: Provides ARM Application Binary Interface on x86_64 systems
4. **JNI Handling**: Translates Java Native Interface calls between architectures

### Configuration Changes

The script modifies the following Waydroid configuration:

**File: `/var/lib/waydroid/waydroid.cfg`**
```ini
[properties]
ro.dalvik.vm.native.bridge=libhoudini.so  # or libndk_translation.so
ro.enable.native.bridge.exec=1
ro.dalvik.vm.isa.arm=x86
ro.dalvik.vm.isa.arm64=x86_64
ro.product.cpu.abilist=x86_64,x86,arm64-v8a,armeabi-v7a,armeabi
ro.product.cpu.abilist64=x86_64,arm64-v8a
ro.product.cpu.abilist32=x86,armeabi-v7a,armeabi
```

### Library Installation

Translation layer libraries are installed to:
- `/var/lib/waydroid/rootfs/system/lib/libhoudini.so` (or libndk_translation.so)
- `/var/lib/waydroid/rootfs/system/lib64/libhoudini.so` (or libndk_translation.so)
- Additional ARM-specific directories

## Performance Impact

### Expected Performance Characteristics

| Metric | Impact |
|--------|--------|
| CPU Usage | +30-50% higher |
| Memory Usage | +20-30% higher |
| App Launch Time | +2-5 seconds |
| Overall Speed | 60-80% of native |
| Gaming FPS | 50-70% of native |
| Battery Life | -20-30% reduction |

### Performance Tips

1. **Close Background Apps**: Free up resources for translation overhead
2. **Use Correct Layer**: libhoudini for Intel, libndk for AMD
3. **Monitor Resources**: Use `htop` or system monitor
4. **Prefer Native**: Always use x86_64 APKs when available
5. **Test Before Relying**: Some apps may not work correctly

## Compatibility

### What Works Well

✅ **Generally Compatible:**
- Social media apps (Facebook, Instagram, Twitter)
- Messaging apps (WhatsApp, Telegram)
- Productivity apps (Office, note-taking)
- Media players (VLC, streaming apps)
- Simple games (puzzle, casual games)

### What May Have Issues

⚠️ **Potentially Problematic:**
- High-performance games (3D, action games)
- Apps with DRM protection
- Banking apps with security checks
- Apps using SafetyNet
- Apps with hardware-specific code
- Apps using advanced JNI

### What Won't Work

❌ **Not Compatible:**
- Apps requiring ARM-specific hardware
- Apps with anti-cheat systems
- Some VPN apps
- Apps with kernel-level security
- Hardware-dependent utilities

## Troubleshooting

### ARM Apps Won't Install

**Symptoms**: `INSTALL_FAILED_NO_MATCHING_ABIS` error

**Solutions**:
1. Verify translation layer is installed:
   ```bash
   sudo ./scripts/setup-arm-translation.sh status
   ```

2. Check CPU ABI list:
   ```bash
   waydroid prop get ro.product.cpu.abilist
   ```
   Should include: `arm64-v8a,armeabi-v7a,armeabi`

3. Restart Waydroid:
   ```bash
   waydroid container stop
   waydroid container start
   ```

4. Reinstall translation layer:
   ```bash
   sudo ./scripts/setup-arm-translation.sh install libhoudini
   ```

### ARM Apps Crash on Launch

**Symptoms**: App crashes immediately or shows black screen

**Solutions**:
1. Check logcat for errors:
   ```bash
   waydroid logcat | grep -i "crash\|error\|exception"
   ```

2. Try different translation layer:
   ```bash
   sudo ./scripts/setup-arm-translation.sh uninstall
   sudo ./scripts/setup-arm-translation.sh install libndk
   ```

3. Clear app data:
   ```bash
   waydroid app intent android.settings.APPLICATION_DETAILS_SETTINGS \
     package:com.example.app
   ```

4. Check app compatibility online

### Poor Performance

**Symptoms**: Laggy UI, stuttering, slow response

**Solutions**:
1. Verify only one translation layer installed:
   ```bash
   sudo ./scripts/setup-arm-translation.sh status
   ```

2. Use recommended layer for CPU:
   - Intel → libhoudini
   - AMD → libndk

3. Increase LXC resources:
   ```bash
   # On Proxmox host
   pct set <VMID> -cores 4 -memory 4096
   ```

4. Consider using native x86_64 APK if available

### Installation Fails

**Symptoms**: Script reports installation errors

**Solutions**:
1. Check prerequisites:
   ```bash
   waydroid status  # Should show RUNNING
   df -h  # Check free space (need 2GB+)
   python3 --version  # Need 3.6+
   ```

2. Stop Waydroid completely:
   ```bash
   waydroid container stop
   pkill -9 waydroid
   ```

3. Clean up and retry:
   ```bash
   rm -rf /var/cache/waydroid-arm/waydroid_script
   sudo ./scripts/setup-arm-translation.sh install libhoudini
   ```

4. Check logs:
   ```bash
   tail -f /var/log/waydroid-arm/setup-*.log
   ```

5. Restore from backup if needed:
   ```bash
   sudo ./scripts/setup-arm-translation.sh restore
   ```

### Native Bridge Not Enabled

**Symptoms**: "Native bridge is not enabled" error in logs

**Solutions**:
1. Verify configuration:
   ```bash
   grep native.bridge /var/lib/waydroid/waydroid.cfg
   ```

2. Check native bridge property:
   ```bash
   waydroid prop get ro.dalvik.vm.native.bridge
   ```
   Should show: `libhoudini.so` or `libndk_translation.so`

3. Manually enable if needed:
   ```bash
   waydroid prop set ro.dalvik.vm.native.bridge libhoudini.so
   waydroid prop set ro.enable.native.bridge.exec 1
   ```

4. Restart Waydroid:
   ```bash
   waydroid container stop && waydroid container start
   ```

## Advanced Usage

### Switching Translation Layers

If one layer doesn't work well for an app, try the other:

```bash
# Switch from libhoudini to libndk
sudo ./scripts/setup-arm-translation.sh uninstall libhoudini
sudo ./scripts/setup-arm-translation.sh install libndk

# Switch from libndk to libhoudini
sudo ./scripts/setup-arm-translation.sh uninstall libndk
sudo ./scripts/setup-arm-translation.sh install libhoudini
```

**Important**: Only one translation layer can be installed at a time!

### Checking APK Architecture

Before installing an APK, check if it needs translation:

```bash
sudo ./scripts/setup-arm-translation.sh verify /path/to/app.apk
```

Output example:
```
[INFO] Analyzing APK architecture: /path/to/app.apk
native-code: 'armeabi-v7a' 'arm64-v8a'
[WARN] APK contains ARM native libraries
Translation layer: REQUIRED for x86_64 systems
```

### Manual Configuration

For advanced users who want to configure manually:

1. **Edit waydroid.cfg**:
   ```bash
   nano /var/lib/waydroid/waydroid.cfg
   ```

2. **Add properties** in `[properties]` section:
   ```ini
   ro.dalvik.vm.native.bridge=libhoudini.so
   ro.enable.native.bridge.exec=1
   ro.dalvik.vm.isa.arm=x86
   ro.dalvik.vm.isa.arm64=x86_64
   ro.product.cpu.abilist=x86_64,x86,arm64-v8a,armeabi-v7a,armeabi
   ```

3. **Restart Waydroid**:
   ```bash
   waydroid container stop && waydroid container start
   ```

### Backup and Restore

The script automatically creates backups before making changes:

**Backup location**: `/var/cache/waydroid-arm/backup/`

**Manual backup**:
```bash
cp /var/lib/waydroid/waydroid.cfg \
   /var/cache/waydroid-arm/backup/waydroid.cfg.backup
```

**Restore from backup**:
```bash
sudo ./scripts/setup-arm-translation.sh restore
```

## System Requirements

### Minimum Requirements
- x86_64 processor (Intel or AMD)
- 2GB free disk space
- Waydroid installed and initialized
- Python 3.6 or higher
- Git
- Root/sudo access

### Recommended Requirements
- Modern x86_64 processor (2015+)
- 4GB RAM for LXC container
- 4+ CPU cores
- SSD storage for better performance

### Software Dependencies
Automatically installed by script:
- python3-venv
- python3-pip
- git
- curl
- aapt (for APK analysis)

## Known Limitations

### Architecture Limitations
- Cannot install both libhoudini and libndk simultaneously
- ARM apps run 20-40% slower than native x86_64 apps
- Some ARM-specific optimizations don't work
- Mixed-architecture APKs may have issues

### App Compatibility
- Apps with SafetyNet checks may fail
- Banking apps with strong security may not work
- Games with anti-cheat systems may be blocked
- DRM-protected content may not play
- Apps using ARM-specific hardware features will fail

### Performance Characteristics
- 20-40% performance overhead from translation
- Higher battery/power consumption
- Increased memory usage
- Cache generation causes initial slowdown
- Some JIT compilation benefits lost

### Gaming Limitations
- Reduced FPS in demanding games
- Graphics may lag or stutter
- Online games may have latency issues
- Shader compilation may be slower
- Some games may crash or freeze

## Best Practices

### 1. Prefer Native Apps
Always look for x86_64 versions first:
- Check F-Droid for native builds
- Look on APKMirror for multiple architectures
- Use web apps as alternatives
- Consider Progressive Web Apps (PWAs)

### 2. Test Before Production
- Test apps thoroughly before relying on them
- Have backup solutions ready
- Monitor performance metrics
- Keep logs for troubleshooting

### 3. Resource Management
- Monitor CPU and memory usage
- Close unnecessary background apps
- Allocate sufficient LXC resources
- Use performance monitoring tools

### 4. Updates and Maintenance
- Keep Waydroid updated
- Monitor translation layer compatibility
- Backup before making changes
- Check logs regularly

### 5. Security Considerations
- Translation may bypass some security features
- Banking apps may detect emulation
- Keep system patches current
- Use trusted APK sources only

## Resources

### Official Documentation
- [Waydroid Documentation](https://docs.waydro.id/)
- [Waydroid GitHub](https://github.com/waydroid/waydroid)
- [casualsnek/waydroid_script](https://github.com/casualsnek/waydroid_script)

### Community Resources
- [Waydroid Subreddit](https://reddit.com/r/waydroid)
- [XDA Developers Forum](https://forum.xda-developers.com/)
- [Arch Wiki - Waydroid](https://wiki.archlinux.org/title/Waydroid)

### Related Projects
- [sickcodes/droid-native](https://github.com/sickcodes/droid-native)
- [Droid-NDK-Extractor](https://github.com/sickcodes/Droid-NDK-Extractor)
- [Anbox](https://anbox.io/) (alternative to Waydroid)

## Frequently Asked Questions

### Q: Do I need ARM translation?
**A**: Only if you want to run ARM-only Android apps on an x86_64 system. Check the app's architecture first using the `verify` command.

### Q: Which translation layer should I choose?
**A**: Use libhoudini for Intel CPUs (better compatibility) or libndk for AMD CPUs (better performance). The script recommends based on your CPU.

### Q: Can I install both translation layers?
**A**: No, only one translation layer can be installed at a time. Installing both causes conflicts.

### Q: Will all ARM apps work?
**A**: No. Most simple apps work, but apps with DRM, anti-cheat, or hardware-specific code may fail.

### Q: How much slower are ARM apps?
**A**: Expect 20-40% performance reduction compared to native x86_64 apps due to translation overhead.

### Q: Can I play games with ARM translation?
**A**: Simple games work, but demanding 3D games will have reduced FPS and may stutter. Native x86_64 games are strongly recommended.

### Q: Is ARM translation legal?
**A**: The translation layers are extracted from publicly available sources (WSA, ChromeOS) and used for compatibility purposes. However, check your local laws and app licenses.

### Q: How do I uninstall?
**A**: Run `sudo ./scripts/setup-arm-translation.sh uninstall`

### Q: Where are backups stored?
**A**: In `/var/cache/waydroid-arm/backup/` - the script creates automatic backups before changes.

### Q: Can I use this on ARM hardware?
**A**: No, ARM translation is for x86_64 systems only. ARM hardware doesn't need translation.

## Changelog

### Version 1.0.0 (2025-11-12)
- Initial release
- Support for libhoudini and libndk
- Automatic CPU detection and recommendation
- Comprehensive verification and testing
- Automatic backup and restore
- Detailed troubleshooting guides
- APK architecture analysis
- Performance warnings and limitations
- Integration with waydroid_script

## License

This script uses the casualsnek/waydroid_script tool which is open source. The translation layers (libhoudini and libndk) are extracted from their respective sources (Windows Subsystem for Android and ChromeOS firmware).

## Support

For issues and questions:
1. Check the troubleshooting section above
2. Review logs in `/var/log/waydroid-arm/`
3. Open an issue on the repository
4. Consult Waydroid documentation and community

---

**Note**: ARM translation is a compatibility feature with performance trade-offs. Always prefer native x86_64 applications when available for the best experience.
