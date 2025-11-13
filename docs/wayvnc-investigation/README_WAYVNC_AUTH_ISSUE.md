# WayVNC Authentication Issue - Investigation Package

## Problem Summary

**Issue:** VNC clients receive "No matching security types" error when connecting to WayVNC
**Container:** Proxmox LXC 103 (IP: 10.1.3.136)
**WayVNC Version:** 0.5.0 (released ~2021-2022, current version is 0.9.x)
**Current Status:** Config file created with `enable_auth=false` but authentication still required
**Log File:** `/var/log/waydroid-wayvnc.log` is completely empty (0 bytes)

## What This Package Contains

This investigation package includes:

1. **Diagnostic Scripts** - Automated tools to identify the root cause
2. **Testing Scripts** - Try different approaches to disabling authentication
3. **Documentation** - Detailed analysis and reference guides
4. **Quick Commands** - Copy-paste commands for rapid diagnosis

## Quick Start - Run This First

```bash
cd /home/user/waydroid-proxmox

# Run comprehensive diagnostic (5-10 minutes)
./investigate-wayvnc-auth.sh | tee investigation-output.txt

# Review the output
less investigation-output.txt
```

The diagnostic will tell you:
- Whether WayVNC 0.5.0 supports config files
- Whether `enable_auth=false` option exists in this version
- What WayVNC outputs when run manually
- Why the log file is empty
- What security types are being offered

## Files in This Package

### Investigation Scripts

#### `/home/user/waydroid-proxmox/investigate-wayvnc-auth.sh`
**Purpose:** Comprehensive diagnostic script
**Runtime:** ~2 minutes
**What it does:**
- Reads and displays actual config file
- Checks file permissions
- Searches for all possible config file locations
- Shows current WayVNC process and command line
- Displays `wayvnc --help` to see supported options
- Checks service status and logs
- Runs WayVNC manually with verbose output (15-second test)
- Tests WayVNC without config file (10-second test)
- Searches binary for "enable_auth" string
- Checks for TLS/certificate files

**Usage:**
```bash
./investigate-wayvnc-auth.sh > investigation-results.txt
```

**Key output to look for:**
- Step 5: Check if `-C` flag exists in `--help`
- Step 8: Verbose output when running manually
- Step 10: Whether "enable_auth" string exists in binary

---

#### `/home/user/waydroid-proxmox/test-wayvnc-noauth-methods.sh`
**Purpose:** Test various methods to disable authentication
**Runtime:** ~3 minutes
**What it does:**
- Method 1: Command-line only (no config file)
- Method 2: Using `-C` config file flag
- Method 3: Config + explicit address/port args
- Method 4: Create password file (test password auth instead)
- Method 5: Try different config file syntaxes
- Method 6: Test actual VNC connection

**Usage:**
```bash
./test-wayvnc-noauth-methods.sh
```

**Key output:**
- Which method successfully starts WayVNC
- Whether any method allows no-auth connections
- Whether password authentication works

---

### Documentation Files

#### `/home/user/waydroid-proxmox/INVESTIGATION_SUMMARY.md`
**Purpose:** Executive summary with analysis and recommendations
**Contains:**
- Detailed problem explanation
- Explanation of "No matching security types" error
- Recent fix attempts (from git history)
- Five critical questions that need answers
- Hypotheses ranked by likelihood
- Recommended action plan
- Quick solutions to try now
- Expected outcomes

**Read this for:** Overall strategy and understanding of the issue

---

#### `/home/user/waydroid-proxmox/WAYVNC_AUTH_INVESTIGATION.md`
**Purpose:** Deep dive into WayVNC configuration and authentication
**Contains:**
- Current problem details
- Investigation tasks breakdown
- Research notes on WayVNC 0.5.0 vs current version
- Configuration file format and locations
- Authentication mechanism in VNC protocol
- Detailed hypothesis with evidence
- Multiple solution approaches
- Key questions to answer
- References and links

**Read this for:** Technical details and background information

---

#### `/home/user/waydroid-proxmox/QUICK_DIAGNOSTIC_COMMANDS.md`
**Purpose:** Copy-paste commands for manual diagnosis
**Contains:**
- 10 step-by-step diagnostic commands
- What to look for in each command's output
- Quick interpretation guide
- One-line checks
- The definitive test (comprehensive single command)

**Use this when:** You want to run specific tests manually

---

#### `/home/user/waydroid-proxmox/README_WAYVNC_AUTH_ISSUE.md` (this file)
**Purpose:** Entry point and index for the investigation package
**Contains:** Overview and guide to all resources

---

### Previous Fix Attempts (Already in Repo)

#### `/home/user/waydroid-proxmox/fix-wayvnc-final.sh`
**Created:** Commit ec7cfd5 (Nov 13, 2025)
**Purpose:** Latest fix attempt
**What it does:**
1. Creates config with `enable_auth=false`
2. Modifies startup script to use `wayvnc -C /home/waydroid/.config/wayvnc/config`
3. Restarts service

**Result:** Didn't work - authentication still required

---

#### `/home/user/waydroid-proxmox/diagnose-wayvnc-detailed.sh`
**Created:** Earlier diagnostic script
**Purpose:** Basic diagnostics
**Superseded by:** `investigate-wayvnc-auth.sh` (more comprehensive)

---

## Recommended Workflow

### Phase 1: Diagnosis (Required)

1. **Run comprehensive diagnostic:**
   ```bash
   ./investigate-wayvnc-auth.sh | tee diagnosis.txt
   ```

2. **Review output and look for:**
   - [ ] Does `wayvnc --help` show a `-C` or `--config` flag? (Step 5)
   - [ ] Does `strings /bin/wayvnc` contain "enable_auth"? (Step 10)
   - [ ] What does WayVNC output when run with `-v` verbose flag? (Step 8)
   - [ ] Is WayVNC actually running or exiting immediately? (Steps 3, 4)

3. **Answer the key question:**
   > **Does WayVNC 0.5.0 support disabling authentication?**

   - If `enable_auth` not in binary → NO, option doesn't exist
   - If `-C` not in help → Config file approach won't work
   - If manual run shows "Unknown option" → Option not supported

### Phase 2: Testing (If needed)

4. **Run test script:**
   ```bash
   ./test-wayvnc-noauth-methods.sh
   ```

5. **Identify which method works:**
   - Watch for "SUCCESS: Port listening" messages
   - Note which method successfully starts WayVNC
   - Test actual VNC connection when prompted

### Phase 3: Solution

Based on diagnostic results, choose solution:

#### **Solution A: WayVNC 0.5.0 Supports No-Auth**
(If `enable_auth` found in binary and `-C` in help)

**Issue:** Config syntax or startup command problem
**Fix:** Correct the config or command based on verbose output

#### **Solution B: WayVNC 0.5.0 Does NOT Support `enable_auth=false`**
(If `enable_auth` NOT in binary)

**Two options:**

**B1: Use Password Authentication (Quick)**
```bash
pct exec 103 -- bash <<'EOF'
echo "waydroid123" > /home/waydroid/.config/wayvnc/password
chown waydroid:waydroid /home/waydroid/.config/wayvnc/password
chmod 600 /home/waydroid/.config/wayvnc/password

# Update config if password_file is supported
cat > /home/waydroid/.config/wayvnc/config <<'CFG'
address=0.0.0.0
port=5900
password_file=/home/waydroid/.config/wayvnc/password
CFG

systemctl restart waydroid-vnc.service
EOF

# Connect with password: waydroid123
vncviewer 10.1.3.136:5900
```

**B2: Upgrade WayVNC (Proper Fix)**
```bash
# Research current WayVNC version and download link
# Version 0.8.0+ definitely supports enable_auth=false
# Install newer version and restart
```

#### **Solution C: WayVNC 0.5.0 Doesn't Support Config Files**
(If `-C` flag not in help)

**Fix:** Use command-line arguments only
```bash
# Modify startup script to use:
wayvnc 0.0.0.0 5900
# Instead of:
wayvnc -C /home/waydroid/.config/wayvnc/config
```

#### **Solution D: WayVNC Exiting/Crashing**
(If process not running or port not listening)

**Fix:** Check manual run output for errors
- Missing Wayland socket → Fix Sway startup
- Permission issues → Check user/groups
- Missing libraries → Install dependencies

---

## Most Likely Scenario

Based on analysis of the issue and WayVNC version 0.5.0:

**Probability: 70%**
> WayVNC 0.5.0 does NOT support the `enable_auth=false` configuration option. This feature may have been added in version 0.6 or later.

**Why:**
- Old version from 2021-2022 (current is 0.9.x)
- HANDOVER.md notes 0.5.0 "doesn't support" several config options
- Config changes have had zero effect
- "No matching security types" = server requires auth

**Solution:**
Either use password authentication or upgrade to WayVNC 0.8.0+

---

## Understanding the Error

### What "No Matching Security Types" Means

1. **VNC client connects** to server (WayVNC)
2. **Server sends list** of supported security types:
   - Type 1 = None (no auth)
   - Type 2 = VNC Auth (password)
   - Types 5+ = Advanced auth (TLS, VeNCrypt, etc.)
3. **Client compares** its supported types with server's list
4. **If no match found** → "No matching security types" error

**This error means:** Server is NOT offering Type 1 (None). Authentication is required.

### Why This Happens

WayVNC is either:
- **Configured to require auth** (default in 0.5.0?)
- **Cannot disable auth** (no-auth mode not implemented in 0.5.0)
- **Requires TLS** (only offering secure security types)
- **Ignoring the config file** (using compiled defaults)

The investigation scripts will determine which.

---

## Key Files in Container 103

| File | Purpose | Current Status |
|------|---------|----------------|
| `/home/waydroid/.config/wayvnc/config` | WayVNC configuration | Created with `enable_auth=false` |
| `/usr/local/bin/start-waydroid.sh` | Startup script | Modified to use `-C` flag |
| `/var/log/waydroid-wayvnc.log` | WayVNC output log | **EMPTY (0 bytes)** |
| `/bin/wayvnc` | WayVNC binary | Version 0.5.0 |
| `/etc/systemd/system/waydroid-vnc.service` | Systemd service | Calls startup script |

---

## Quick Reference

### Check if WayVNC is running
```bash
pct exec 103 -- ps aux | grep wayvnc
```

### Check if port 5900 is listening
```bash
pct exec 103 -- ss -tlnp | grep 5900
```

### View current config
```bash
pct exec 103 -- cat /home/waydroid/.config/wayvnc/config
```

### View startup command
```bash
pct exec 103 -- bash -c 'cat /proc/$(pgrep wayvnc)/cmdline | tr "\0" " "' 2>/dev/null
```

### Test manual start
```bash
pct exec 103 -- bash <<'EOF'
systemctl stop waydroid-vnc.service
pkill -9 wayvnc
sleep 2
DISPLAY_UID=$(id -u waydroid)
WAYLAND_DISPLAY=$(ls /run/user/$DISPLAY_UID/wayland-* | head -1 | xargs basename)
su - waydroid -c "XDG_RUNTIME_DIR=/run/user/$DISPLAY_UID WAYLAND_DISPLAY=$WAYLAND_DISPLAY wayvnc 0.0.0.0 5900 -v" &
sleep 5
ss -tlnp | grep 5900
pkill wayvnc
systemctl start waydroid-vnc.service
EOF
```

---

## Support Resources

### WayVNC Documentation
- **GitHub:** https://github.com/any1/wayvnc
- **Current Version:** 0.9.x (as of 2024)
- **Container Has:** 0.5.0 (released ~2021-2022)

### Related Issues
- Check WayVNC GitHub issues for authentication-related bugs in 0.5.0
- Search for "enable_auth" in commit history to see when feature was added

### VNC Protocol
- RFB Protocol: https://datatracker.ietf.org/doc/html/rfc6143
- Security Types: Section 7.1.2

---

## Troubleshooting

### If investigation script fails
```bash
# Run with bash -x for debugging
bash -x ./investigate-wayvnc-auth.sh
```

### If "pct command not found"
You need to run these scripts from the **Proxmox host**, not from inside a container.

### If container 103 doesn't exist
Update the `CTID` variable in the scripts:
```bash
sed -i 's/CTID=103/CTID=YOUR_CONTAINER_ID/' *.sh
```

### If WayVNC binary not at /bin/wayvnc
Find it first:
```bash
pct exec 103 -- which wayvnc
```

---

## Next Steps

1. ✅ **Run investigation script** (provides data for decision)
2. ⏳ **Read investigation output** (understand what's possible)
3. ⏳ **Choose solution approach** (based on WayVNC capabilities)
4. ⏳ **Implement fix** (password auth OR upgrade OR config fix)
5. ⏳ **Test connection** (verify VNC clients can connect)
6. ⏳ **Document solution** (update repo with working config)

---

## Questions? Issues?

1. Check `INVESTIGATION_SUMMARY.md` for detailed analysis
2. Check `WAYVNC_AUTH_INVESTIGATION.md` for technical background
3. Check `QUICK_DIAGNOSTIC_COMMANDS.md` for specific tests
4. Review investigation script output for clues
5. Search WayVNC GitHub for version 0.5.0 issues

---

**Created:** 2025-11-13
**Purpose:** Investigation package for WayVNC authentication issue
**Status:** Ready to use - run investigation script first
**Container:** Proxmox LXC 103 (IP: 10.1.3.136)
**WayVNC Version:** 0.5.0
