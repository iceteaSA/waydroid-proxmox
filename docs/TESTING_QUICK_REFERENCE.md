# Testing Quick Reference Card

Quick reference for the Waydroid LXC comprehensive testing framework.

## Quick Commands

```bash
# Basic test (text output)
./scripts/test-complete.sh

# Quick test (fast)
./scripts/test-complete.sh --quick

# Thorough test (complete)
./scripts/test-complete.sh --thorough

# JSON output
./scripts/test-complete.sh --format json

# HTML report
./scripts/test-complete.sh --format html

# All formats
./scripts/test-complete.sh --format all

# Verbose output
./scripts/test-complete.sh --verbose

# CI/CD mode
./scripts/test-complete.sh --ci --format json
```

## Test Categories (45+ tests)

| Category | Tests | Mode |
|----------|-------|------|
| **System Resources** | CPU, Memory, Disk, I/O | All |
| **Host Config** | Proxmox, Modules, GPU | Host |
| **LXC Config** | Container, GPU Access | Container |
| **Waydroid** | Install, Init, Service, Apps | Container |
| **Wayland** | Compositor, Display | Container |
| **VNC Server** | Install, Service, Port, Security | Container |
| **API Server** | Script, Service, Endpoints | Container |
| **Audio** | PulseAudio, PipeWire, Devices | Thorough |
| **Clipboard** | Tools, Sync, ADB | Thorough |
| **GPU Performance** | Rendering, Vulkan | Thorough |
| **Network** | DNS, Internet, HTTP, IP | All |

## Exit Codes

| Code | Status | Action |
|------|--------|--------|
| `0` | ✓ Success | No action needed |
| `1` | ⚠ Warning/Failed | Review results |
| `2` | ✗ Critical | Fix immediately |

## Output Formats

### Text Report
```bash
./scripts/test-complete.sh --format text
# Location: /tmp/waydroid-test-results/waydroid-test-YYYYMMDD-HHMMSS.txt
```

### JSON Report
```bash
./scripts/test-complete.sh --format json > results.json
# Structure:
# - report: metadata
# - summary: pass/fail counts
# - system: host info
# - tests: detailed results
# - metrics: performance data
```

### HTML Report
```bash
./scripts/test-complete.sh --format html
# Location: /tmp/waydroid-test-results/waydroid-test-YYYYMMDD-HHMMSS.html
# Open in browser for interactive view
```

## Common Use Cases

### Development
```bash
# Quick check during development
./scripts/test-complete.sh --quick --verbose
```

### Production
```bash
# Complete validation
./scripts/test-complete.sh --thorough --format all
```

### CI/CD
```bash
# Automated testing
./scripts/test-complete.sh --quick --ci --format json | jq
```

### Pre-Deployment
```bash
# Before making changes
./scripts/test-complete.sh --thorough
if [ $? -eq 0 ]; then
    echo "Safe to proceed"
else
    echo "Fix issues first"
fi
```

## Performance Thresholds

| Metric | Threshold | Impact |
|--------|-----------|--------|
| CPU Load | < 2.0/core | System responsiveness |
| Memory | > 512 MB free | App stability |
| Disk Space | < 90% full | Data operations |
| API Response | < 1000 ms | User experience |
| VNC Handshake | < 2000 ms | Remote access |

## Interpreting Results

### All Pass
```
✓ System Resources: CPU Load (Pass)
✓ Waydroid: Installation (Pass)
✓ VNC Server: Service (Pass)

Overall Status: ✓ ALL TESTS PASSED
```
**Action**: None needed

### With Warnings
```
✓ System Resources: CPU Load (Pass)
⚠ VNC Server: Security (Warn)
✓ API Server: Endpoints (Pass)

Overall Status: ⚠ PASSED WITH WARNINGS
```
**Action**: Review warnings, system functional

### With Failures
```
✓ System Resources: CPU Load (Pass)
✗ Waydroid: Installation (Fail)
  └─ Waydroid command not found
✗ VNC Server: Service (Fail)

Overall Status: ✗ TESTS FAILED
```
**Action**: Fix failures immediately

## Automation Examples

### Cron (Hourly)
```bash
0 * * * * /path/to/scripts/test-complete.sh --quick --ci --format json > /var/log/waydroid-test.json 2>&1
```

### Systemd Timer
```ini
# /etc/systemd/system/waydroid-test.timer
[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
```

### Pre-commit Hook
```bash
#!/bin/bash
./scripts/test-complete.sh --quick --ci
exit $?
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Permission denied | `chmod +x scripts/test-complete.sh` |
| Not in LXC error | Use `--from-host` flag |
| Tests timeout | Use `--quick` mode |
| Missing curl | `apt install curl` |
| No reports | Check `--output-dir` permissions |

## Integration Snippets

### Prometheus Export
```bash
./scripts/test-complete.sh --quick --format json | \
jq -r '.metrics | to_entries[] | "waydroid_\(.key) \(.value)"'
```

### Slack Notification
```bash
./scripts/test-complete.sh --quick --ci --format json > /tmp/result.json
[ $? -ne 0 ] && curl -X POST -H 'Content-type: application/json' \
  --data "{\"text\":\"Tests failed\"}" $SLACK_WEBHOOK
```

### Home Assistant Sensor
```yaml
sensor:
  - platform: command_line
    name: "Waydroid Health"
    command: "./scripts/test-complete.sh --quick --ci --format json | jq -r '.summary.success_rate'"
    unit_of_measurement: "%"
```

## Related Tools

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `test-complete.sh` | Full system test | Validation, CI/CD |
| `health-check.sh` | Quick health check | Monitoring |
| `test-setup.sh` | Original test | Legacy |
| `test-clipboard.sh` | Clipboard specific | Clipboard debug |
| `test-examples.sh` | Usage examples | Learning |

## Performance Tips

1. **Use --quick for frequent checks** (30s vs 2min)
2. **Use --thorough before releases** (complete validation)
3. **Cache results** (avoid redundant tests)
4. **Run off-peak** (minimize impact)
5. **Parallel testing** (multiple containers)

## Best Practices

✓ **DO**:
- Run quick tests regularly
- Run thorough tests before changes
- Store reports for trends
- Automate with cron/systemd
- Review warnings promptly
- Use verbose for debugging

✗ **DON'T**:
- Ignore warnings
- Skip pre-deployment tests
- Run during peak hours
- Neglect disk space
- Override exit codes

## Getting Help

1. **View examples**: `./scripts/test-examples.sh`
2. **Full docs**: `docs/TESTING.md`
3. **Help**: `./scripts/test-complete.sh --help`
4. **Verbose**: Add `--verbose` flag
5. **Logs**: Check report ISSUES section

## Quick Diagnosis

```bash
# Full system health
./scripts/test-complete.sh --quick

# GPU only
glxinfo | grep "direct rendering"

# VNC only
ss -tuln | grep 5900

# API only
curl http://localhost:8080/status

# Network only
ping -c 1 8.8.8.8

# Waydroid only
waydroid status
```

## Version Info

- **Script Version**: 1.0.0
- **Test Categories**: 11
- **Total Tests**: 45+
- **Output Formats**: 3 (text, JSON, HTML)
- **Test Modes**: 2 (quick, thorough)

---

**Note**: For detailed information, see [TESTING.md](TESTING.md)
