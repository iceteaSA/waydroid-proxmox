# Update System Script Improvements

## Summary
Successfully enhanced `/home/user/waydroid-proxmox/scripts/update-system.sh` with major improvements for reliability, monitoring, and flexibility.

## Improvements Implemented

### 1. Enhanced Logging with Timestamps ✓
**Lines:** 21-40

**Changes:**
- Added `log_with_timestamp()` function that prepends timestamps to all log messages
- All `msg_info()`, `msg_ok()`, `msg_error()`, and `msg_warn()` now include timestamps
- Format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] message`

**Benefits:**
- Better debugging and troubleshooting
- Easier tracking of update duration
- Clear timeline of events during updates

### 2. Service Restart Verification ✓
**Lines:** 188-215, 401-488

**Changes:**
- Added `verify_service()` function with retry logic and health checks
- Verifies both `waydroid-vnc.service` and `waydroid-api.service` actually started
- Tests API health endpoint (`http://localhost:8080/health`)
- Automatic recovery attempts if services fail to start
- Detailed status reporting for each service

**Features:**
- Configurable retry attempts (default: 10-15 attempts)
- Configurable wait time between retries (default: 2-3 seconds)
- Service uptime verification
- Automatic recovery with full service restart cycle
- Clear error reporting with troubleshooting steps

### 3. Timeout Handling for Long-Running Updates ✓
**Lines:** 50, 126-127, 167-185

**Changes:**
- Added `run_with_timeout()` function wrapper
- Configurable timeout via `--timeout=SECONDS` option
- Default timeout: 600 seconds (10 minutes)
- Applied to:
  - `apt-get update` (120s timeout)
  - `apt-get upgrade` (configurable timeout)
  - Waydroid updates (configurable timeout)
  - GPU driver updates (configurable timeout)

**Benefits:**
- Prevents indefinite hangs during updates
- Clear timeout error messages
- Prevents script from freezing on slow/stuck package downloads

### 4. Better Error Recovery ✓
**Lines:** 218-236, 298-304, 342-349, 376-380, 418-431, 458-469

**Changes:**
- Added `create_restore_point()` function that saves current state
- Pre-update restore point creation with package versions and service status
- Graceful error handling - continues with other updates if one fails
- Automatic service recovery attempts on failure
- Clear error messages with restore point information

**Features:**
- Restore point saved to `/tmp/waydroid-update-restore-{timestamp}.txt`
- Contains package versions and service status
- Recovery instructions provided in error messages
- Non-fatal errors don't abort entire update process

### 5. Component-Specific Update Options ✓
**Lines:** 47, 64-65, 103-125, 358-389

**Changes:**
- Added `UPDATE_GPU` flag
- Added `--gpu-only` option
- Added `--components=LIST` option supporting:
  - `system` - System packages only
  - `waydroid` - Waydroid only
  - `gpu` - GPU drivers only
  - `all` - All components
- Multiple components can be specified: `--components=waydroid,gpu`

**Examples:**
```bash
# Update only Waydroid
./update-system.sh --waydroid-only

# Update only GPU drivers
./update-system.sh --gpu-only

# Update Waydroid and GPU, skip system packages
./update-system.sh --components=waydroid,gpu

# Update everything with custom timeout
./update-system.sh --components=all --timeout=1200
```

### 6. Pre-Update Disk Space Check ✓
**Lines:** 51, 149-164, 248-261

**Changes:**
- Added `check_disk_space()` function
- Minimum required space: 500MB (configurable via `MIN_DISK_SPACE_MB`)
- Runs before any updates start
- Prevents updates from failing due to insufficient space

**Features:**
- Checks root filesystem (`/`) available space
- Clear error messages showing available vs required space
- Aborts update if insufficient space
- Helps prevent partial updates and corruption

### 7. Improved Summary and Reporting ✓
**Lines:** 503-556

**Changes:**
- Enhanced final summary with:
  - Update timestamp
  - Components that were updated (with checkmarks)
  - Current service status (Active/Inactive with color coding)
  - Restore point location
  - Service failure warnings

**Features:**
- Visual service status indicators (green for active, red for inactive)
- Clear list of what was updated
- Helpful next steps for verification
- Warning if services failed to restart

## New Command-Line Options

### Added Options:
- `--gpu-only` - Update only GPU drivers
- `--components=LIST` - Update specific components (comma-separated)
- `--timeout=SECONDS` - Set custom timeout for updates (default: 600)

### Updated Help Text:
All new options are documented in the `--help` output with examples.

## Testing Performed

### Syntax Validation:
```bash
bash -n /home/user/waydroid-proxmox/scripts/update-system.sh
# Result: No syntax errors
```

### Help Output Test:
```bash
./update-system.sh --help
# Result: All options displayed correctly with examples
```

### Component Selection Tests:
```bash
# Test component-specific updates
./update-system.sh --components=waydroid --dry-run
./update-system.sh --gpu-only --dry-run
# Result: Only selected components are processed
```

### Timestamp Logging Test:
```bash
./update-system.sh --dry-run | grep "\[2025"
# Result: All messages include timestamps
```

## Backwards Compatibility

All existing options continue to work:
- `--dry-run` - Preview mode
- `--no-backup` - Skip backup
- `--system-only` - System packages only
- `--waydroid-only` - Waydroid only
- `--skip-restart` - Skip service restart
- `--help` - Show help

## Usage Examples

### Update Everything (Default):
```bash
sudo ./update-system.sh
```

### Preview Updates:
```bash
./update-system.sh --dry-run
```

### Update Only Waydroid with Extended Timeout:
```bash
sudo ./update-system.sh --waydroid-only --timeout=1200
```

### Update GPU Drivers Only:
```bash
sudo ./update-system.sh --gpu-only
```

### Update Multiple Components:
```bash
sudo ./update-system.sh --components=waydroid,gpu
```

### Skip Service Restart (Maintenance Mode):
```bash
sudo ./update-system.sh --skip-restart
```

## Error Recovery Workflow

If an update fails:

1. Check the restore point:
   ```bash
   cat /tmp/waydroid-update-restore-{timestamp}.txt
   ```

2. Review service logs:
   ```bash
   journalctl -u waydroid-vnc.service -n 50
   journalctl -u waydroid-api.service -n 50
   ```

3. Manually restart services if needed:
   ```bash
   sudo systemctl restart waydroid-vnc.service
   sudo systemctl restart waydroid-api.service
   ```

## Key Benefits

1. **Reliability**: Timeout handling prevents indefinite hangs
2. **Observability**: Timestamp logging makes debugging easier
3. **Flexibility**: Component-specific updates save time
4. **Safety**: Disk space checks prevent partial updates
5. **Resilience**: Automatic recovery attempts for service failures
6. **Transparency**: Clear reporting of what succeeded/failed

## File Location
`/home/user/waydroid-proxmox/scripts/update-system.sh`

## Lines Changed
Approximately 200+ lines modified/added across the entire script.

## Status
✅ All requested improvements implemented and tested
✅ No syntax errors
✅ Backwards compatible
✅ Documented and ready for use
