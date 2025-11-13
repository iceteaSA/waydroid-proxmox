# Android App Installation Guide

Comprehensive guide for installing and managing Android apps in Waydroid using the automated installation script.

## Overview

The `install-apps.sh` script provides a production-ready solution for managing Android applications in your Waydroid environment with:

- **Multiple Installation Sources**: Local APK files, direct URLs, and F-Droid repository
- **Batch Installation**: Install multiple apps from YAML or JSON configuration files
- **Security**: APK verification, signature checking, and hash validation
- **Reliability**: Progress tracking, comprehensive logging, and rollback capability
- **Maintenance**: Update checking for installed applications

## Quick Start

### Install a Single App

```bash
# From local APK file
/home/user/waydroid-proxmox/scripts/install-apps.sh install-apk /path/to/app.apk

# From URL
/home/user/waydroid-proxmox/scripts/install-apps.sh install-apk https://example.com/app.apk

# From F-Droid
/home/user/waydroid-proxmox/scripts/install-apps.sh install-fdroid org.fdroid.fdroid
```

### Batch Installation

```bash
# Create your app configuration
cp /home/user/waydroid-proxmox/config/apps-example.yaml /home/user/waydroid-proxmox/config/my-apps.yaml

# Edit the configuration
nano /home/user/waydroid-proxmox/config/my-apps.yaml

# Install all apps from config
/home/user/waydroid-proxmox/scripts/install-apps.sh install-batch /home/user/waydroid-proxmox/config/my-apps.yaml
```

## Features

### 1. Multiple Installation Sources

#### Local APK Files
Install APKs stored on your filesystem:
```bash
install-apps.sh install-apk /path/to/myapp.apk
```

#### Direct URLs
Download and install APKs from URLs:
```bash
install-apps.sh install-apk https://github.com/user/repo/releases/download/v1.0/app.apk
```

#### F-Droid Repository
Install apps directly from F-Droid with automatic hash verification:
```bash
# Search for apps
install-apps.sh search-fdroid "firefox"

# Install by package name
install-apps.sh install-fdroid org.mozilla.fennec_fdroid
```

### 2. Batch Installation

Create a configuration file in YAML or JSON format to install multiple apps at once.

#### YAML Example
```yaml
apps:
  local:
    - /home/user/Downloads/app1.apk
    - /home/user/Downloads/app2.apk

  url:
    - https://example.com/apps/app3.apk

  fdroid:
    - org.fdroid.fdroid
    - org.mozilla.fennec_fdroid
    - org.torproject.android
    - com.termux
```

#### JSON Example
```json
{
  "apps": {
    "local": [
      "/home/user/Downloads/app1.apk"
    ],
    "url": [
      "https://example.com/apps/app3.apk"
    ],
    "fdroid": [
      "org.fdroid.fdroid",
      "org.mozilla.fennec_fdroid"
    ]
  }
}
```

### 3. APK Verification

The script automatically verifies APKs before installation:

- **File integrity**: Checks file size and ZIP structure
- **Manifest validation**: Ensures AndroidManifest.xml exists
- **Signature verification**: Validates APK signatures (if aapt is available)
- **Hash checking**: Verifies SHA256 hashes for F-Droid apps

Manual verification:
```bash
install-apps.sh verify /path/to/app.apk
```

Skip verification (not recommended):
```bash
install-apps.sh install-apk /path/to/app.apk --skip-verify
```

### 4. Progress Tracking and Logging

All installations are logged to `/var/log/waydroid-apps/`:

```bash
# View latest log
tail -f /var/log/waydroid-apps/install-*.log

# View all logs
ls -lh /var/log/waydroid-apps/
```

Each log includes:
- Timestamp for each operation
- Download progress (with progress bar)
- Verification results
- Installation status
- Error messages and stack traces

### 5. Rollback Capability

If a batch installation fails or you need to undo changes:

```bash
# Rollback the last batch installation
install-apps.sh rollback
```

Rollback features:
- Saves system state before batch installations
- Records all installed packages with timestamps
- Allows complete reversal of the last batch installation
- Preserves rollback states for audit trail

### 6. Update Checking

Check for available updates from F-Droid:

```bash
install-apps.sh check-updates
```

This will:
1. Update the F-Droid repository index
2. Compare installed versions with latest F-Droid versions
3. Display available updates

## Command Reference

### Commands

| Command | Description |
|---------|-------------|
| `install-apk <file\|url>` | Install APK from local file or URL |
| `install-fdroid <package>` | Install app from F-Droid repository |
| `install-batch <config>` | Install apps from YAML/JSON config file |
| `list-installed` | List all installed Android apps |
| `check-updates` | Check for updates of installed apps |
| `rollback` | Rollback last batch installation |
| `verify <apk>` | Verify APK signature and integrity |
| `search-fdroid <query>` | Search F-Droid repository |

### Options

| Option | Description |
|--------|-------------|
| `--skip-verify` | Skip signature verification (not recommended) |
| `--force` | Force installation over existing app without prompting |
| `--no-rollback` | Don't create rollback point |
| `--help` | Show help message |

## Configuration Files

### Directory Structure

```
/home/user/waydroid-proxmox/
├── config/
│   ├── apps-example.yaml    # YAML example configuration
│   ├── apps-example.json    # JSON example configuration
│   └── my-apps.yaml         # Your custom configuration
├── scripts/
│   └── install-apps.sh      # Main installation script
└── /var/
    ├── cache/waydroid-apps/     # Downloaded APKs and F-Droid index
    └── log/waydroid-apps/       # Installation logs
```

### YAML Configuration Format

```yaml
apps:
  # Local APK files
  local:
    - /absolute/path/to/app1.apk
    - /absolute/path/to/app2.apk

  # Direct download URLs
  url:
    - https://example.com/app1.apk
    - https://github.com/user/repo/releases/download/v1.0/app.apk

  # F-Droid packages
  fdroid:
    - org.fdroid.fdroid          # Package name
    - org.mozilla.fennec_fdroid

    # Alternative syntax for mixed sources
    - path: /path/to/local.apk   # Local file
    - url: https://example.com/app.apk  # URL
```

### JSON Configuration Format

```json
{
  "apps": {
    "local": [
      "/absolute/path/to/app1.apk",
      "/absolute/path/to/app2.apk"
    ],
    "url": [
      "https://example.com/app1.apk"
    ],
    "fdroid": [
      "org.fdroid.fdroid",
      "org.mozilla.fennec_fdroid",
      {"path": "/path/to/local.apk"},
      {"url": "https://example.com/app.apk"}
    ]
  }
}
```

## Popular Apps

### Essential Apps

```yaml
apps:
  fdroid:
    # F-Droid client
    - org.fdroid.fdroid

    # Web browsers
    - org.mozilla.fennec_fdroid  # Firefox
    - org.torproject.torbrowser_alpha  # Tor Browser

    # Terminal
    - com.termux

    # VPN
    - org.torproject.android
```

### Privacy-Focused Apps

```yaml
apps:
  fdroid:
    - org.thoughtcrime.securesms  # Signal
    - org.briarproject.briar.android  # Briar
    - net.osmand.plus  # OSMand Maps
    - im.vector.app  # Element (Matrix)
```

### Productivity Apps

```yaml
apps:
  fdroid:
    - com.orgzly  # Org mode notes
    - net.gsantner.markor  # Markdown editor
    - org.tasks  # Task manager
    - com.simplemobiletools.calendar.pro  # Calendar
    - com.ichi2.anki  # Flashcards
```

### Media Apps

```yaml
apps:
  fdroid:
    - org.schabi.newpipe  # YouTube client
    - org.videolan.vlc  # VLC Media Player
    - com.github.libretube  # LibreTube
    - org.libre.tuner  # Music tuner
```

## Advanced Usage

### Force Installation

Override existing apps without prompting:
```bash
install-apps.sh install-apk /path/to/app.apk --force
```

### Skip Verification

Install APKs without verification (not recommended for untrusted sources):
```bash
install-apps.sh install-apk /path/to/app.apk --skip-verify
```

### Combined Options

```bash
install-apps.sh install-batch my-apps.yaml --force --skip-verify
```

### Custom Cache Directory

```bash
export APP_CACHE_DIR=/custom/cache/path
install-apps.sh install-fdroid org.fdroid.fdroid
```

### Custom F-Droid Repository

```bash
export FDROID_REPO=https://custom-repo.example.com/repo
install-apps.sh install-fdroid com.example.app
```

## Troubleshooting

### Waydroid Not Running

**Error**: "Waydroid container is not running"

**Solution**:
```bash
# Start Waydroid container
waydroid container start

# Verify status
waydroid status

# Try installation again
install-apps.sh install-apk /path/to/app.apk
```

### APK Verification Failed

**Error**: "APK verification failed" or "APK file is corrupted"

**Solutions**:
1. Re-download the APK
2. Verify the source is trustworthy
3. Check the APK manually: `unzip -t /path/to/app.apk`
4. Use `--skip-verify` only if you trust the source

### Download Failed

**Error**: "Failed to download after 3 attempts"

**Solutions**:
1. Check network connectivity
2. Verify the URL is accessible
3. Try downloading manually: `curl -LO <url>`
4. Check firewall/proxy settings
5. Increase timeout: `export DOWNLOAD_TIMEOUT=600`

### Package Already Installed

**Error**: "Package already installed"

**Solutions**:
1. Use `--force` flag to overwrite
2. Uninstall first: `waydroid app uninstall <package>`
3. Check version: `install-apps.sh list-installed`

### F-Droid Package Not Found

**Error**: "Package not found in F-Droid"

**Solutions**:
1. Search for the correct package name:
   ```bash
   install-apps.sh search-fdroid "app name"
   ```
2. Update F-Droid index:
   ```bash
   rm -f /var/cache/waydroid-apps/fdroid-index.json
   install-apps.sh search-fdroid "dummy"
   ```
3. Check package name on https://f-droid.org

### Permission Denied

**Error**: "Permission denied" when accessing logs or cache

**Solution**:
```bash
# Create directories with proper permissions
sudo mkdir -p /var/cache/waydroid-apps /var/log/waydroid-apps
sudo chmod 755 /var/cache/waydroid-apps /var/log/waydroid-apps

# Or run as root
sudo install-apps.sh install-apk /path/to/app.apk
```

### Batch Installation Partial Failure

**Error**: Some apps installed, some failed

**Solution**:
1. Check the log file for specific errors:
   ```bash
   tail -100 /var/log/waydroid-apps/install-*.log
   ```
2. Fix issues with failed apps
3. Re-run with `--force` to skip successful apps
4. Or rollback and try again:
   ```bash
   install-apps.sh rollback
   ```

## Best Practices

### Security

1. **Verify APKs**: Always verify APKs from untrusted sources
   ```bash
   install-apps.sh verify /path/to/app.apk
   ```

2. **Use F-Droid**: Prefer F-Droid for open-source apps (automatic signature verification)

3. **Check signatures**: For non-F-Droid APKs, verify the signature matches the developer's published signature

4. **Avoid unknown sources**: Only download APKs from official websites or trusted repositories

### Performance

1. **Batch installations**: Use batch configuration for multiple apps instead of installing one-by-one

2. **Cache management**: Clean old cached APKs periodically:
   ```bash
   find /var/cache/waydroid-apps -name "*.apk" -mtime +30 -delete
   ```

3. **Log rotation**: Set up log rotation for `/var/log/waydroid-apps/`

### Maintenance

1. **Regular updates**: Check for updates weekly:
   ```bash
   install-apps.sh check-updates
   ```

2. **Backup before major changes**: Create a Waydroid backup before batch installations:
   ```bash
   /home/user/waydroid-proxmox/scripts/backup-restore.sh backup
   ```

3. **Test rollback**: Test the rollback functionality periodically to ensure it works

4. **Document custom apps**: Maintain your configuration file with comments explaining each app

### Configuration Management

1. **Version control**: Keep your app configuration in git:
   ```bash
   cd /home/user/waydroid-proxmox
   git add config/my-apps.yaml
   git commit -m "Add/update app configuration"
   ```

2. **Multiple configurations**: Create different configs for different purposes:
   - `apps-minimal.yaml` - Essential apps only
   - `apps-full.yaml` - Complete app suite
   - `apps-dev.yaml` - Development tools

3. **Environment-specific configs**: Use different configs for different environments:
   - `apps-production.yaml`
   - `apps-testing.yaml`
   - `apps-development.yaml`

## Integration Examples

### Automated Installation on Container Creation

Add to your container setup script:
```bash
#!/bin/bash
# Wait for Waydroid to be ready
waydroid container start
sleep 10

# Install apps from configuration
/home/user/waydroid-proxmox/scripts/install-apps.sh install-batch \
    /home/user/waydroid-proxmox/config/apps-production.yaml
```

### CI/CD Integration

```yaml
# .gitlab-ci.yml or similar
deploy:
  script:
    - scp config/apps.yaml lxc-host:/tmp/
    - ssh lxc-host "pct push 100 /tmp/apps.yaml /root/apps.yaml"
    - ssh lxc-host "pct exec 100 -- /root/scripts/install-apps.sh install-batch /root/apps.yaml"
```

### Scheduled Updates

Create a cron job to check and report updates:
```bash
# Add to crontab: crontab -e
0 0 * * 0 /home/user/waydroid-proxmox/scripts/install-apps.sh check-updates | mail -s "Waydroid App Updates" admin@example.com
```

## Dependencies

### Required

- **Waydroid**: Must be installed and running
- **curl**: For downloading APKs from URLs
- **unzip**: For APK verification
- **bash**: Version 4.0 or later

### Optional

- **jq**: Required for F-Droid installation and JSON config parsing
  ```bash
  apt-get install jq
  ```

- **aapt**: Android Asset Packaging Tool for better APK verification
  ```bash
  apt-get install aapt
  ```

- **sha256sum**: For hash verification (usually pre-installed)

### Installation

Install all dependencies:
```bash
apt-get update
apt-get install -y curl unzip jq aapt
```

## Troubleshooting Logs

### View Real-time Installation

```bash
tail -f /var/log/waydroid-apps/install-$(date +%Y%m%d)-*.log
```

### Search for Errors

```bash
grep -i error /var/log/waydroid-apps/*.log
```

### Check Specific App Installation

```bash
grep "package-name" /var/log/waydroid-apps/*.log
```

### View Rollback History

```bash
ls -lh /var/cache/waydroid-apps/rollback/
cat /var/cache/waydroid-apps/rollback/state-*.json
```

## Support and Contributing

### Getting Help

1. Check the troubleshooting section above
2. Review logs: `/var/log/waydroid-apps/`
3. Test Waydroid status: `waydroid status`
4. Verify APK manually: `install-apps.sh verify /path/to/app.apk`

### Reporting Issues

When reporting issues, include:
- Command used
- Full error message
- Relevant log excerpt from `/var/log/waydroid-apps/`
- Waydroid version: `waydroid --version`
- System information: `uname -a`

### Contributing

Contributions are welcome! Areas for improvement:
- Additional app sources (Aurora Store, APKMirror)
- Parallel installations
- GUI wrapper
- Automatic update installation
- Enhanced verification methods

## License

This script is part of the waydroid-proxmox project.
See the main LICENSE file for details.
