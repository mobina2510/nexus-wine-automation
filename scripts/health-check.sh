#!/usr/bin/env bash

set -u

echo "========================================"
echo " Automation Environment Health Check"
echo "========================================"

echo
echo "[Docker]"

if systemctl is-active --quiet docker; then
    echo "OK - Docker is running"
else
    echo "FAIL - Docker is not running"
fi


echo
echo "[Nexus Container]"

if docker ps --format '{{.Names}}' | grep -qx nexus; then
    echo "OK - Nexus container is running"
else
    echo "FAIL - Nexus container is not running"
fi


echo
echo "[Nexus HTTP]"

if curl -fs http://localhost:8081 >/dev/null 2>&1; then
    echo "OK - Nexus HTTP is responding"
else
    echo "FAIL - Nexus HTTP is not responding"
fi


echo
echo "[xRDP]"

if systemctl is-active --quiet xrdp; then
    echo "OK - xRDP is running"
else
    echo "FAIL - xRDP is not running"
fi


echo
echo "[Wine]"

if command -v wine >/dev/null 2>&1; then
    wine --version
else
    echo "FAIL - Wine is not installed"
fi


echo
echo "[Storage]"

df -h /
