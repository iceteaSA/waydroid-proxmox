# WayVNC Authentication Investigation

## Current Problem

**Symptom:** VNC clients get "No matching security types" error when connecting
**WayVNC Version:** 0.5.0
**Container:** Proxmox LXC 103 (IP: 10.1.3.136)
**Command:** `wayvnc -C /home/waydroid/.config/wayvnc/config`
**Log Status:** `/var/log/waydroid-wayvnc.log` is COMPLETELY EMPTY

## Investigation Tasks

### 1. Read Actual Config File
**Location:** `/home/waydroid/.config/wayvnc/config`
**Expected Content:**
```
address=0.0.0.0
port=5900
enable_auth=false
```

**Status:** Need to verify actual content

### 2. Check if WayVNC is Reading the Config
**Method:** Run with verbose flag: `wayvnc -C /home/waydroid/.config/wayvnc/config -v`
**Goal:** See if config is being parsed and what settings are applied

### 3. Research WayVNC 0.5.0 Configuration Options

#### Known Facts:
- WayVNC 0.5.0 is an OLDER version (current is 0.9+)
- Based on HANDOVER.md: "WayVNC 0.5.0 in container doesn't support these config options:"
  - `enable_auth=true`
  - `username=waydroid`
  - `password_file=/home/waydroid/.config/wayvnc/password`
  - `max_rate=60`

#### Configuration Format:
WayVNC uses INI-style configuration files. Locations checked (in order):
1. Path specified with `-C` flag
2. `$XDG_CONFIG_HOME/wayvnc/config`
3. `$HOME/.config/wayvnc/config`
4. `/etc/wayvnc/config`

#### Authentication in WayVNC 0.5.0:

**Question:** Does WayVNC 0.5.0 even support `enable_auth=false`?

The "No matching security types" error typically means:
- Client offers: VncAuth, Tight, etc.
- Server offers: ONLY something incompatible (or requires encryption)

**Possible Causes:**
1. WayVNC 0.5.0 might REQUIRE authentication by default with no way to disable it
2. The `-C` flag might not work in 0.5.0
3. Config syntax might be different in 0.5.0
4. WayVNC might require TLS and only offer secure security types

### 4. Check for Multiple Config Files

WayVNC might be reading a different config file:
- `/home/waydroid/.config/wayvnc/config` (intended)
- `/root/.config/wayvnc/config` (if running as root initially)
- `/etc/wayvnc/config` (system-wide)

### 5. File Permissions

Check if the waydroid user can actually read the config:
```bash
ls -la /home/waydroid/.config/wayvnc/config
```

Expected: `-rw-r--r-- waydroid:waydroid`

### 6. Why is Log File Empty?

The startup script likely redirects stderr/stdout to the log file:
```bash
wayvnc ... > /var/log/waydroid-wayvnc.log 2>&1
```

**If log is empty, possibilities:**
1. WayVNC is not actually running (exits immediately)
2. Output is being redirected elsewhere
3. WayVNC is running but producing no output
4. File permissions prevent writing

### 7. WayVNC Command-Line Options

From `wayvnc --help`, we need to check:
- Does `-C` flag exist in 0.5.0?
- What other auth-related flags exist?
- Can auth be disabled via command line? (e.g., `--disable-auth`)

**Common WayVNC options:**
- `-a, --address <address>` - Bind address (default: 0.0.0.0)
- `-p, --port <port>` - Port number (default: 5900)
- `-C, --config <path>` - Config file path
- `-v, --verbose` - Verbose logging

**In older versions, authentication options might be:**
- No auth by default (just connects)
- Or ALWAYS requires auth with no disable option

### 8. Security Types in VNC

**VNC Security Types:**
- 1 = None (no authentication)
- 2 = VNC Authentication (password)
- 5-19 = Various (Tight, VeNCrypt, etc.)

"No matching security types" means the server is not offering Type 1 (None).

**This means WayVNC IS requiring authentication**, regardless of config.

## Hypothesis

**Primary Hypothesis:**
WayVNC 0.5.0 does NOT support the `enable_auth=false` configuration option. This option may have been added in a later version (0.6+).

**Evidence:**
1. HANDOVER.md states 0.5.0 "doesn't support" several config options
2. The error "No matching security types" indicates server requires auth
3. Config file changes have no effect

**Test:**
Run `wayvnc 0.0.0.0 5900` WITHOUT any config file or flags, and see if it requires auth. If it does, then 0.5.0 might simply not support no-auth mode.

## Solutions to Try

### Solution 1: Use Password Authentication
Instead of trying to disable auth, SET a password:

```bash
# Create password file
pct exec 103 -- bash -c 'echo "mypassword" | wayvncctl auth create /home/waydroid/.config/wayvnc/password'
```

Then update config to use it (if supported):
```ini
address=0.0.0.0
port=5900
password_file=/home/waydroid/.config/wayvnc/password
```

### Solution 2: Upgrade WayVNC
If 0.5.0 doesn't support no-auth, upgrade to 0.8.0+ which definitely supports it.

```bash
pct exec 103 -- bash <<'EOF'
# Download newer WayVNC (example - adjust URL for actual version)
wget https://github.com/any1/wayvnc/releases/download/v0.8.0/wayvnc-v0.8.0-linux-x86_64.tar.gz
tar xzf wayvnc-v0.8.0-linux-x86_64.tar.gz
cp wayvnc /usr/local/bin/
EOF
```

### Solution 3: Use neatvnc's Built-in Auth Bypass
WayVNC uses libneatvnc. Check if there's an environment variable to disable auth:

```bash
# Try with environment variable (if it exists)
NEATVNC_AUTH_NONE=1 wayvnc 0.0.0.0 5900
```

### Solution 4: Compile WayVNC from Source with Auth Disabled
If all else fails, compile a custom version with authentication code removed or disabled at compile-time.

## Expected Investigation Output

After running `investigate-wayvnc-auth.sh`, we should see:

1. **Actual config content** - Verify what's really in the file
2. **WayVNC verbose output** - Shows what config options are being parsed
3. **Supported flags** - From `--help`, see if `-C` and auth options exist
4. **Process command line** - What command is actually running
5. **Binary strings** - Check if "enable_auth" is even in the binary (if not, option doesn't exist)

## Next Steps After Investigation

1. **If `enable_auth=false` is not in binary strings:** Option doesn't exist in 0.5.0 - need to upgrade or use password
2. **If WayVNC shows "Unknown option: enable_auth":** Same as above
3. **If WayVNC parses config but still requires auth:** Bug or different syntax needed
4. **If `-C` flag doesn't exist:** Config file approach won't work - must use command-line args only
5. **If log file is empty due to immediate exit:** WayVNC is crashing on startup - check core dumps or run in foreground

## Key Questions to Answer

1. Does WayVNC 0.5.0 support `enable_auth=false` configuration option?
2. Does WayVNC 0.5.0 support the `-C` (config file) flag?
3. What security types does WayVNC 0.5.0 offer by default?
4. Is there ANY way to disable authentication in WayVNC 0.5.0?
5. Why is the log file empty - is WayVNC crashing or just not producing output?

## References

- WayVNC GitHub: https://github.com/any1/wayvnc
- Current version: 0.9.x (as of 2024)
- Container has: 0.5.0 (released ~2021-2022)
- Significant changes between versions likely

---

**Investigation script created:** `/home/user/waydroid-proxmox/investigate-wayvnc-auth.sh`

Run with: `./investigate-wayvnc-auth.sh`
