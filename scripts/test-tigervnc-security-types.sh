#!/bin/bash
# Test TigerVNC connection with different security types
# Since you have TigerVNC, it supports VeNCrypt which neatvnc 0.5.4 requires

IP=10.1.3.136
PORT=5900

echo "========================================"
echo "Testing TigerVNC with Different Security Types"
echo "========================================"
echo ""
echo "Your VNC server (neatvnc 0.5.4) likely only offers VeNCrypt security types"
echo "TigerVNC supports these, so one of these should work:"
echo ""

echo "Test 1: Try VeNCrypt with X509Plain (type 262)"
echo "Command: vncviewer -SecurityTypes=X509Plain $IP:$PORT"
echo ""
read -p "Press Enter to try... (Ctrl+C to skip)"
vncviewer -SecurityTypes=X509Plain $IP:$PORT 2>&1 || true

echo ""
echo "Test 2: Try VeNCrypt with TLSNone"
echo "Command: vncviewer -SecurityTypes=TLSNone $IP:$PORT"
echo ""
read -p "Press Enter to try... (Ctrl+C to skip)"
vncviewer -SecurityTypes=TLSNone $IP:$PORT 2>&1 || true

echo ""
echo "Test 3: Try VeNCrypt base (type 19)"
echo "Command: vncviewer -SecurityTypes=VeNCrypt $IP:$PORT"
echo ""
read -p "Press Enter to try... (Ctrl+C to skip)"
vncviewer -SecurityTypes=VeNCrypt $IP:$PORT 2>&1 || true

echo ""
echo "Test 4: Try all VeNCrypt types"
echo "Command: vncviewer -SecurityTypes=X509Plain,X509Vnc,X509None,TLSPlain,TLSVnc,TLSNone,VeNCrypt $IP:$PORT"
echo ""
read -p "Press Enter to try... (Ctrl+C to skip)"
vncviewer -SecurityTypes=X509Plain,X509Vnc,X509None,TLSPlain,TLSVnc,TLSNone,VeNCrypt $IP:$PORT 2>&1 || true

echo ""
echo "Test 5: Try letting TigerVNC auto-negotiate"
echo "Command: vncviewer $IP:$PORT"
echo ""
read -p "Press Enter to try... (Ctrl+C to skip)"
vncviewer $IP:$PORT 2>&1 || true

echo ""
echo "========================================"
echo "If any test worked, that's your solution!"
echo "If none worked, you need to upgrade WayVNC"
echo "========================================"
