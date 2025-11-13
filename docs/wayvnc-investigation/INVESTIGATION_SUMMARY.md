# WayVNC Authentication Investigation - Executive Summary

## Problem Statement

**Current Issue:** VNC clients receive "No matching security types" error when connecting to WayVNC on container 103
**WayVNC Version:** 0.5.0 (circa 2021-2022)
**Current Command:** `wayvnc -C /home/waydroid/.config/wayvnc/config`
**Log File Status:** `/var/log/waydroid-wayvnc.log` is COMPLETELY EMPTY (0 bytes)

## What "No Matching Security Types" Means

This is a standard VNC protocol error that occurs during the security handshake:

1. VNC client connects and requests available security types
2. Server responds with list of supported security types
3. Client compares its supported types with server's list
4. If no common security type exists, client shows this error

**VNC Security Types:**
- Type 1 = None (no authentication required)
- Type 2 = VNC Authentication (password required)
- Types 5+ = Various advanced auth methods

**The error indicates:** Server is NOT offering Type 1 (None), meaning authentication IS required.

## Recent Fix Attempts (from git history)

### Latest Fix (Commit ec7cfd5 - Nov 13, 2025)
**Script:** `/home/user/waydroid-proxmox/fix-wayvnc-final.sh`

**Changes Made:**
1. Created config file at `/home/waydroid/.config/wayvnc/config` with:
   ```ini
   address=0.0.0.0
   port=5900
   enable_auth=false
   ```

2. Modified startup script to use: `wayvnc -C /home/waydroid/.config/wayvnc/config`

**Assumption:** "WayVNC 0.5.0 built without auth support" (per commit message)

**Result:** Still not working - clients still get authentication error

## Critical Questions That Need Answers

### 1. Does WayVNC 0.5.0 Support `enable_auth=false`?

**Investigation needed:**
- Check `wayvnc --help` output for supported config options
- Run `strings /bin/wayvnc | grep enable_auth` to see if option exists in binary
- Run with verbose flag to see if config is being parsed

**If NOT supported:** This would explain why config changes have no effect.

### 2. Does WayVNC 0.5.0 Support the `-C` Config File Flag?

**Check:** Run `wayvnc --help` and look for `-C` or `--config` flag

**If NOT supported:** WayVNC is ignoring the config file entirely and using defaults.

### 3. Why is the Log File Empty?

**Possible causes:**
1. **WayVNC exits immediately** - Dies before writing anything
2. **Output not redirected properly** - Writing to stdout/stderr not captured
3. **WayVNC produces no output** - Silent by default in 0.5.0
4. **File permissions** - Can't write to log file

**Investigation:** Run WayVNC manually in foreground to see actual output

### 4. Is WayVNC Actually Reading the Config File?

**Test:**
- Put an invalid syntax in config (e.g., `invalid_option=xyz`)
- If WayVNC starts anyway, config is being ignored
- If WayVNC fails, config is being read

### 5. What Security Types Does WayVNC 0.5.0 Offer By Default?

**Without config/flags:** WayVNC might:
- Offer ONLY Type 2 (password required) by default
- Offer Type 1 (None) by default
- Require TLS/encryption (offering only secure types)

## Investigation Scripts Created

### 1. `/home/user/waydroid-proxmox/investigate-wayvnc-auth.sh`
**Purpose:** Comprehensive diagnostic script
**What it does:**
- Reads actual config file content
- Checks file permissions
- Searches for all possible config locations
- Shows current WayVNC process and command line
- Runs `wayvnc --help` to see supported options
- Checks service status and logs
- Runs WayVNC manually with verbose output (15 sec test)
- Tests WayVNC without config file
- Searches binary for authentication-related strings
- Checks for TLS certificate files

**Usage:** `./investigate-wayvnc-auth.sh`

### 2. `/home/user/waydroid-proxmox/test-wayvnc-noauth-methods.sh`
**Purpose:** Test various methods to disable authentication
**What it tests:**
- Method 1: Command-line only (`wayvnc 0.0.0.0 5900`)
- Method 2: Using config file with `-C` flag
- Method 3: Config + explicit address/port arguments
- Method 4: Create password file and use password auth instead
- Method 5: Try different config file syntaxes (YAML vs INI)
- Method 6: Test actual VNC connection to see real error

**Usage:** `./test-wayvnc-noauth-methods.sh`

## Hypotheses Ranked by Likelihood

### Hypothesis #1: WayVNC 0.5.0 Does NOT Support `enable_auth=false` (70% likely)

**Evidence:**
- HANDOVER.md states 0.5.0 "doesn't support" several config options
- Commit message says "built without auth support" but might be misinterpretation
- This is an old version (0.5.0 from ~2021), current is 0.9.x
- Config changes have had no effect

**If true, solutions:**
1. Use password authentication instead (create password file)
2. Upgrade WayVNC to version 0.8.0+
3. Compile WayVNC from source with auth disabled

### Hypothesis #2: WayVNC 0.5.0 Doesn't Support `-C` Flag (20% likely)

**Evidence:**
- If config file flag was added in later version, command is invalid
- Would explain why config changes have no effect
- Would NOT explain empty log file (should show "unknown option" error)

**Test:** Check `wayvnc --help` for `-C` flag

**If true, solution:** Use command-line arguments only, no config file

### Hypothesis #3: Config File Syntax Error (5% likely)

**Evidence:**
- INI format should be straightforward
- Script creates simple, valid-looking config

**Test:** Run manually and check for parse errors in output

### Hypothesis #4: WayVNC is Not Actually Running (5% likely)

**Evidence:**
- User says "WayVNC 0.5.0 is running"
- But log file is empty
- Might be exiting immediately

**Test:** Check `ps aux | grep wayvnc` and `ss -tlnp | grep 5900`

## Recommended Action Plan

### Step 1: Run Investigation Script (5 minutes)
```bash
cd /home/user/waydroid-proxmox
./investigate-wayvnc-auth.sh > investigation-output.txt 2>&1
```

**What to look for in output:**
- [ ] Does `wayvnc --help` show `-C` or `--config` flag?
- [ ] Does verbose run show config being parsed?
- [ ] Does binary contain "enable_auth" string?
- [ ] Is port 5900 actually listening?
- [ ] What does WayVNC output when run manually?

### Step 2: Based on Results

#### If `-C` flag doesn't exist:
Config file approach won't work. Try: `wayvnc 0.0.0.0 5900` directly.

#### If `enable_auth` not in binary:
Option doesn't exist in 0.5.0. Two choices:
1. **Quick fix:** Use password authentication
   ```bash
   pct exec 103 -- bash -c 'echo "mypassword" > /home/waydroid/.config/wayvnc/password'
   ```
   Update config to reference password file (test if password_file is supported)

2. **Proper fix:** Upgrade WayVNC to 0.8.0+

#### If WayVNC not running:
Check startup script, check for crashes, enable debug output.

#### If config IS being read but auth still required:
WayVNC 0.5.0 might not honor `enable_auth=false`. Upgrade required.

### Step 3: Test Methods Script (10 minutes)
```bash
./test-wayvnc-noauth-methods.sh
```

This will show which approach (if any) successfully starts WayVNC without authentication.

## Quick Solutions to Try NOW

### Solution A: Test Without Config (30 seconds)
```bash
pct exec 103 -- pkill -9 wayvnc
pct exec 103 -- bash -c '
  DISPLAY_UID=$(id -u waydroid)
  nohup su - waydroid -c "XDG_RUNTIME_DIR=/run/user/$DISPLAY_UID WAYLAND_DISPLAY=wayland-1 wayvnc 0.0.0.0 5900 > /tmp/wayvnc-test.log 2>&1" &
'
sleep 5
pct exec 103 -- ss -tlnp | grep 5900
pct exec 103 -- cat /tmp/wayvnc-test.log
```

Try connecting. If same error, config file was never the issue.

### Solution B: Use Password Authentication (2 minutes)
```bash
pct exec 103 -- bash -c 'echo "waydroid123" > /home/waydroid/.config/wayvnc/password'
pct exec 103 -- bash -c 'chown waydroid:waydroid /home/waydroid/.config/wayvnc/password'
pct exec 103 -- bash -c 'chmod 600 /home/waydroid/.config/wayvnc/password'

# Try connecting with password: waydroid123
```

### Solution C: Check WayVNC Version Capabilities (1 minute)
```bash
pct exec 103 -- wayvnc --help 2>&1 | grep -E "auth|config|password"
```

This immediately shows what options are available.

## Expected Outcome

After running the investigation script, you'll know:

1. **What config options WayVNC 0.5.0 actually supports**
2. **Why the log file is empty** (WayVNC crashes? Silent? Wrong redirect?)
3. **Whether WayVNC is using the config file** or ignoring it
4. **What security types WayVNC offers** (might be in verbose output)
5. **If authentication CAN be disabled** in this version at all

## Most Likely Resolution

Based on the evidence, **WayVNC 0.5.0 probably requires authentication** and the `enable_auth=false` option either:
- Doesn't exist in 0.5.0
- Exists but is broken/ignored
- Has different syntax

**Recommended fix:**
1. **Short-term:** Set up password authentication (if supported)
2. **Long-term:** Upgrade to WayVNC 0.8.0+ which definitely supports no-auth mode

## Files Reference

**Scripts in repo:**
- `/home/user/waydroid-proxmox/investigate-wayvnc-auth.sh` - Diagnostic script (NEW)
- `/home/user/waydroid-proxmox/test-wayvnc-noauth-methods.sh` - Test various approaches (NEW)
- `/home/user/waydroid-proxmox/fix-wayvnc-final.sh` - Latest fix attempt (already run)
- `/home/user/waydroid-proxmox/WAYVNC_AUTH_INVESTIGATION.md` - Detailed analysis (NEW)

**Files in container 103:**
- `/home/waydroid/.config/wayvnc/config` - Config file (created by fix script)
- `/usr/local/bin/start-waydroid.sh` - Startup script
- `/var/log/waydroid-wayvnc.log` - Log file (EMPTY)
- `/bin/wayvnc` - WayVNC binary version 0.5.0

## Next Steps

1. **Run investigation script:** `./investigate-wayvnc-auth.sh`
2. **Review output** for capability information
3. **Run test script:** `./test-wayvnc-noauth-methods.sh`
4. **Determine:** Can auth be disabled in 0.5.0?
5. **If NO:** Set up password auth or upgrade
6. **If YES:** Fix config syntax or startup command

---

**Created:** 2025-11-13
**Context:** WayVNC authentication issue investigation
**Status:** Scripts ready to run, awaiting diagnostic results
