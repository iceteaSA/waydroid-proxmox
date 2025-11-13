# Test Setup Script Improvements

## Overview
The `/home/user/waydroid-proxmox/scripts/test-setup.sh` script has been significantly enhanced to provide comprehensive testing capabilities with proper exit codes, verbose diagnostics, and CI/CD integration.

## Key Improvements

### 1. Exit Code Management
- **Exit 0**: All tests passed successfully
- **Exit 1**: Some tests failed (allows CI/CD to detect issues)
- **Exit 2**: Critical failure (e.g., not running in LXC)
- Previously: Always exited with code 0 regardless of test results

### 2. Comprehensive Test Suite (12 Tests)

#### Existing Tests (Enhanced):
1. **GPU Device Access** - Checks /dev/dri/card0 and renderD128 with detailed permissions
2. **Kernel Modules** - Validates binder_linux and ashmem_linux modules
3. **Waydroid Installation** - Verifies installation and initialization status
4. **Wayland Compositor** - Checks for Sway and Weston
5. **VNC Server** - Validates WayVNC installation and service status
6. **API Server** - Checks API script and service status
7. **Systemd Services** - Verifies all required services

#### New Tests:
8. **Network Connectivity** - Tests DNS resolution, ICMP ping, and HTTP/HTTPS connectivity
9. **GPU Performance** - Validates GPU acceleration using glxinfo and checks for direct rendering
10. **Waydroid App Launch** - Verifies app manager accessibility and installed apps
11. **VNC Connection Test** - Performs actual TCP connection test to VNC port
12. **API Endpoint Tests** - Makes HTTP requests to API endpoints to verify functionality

### 3. JSON Output for CI/CD
```bash
./test-setup.sh --json
```

Output format:
```json
{
  "timestamp": "2025-11-12T10:30:00Z",
  "summary": {
    "total": 12,
    "passed": 10,
    "failed": 1,
    "warnings": 1,
    "exit_code": 1
  },
  "system": {
    "hostname": "waydroid-lxc",
    "ip": "10.0.0.100",
    "os": "Ubuntu 22.04 LTS",
    "kernel": "5.15.0-generic"
  },
  "tests": [
    {
      "name": "GPU Device Access",
      "result": "pass",
      "message": "GPU devices accessible and writable",
      "fix_suggestion": ""
    },
    ...
  ]
}
```

### 4. Verbose Mode
```bash
./test-setup.sh --verbose
```

Features:
- Detailed diagnostic messages for each test step
- Shows what's being checked before results
- Helpful for debugging issues
- Can be combined with JSON output

### 5. Fix Suggestions
Each failed or warning test now includes specific, actionable fix suggestions:

**Example fixes provided:**
- GPU access issues: Specific LXC config entries to add
- Module loading: Exact modprobe commands and config files
- Service issues: systemctl commands to start/enable services
- Network problems: Configuration files to check and commands to run
- Missing packages: Exact apt install commands

## Usage Examples

### Standard Test Run
```bash
./test-setup.sh
```
Runs all tests with color-coded output and detailed summary.

### Verbose Diagnostics
```bash
./test-setup.sh --verbose
```
Shows detailed step-by-step diagnostics during test execution.

### CI/CD Integration
```bash
./test-setup.sh --json > test-results.json
echo "Exit code: $?"
```
Generates machine-readable JSON output for automated systems.

### Combined Mode
```bash
./test-setup.sh --json --verbose
```
JSON output with verbose details in JSON messages.

### Get Help
```bash
./test-setup.sh --help
```
Shows usage information and examples.

## Test Result Tracking

The script now tracks:
- **Total tests run**: Complete count of all test cases
- **Passed tests**: Tests that completed successfully
- **Failed tests**: Critical failures that need immediate attention
- **Warnings**: Non-critical issues that should be addressed

Each test result includes:
- Test name
- Pass/Fail/Warn status
- Descriptive message
- Fix suggestion (if applicable)

## Enhanced Features

### 1. Smart Test Execution
- Tests that depend on prerequisites (e.g., Waydroid running) are skipped gracefully
- Each test is independent and won't crash the entire test suite
- Results are accumulated and displayed at the end

### 2. Comprehensive Network Testing
- DNS resolution using multiple methods (host, nslookup, dig)
- ICMP connectivity test to 8.8.8.8
- HTTP/HTTPS connectivity test using curl
- Identifies specific network layer failures

### 3. GPU Performance Validation
- Uses glxinfo to verify direct rendering
- Extracts and displays GPU renderer information
- Checks for Intel GPU tools availability
- Provides specific driver installation commands if issues found

### 4. Real Connection Tests
- VNC: Actually attempts TCP connection to port 5900
- API: Makes HTTP request to /status endpoint
- Validates response format and content
- Distinguishes between port listening vs. accepting connections

### 5. Waydroid Integration Testing
- Checks if Waydroid is initialized
- Verifies app manager accessibility
- Counts installed applications
- Non-intrusive testing (doesn't launch apps)

## Output Improvements

### Before:
- Simple pass/fail indicators
- Always exit code 0
- Limited diagnostic information
- No structured output option
- Generic recommendations

### After:
- Detailed pass/fail/warn status for each test
- Proper exit codes (0, 1, 2)
- Verbose mode with step-by-step diagnostics
- JSON output for CI/CD integration
- Specific fix suggestions for each failure
- Comprehensive summary with statistics
- Grouped failed tests with fixes section

## Integration with CI/CD

### Example GitHub Actions Workflow
```yaml
- name: Run Waydroid Tests
  run: |
    ./scripts/test-setup.sh --json > test-results.json

- name: Upload Test Results
  uses: actions/upload-artifact@v3
  with:
    name: test-results
    path: test-results.json

- name: Check Test Status
  run: |
    if [ $(jq '.summary.failed' test-results.json) -gt 0 ]; then
      echo "Tests failed!"
      exit 1
    fi
```

### Example GitLab CI
```yaml
test:
  script:
    - ./scripts/test-setup.sh --json | tee test-results.json
  artifacts:
    reports:
      junit: test-results.json
    when: always
```

## Backward Compatibility

The script maintains backward compatibility:
- Running without arguments works exactly as before
- All original tests are preserved (just enhanced)
- Color output is maintained for interactive use
- Helper functions remain unchanged

## Future Enhancements

Potential additions for future versions:
- Performance benchmarking tests
- Load testing for API endpoints
- Automated repair mode (--fix flag)
- Export results to multiple formats (XML, TAP)
- Integration with monitoring systems
- Test result history tracking
- Custom test selection (--test-filter)
