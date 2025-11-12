# Home Assistant Integration

Guide for integrating Waydroid LXC with Home Assistant for automation tasks.

## Overview

The Waydroid LXC includes a REST API that allows Home Assistant to:
- Launch Android applications
- Send intents to Android apps
- Check Waydroid status
- List installed apps

This enables automations like opening a gate control app, controlling IoT devices through Android apps, or triggering actions based on home automation events.

## API Endpoints

The API runs on port `8080` by default.

### GET /status

Get Waydroid status.

**Request:**
```bash
curl http://<container-ip>:8080/status
```

**Response:**
```json
{
  "status": "running",
  "output": "Session:\tRUNNING\nContainer:\tRUNNING\n..."
}
```

### GET /apps

List installed Android apps.

**Request:**
```bash
curl http://<container-ip>:8080/apps
```

**Response:**
```json
{
  "apps": [
    "com.android.settings",
    "com.android.chrome",
    "com.example.gate"
  ]
}
```

### POST /app/launch

Launch an Android application by package name.

**Request:**
```bash
curl -X POST http://<container-ip>:8080/app/launch \
  -H "Content-Type: application/json" \
  -d '{"package": "com.example.gate"}'
```

**Response:**
```json
{
  "success": true,
  "package": "com.example.gate"
}
```

### POST /app/intent

Send an Android intent.

**Request:**
```bash
curl -X POST http://<container-ip>:8080/app/intent \
  -H "Content-Type: application/json" \
  -d '{"intent": "android.intent.action.VIEW -d https://example.com"}'
```

**Response:**
```json
{
  "success": true
}
```

## Home Assistant Configuration

### REST Command

Add REST commands to your Home Assistant configuration.

#### configuration.yaml

```yaml
rest_command:
  # Launch Android app
  waydroid_launch_app:
    url: "http://<container-ip>:8080/app/launch"
    method: POST
    headers:
      Content-Type: "application/json"
    payload: '{"package": "{{ package }}"}'

  # Send Android intent
  waydroid_send_intent:
    url: "http://<container-ip>:8080/app/intent"
    method: POST
    headers:
      Content-Type: "application/json"
    payload: '{"intent": "{{ intent }}"}'
```

### RESTful Sensor

Monitor Waydroid status:

```yaml
sensor:
  - platform: rest
    name: "Waydroid Status"
    resource: "http://<container-ip>:8080/status"
    method: GET
    value_template: "{{ value_json.status }}"
    json_attributes:
      - output
    scan_interval: 30
```

### Automations

#### Example 1: Open Gate App on Button Press

```yaml
automation:
  - alias: "Open Gate via Android App"
    trigger:
      - platform: state
        entity_id: input_button.open_gate
        to: "on"
    action:
      - service: rest_command.waydroid_launch_app
        data:
          package: "com.example.gatecontrol"
      - delay: "00:00:02"
      - service: rest_command.waydroid_send_intent
        data:
          intent: "com.example.gatecontrol.OPEN_GATE"
```

#### Example 2: Launch App at Sunset

```yaml
automation:
  - alias: "Start Security Camera App at Sunset"
    trigger:
      - platform: sun
        event: sunset
    action:
      - service: rest_command.waydroid_launch_app
        data:
          package: "com.camera.app"
```

#### Example 3: Control Smart Device via Android App

```yaml
automation:
  - alias: "Control AC via Android App"
    trigger:
      - platform: numeric_state
        entity_id: sensor.living_room_temperature
        above: 26
    action:
      - service: rest_command.waydroid_launch_app
        data:
          package: "com.aircon.remote"
      - delay: "00:00:03"
      - service: rest_command.waydroid_send_intent
        data:
          intent: "com.aircon.remote.SET_TEMP -e temperature 22"
```

## Advanced Integration

### Using ADB from Home Assistant

For more complex interactions, use ADB (Android Debug Bridge):

#### Shell Command in Home Assistant

```yaml
shell_command:
  waydroid_adb_command: "ssh root@<container-ip> 'adb -s localhost:5555 {{ command }}'"
```

#### Example: Simulate Touch

```yaml
automation:
  - alias: "Tap Gate Open Button"
    trigger:
      - platform: state
        entity_id: input_button.open_gate
    action:
      - service: rest_command.waydroid_launch_app
        data:
          package: "com.example.gateapp"
      - delay: "00:00:03"
      - service: shell_command.waydroid_adb_command
        data:
          command: "shell input tap 500 800"
```

### Node-RED Integration

If using Node-RED with Home Assistant:

#### HTTP Request Node

```json
{
  "method": "POST",
  "url": "http://<container-ip>:8080/app/launch",
  "headers": {
    "Content-Type": "application/json"
  },
  "payload": {
    "package": "com.example.app"
  }
}
```

#### Example Flow

```
[Inject Node] → [Function Node] → [HTTP Request] → [Debug]
```

**Function Node:**
```javascript
msg.payload = {
    "package": "com.example.gatecontrol"
};
return msg;
```

## Use Cases

### 1. Gate/Door Control

**Scenario**: Your gate uses an Android-only app for control.

**Solution**:
1. Install gate control app in Waydroid
2. Create automation to launch app and trigger open command
3. Integrate with Home Assistant dashboard button

**Automation:**
```yaml
automation:
  - alias: "Open Main Gate"
    trigger:
      - platform: state
        entity_id: input_button.main_gate
        to: "on"
    action:
      - service: rest_command.waydroid_launch_app
        data:
          package: "com.gatecompany.control"
      - delay: "00:00:02"
      - service: rest_command.waydroid_send_intent
        data:
          intent: "com.gatecompany.control.ACTION_OPEN_GATE"
```

### 2. Smart Home Devices without API

**Scenario**: Smart device only has Android app, no API.

**Solution**:
1. Install device's Android app in Waydroid
2. Use ADB to simulate touches or send intents
3. Create automations based on home conditions

### 3. Security Camera Integration

**Scenario**: Security camera app that's Android-only.

**Solution**:
1. Run camera app in Waydroid
2. Stream output via VNC
3. Embed VNC stream in Home Assistant dashboard

**Dashboard:**
```yaml
type: iframe
url: "http://<vnc-web-viewer>/?host=<container-ip>&port=5900"
aspect_ratio: 16:9
```

### 4. Voice Assistant Integration

**Scenario**: Control Android apps via voice commands.

**Solution**:
```yaml
intent_script:
  OpenGate:
    speech:
      text: "Opening the gate"
    action:
      - service: rest_command.waydroid_launch_app
        data:
          package: "com.example.gate"
```

## Finding Package Names

To control an app, you need its package name.

### Method 1: List All Apps

```bash
# In the LXC container
waydroid app list
```

### Method 2: Using ADB

```bash
# In the LXC container
adb connect localhost:5555
adb shell pm list packages
```

### Method 3: Via API

```bash
curl http://<container-ip>:8080/apps
```

### Method 4: APK Analyzer

If you have the APK file:
```bash
aapt dump badging app.apk | grep package
```

## Security Considerations

### API Authentication

By default, the API has no authentication. For production:

#### Option 1: Firewall Rules

Restrict API access to Home Assistant IP:

```bash
# In the LXC container
iptables -A INPUT -p tcp --dport 8080 -s <home-assistant-ip> -j ACCEPT
iptables -A INPUT -p tcp --dport 8080 -j DROP
```

#### Option 2: Reverse Proxy with Auth

Use nginx or Traefik with authentication.

#### Option 3: VPN/Private Network

Keep the LXC on a private network segment.

### VNC Access

For VNC security:

#### Enable Password

```bash
# In container
nano /root/.config/wayvnc/config
```

Add:
```
enable_auth=true
username=admin
password=yourpassword
```

#### Use SSH Tunnel

```bash
# From client
ssh -L 5900:localhost:5900 root@<proxmox-host>
# Then connect VNC to localhost:5900
```

## Troubleshooting

### API Not Responding

```bash
# Check service
systemctl status waydroid-api

# Check logs
journalctl -u waydroid-api -f

# Test locally
curl http://localhost:8080/status
```

### App Won't Launch

```bash
# Verify package name
waydroid app list

# Test manually
waydroid app launch com.example.app

# Check logs
logcat | grep -i error
```

### Intent Not Working

```bash
# List available intents for app
adb shell dumpsys package com.example.app | grep -i intent

# Test intent manually
waydroid app intent "android.intent.action.VIEW -d https://example.com"
```

## Example: Complete Gate Control Setup

### 1. Install Gate App

```bash
# In LXC container
waydroid app install gate-control.apk
```

### 2. Find Package Name

```bash
waydroid app list | grep gate
# Output: com.gatevendor.control
```

### 3. Home Assistant Configuration

```yaml
# configuration.yaml
rest_command:
  open_main_gate:
    url: "http://192.168.1.100:8080/app/launch"
    method: POST
    headers:
      Content-Type: "application/json"
    payload: '{"package": "com.gatevendor.control"}'

input_button:
  main_gate:
    name: "Main Gate"
    icon: mdi:gate

automation:
  - alias: "Open Main Gate"
    trigger:
      - platform: state
        entity_id: input_button.main_gate
        to: "on"
    action:
      - service: rest_command.open_main_gate
      - service: notify.mobile_app
        data:
          message: "Opening main gate"
```

### 4. Dashboard Card

```yaml
type: button
name: Main Gate
icon: mdi:gate
tap_action:
  action: call-service
  service: input_button.press
  target:
    entity_id: input_button.main_gate
```

## Resources

- [Home Assistant REST Command](https://www.home-assistant.io/integrations/rest_command/)
- [Android Intents](https://developer.android.com/guide/components/intents-filters)
- [ADB Commands](https://developer.android.com/studio/command-line/adb)
- [Waydroid Documentation](https://docs.waydro.id)
