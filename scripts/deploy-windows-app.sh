#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${BASE_DIR}/config/automate.env"

# ==============================
# Load configuration
# ==============================

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: Config file not found:"
    echo "${CONFIG_FILE}"
    exit 1
fi

source "${CONFIG_FILE}"

# ==============================
# Arguments
# ==============================

APP_PATH="${1:-}"

if [[ -z "${APP_PATH}" ]]; then
    echo "Usage:"
    echo
    echo "  $0 apps/7zip/7z2602-x64.exe"
    echo
    exit 1
fi

APP_NAME="$(basename "${APP_PATH}")"

DOWNLOAD_URL="${NEXUS_URL}/repository/${NEXUS_REPOSITORY}/${APP_PATH}"

LOCAL_FILE="${DOWNLOAD_DIR}/${APP_NAME}"

echo
echo "========================================"
echo " Windows Application Deployment"
echo "========================================"
echo
echo "Application : ${APP_NAME}"
echo "Repository  : ${NEXUS_REPOSITORY}"
echo "Source      : ${DOWNLOAD_URL}"
echo "Destination : ${LOCAL_FILE}"
echo

# ==============================
# Requirements
# ==============================

for command in curl wget file wine; do

    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "ERROR: ${command} is not installed."
        exit 1
    fi

done

# ==============================
# Create Download Directory
# ==============================

mkdir -p "${DOWNLOAD_DIR}"

# ==============================
# Nexus availability
# ==============================

echo "[1/5] Checking Nexus..."

if ! curl -fsI "${DOWNLOAD_URL}" >/dev/null; then

    echo
    echo "ERROR: File not found in Nexus:"
    echo "${DOWNLOAD_URL}"
    exit 1

fi

echo "OK"

# ==============================
# Download
# ==============================

echo
echo "[2/5] Downloading application..."

wget \
    -q \
    --show-progress \
    -O "${LOCAL_FILE}" \
    "${DOWNLOAD_URL}"

# ==============================
# Validate
# ==============================

echo
echo "[3/5] Validating application..."

FILE_INFO="$(file "${LOCAL_FILE}")"

echo "${FILE_INFO}"

if ! echo "${FILE_INFO}" | grep -qi "PE32"; then

    echo
    echo "ERROR: Downloaded file is not a Windows PE executable."
    rm -f "${LOCAL_FILE}"
    exit 1

fi

# ==============================
# Wine
# ==============================

echo
echo "[4/5] Checking Wine..."

wine --version

# Wine GUI needs an active graphical session
if [[ -z "${DISPLAY:-}" ]]; then

    echo
    echo "ERROR: DISPLAY variable is empty."
    echo "Run this script from the XFCE/RDP graphical session."
    exit 1

fi

# ==============================
# Execute
# ==============================

echo
echo "[5/5] Running application with Wine..."
echo

wine "${LOCAL_FILE}"

echo
echo "Done."
