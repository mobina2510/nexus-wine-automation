#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="/opt/automate"
CONFIG_FILE="${BASE_DIR}/config/automate.env"
NEXUS_DIR="${BASE_DIR}/docker/nexus"
NEXUS_PORT="8081"

echo "========================================"
echo " Nexus + XFCE + xRDP + Wine Bootstrap"
echo "========================================"

# =========================================================
# Root check
# =========================================================

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script as root."
    exit 1
fi

# =========================================================
# Configuration
# =========================================================

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: Config file not found:"
    echo "  ${CONFIG_FILE}"
    echo
    echo "Create it first:"
    echo "  cp ${BASE_DIR}/config/automate.env.example ${CONFIG_FILE}"
    exit 1
fi

# shellcheck disable=SC1090
source "${CONFIG_FILE}"

if [[ -z "${APP_USER:-}" ]]; then
    echo "ERROR: APP_USER is not defined in ${CONFIG_FILE}"
    exit 1
fi

if ! id "${APP_USER}" >/dev/null 2>&1; then
    echo "ERROR: Linux user '${APP_USER}' does not exist."
    exit 1
fi

APP_HOME="$(getent passwd "${APP_USER}" | cut -d: -f6)"

if [[ -z "${APP_HOME}" || ! -d "${APP_HOME}" ]]; then
    echo "ERROR: Home directory for '${APP_USER}' was not found."
    exit 1
fi

# =========================================================
# Ubuntu validation
# =========================================================

if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: /etc/os-release not found."
    exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID}" != "ubuntu" ]]; then
    echo "ERROR: This bootstrap script is designed for Ubuntu."
    exit 1
fi

echo
echo "Operating System:"
echo "  ${PRETTY_NAME}"

echo
echo "Application User:"
echo "  ${APP_USER}"

# =========================================================
# APT wrapper
# =========================================================

apt_cmd() {
    apt-get \
        -o DPkg::Lock::Timeout=300 \
        "$@"
}

export DEBIAN_FRONTEND=noninteractive

# =========================================================
# Step 1 - Prerequisites
# =========================================================

echo
echo "[1/8] Installing prerequisites..."

apt_cmd update

apt_cmd install -y \
    ca-certificates \
    curl \
    wget \
    file \
    gnupg \
    lsb-release \
    software-properties-common

# =========================================================
# Step 2 - Docker
# =========================================================

echo
echo "[2/8] Checking Docker..."

DOCKER_OK=false

if command -v docker >/dev/null 2>&1; then
    if systemctl list-unit-files docker.service >/dev/null 2>&1; then
        DOCKER_OK=true
    fi
fi

if [[ "${DOCKER_OK}" == "false" ]]; then

    echo "Docker Engine not found."
    echo "Installing Docker..."

    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL \
        https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc

    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
        > /etc/apt/sources.list.d/docker.list

    apt_cmd update

    apt_cmd install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

else
    echo "Docker is already installed."
fi

systemctl enable docker >/dev/null 2>&1 || true
systemctl start docker

if ! systemctl is-active --quiet docker; then
    echo "ERROR: Docker service failed to start."
    exit 1
fi

echo
docker --version
docker compose version

# =========================================================
# Step 3 - Nexus
# =========================================================

echo
echo "[3/8] Starting Nexus..."

if [[ ! -d "${NEXUS_DIR}" ]]; then
    echo "ERROR: Nexus directory not found:"
    echo "  ${NEXUS_DIR}"
    exit 1
fi

if [[ ! -f "${NEXUS_DIR}/docker-compose.yml" ]]; then
    echo "ERROR: docker-compose.yml not found:"
    echo "  ${NEXUS_DIR}/docker-compose.yml"
    exit 1
fi

cd "${NEXUS_DIR}"

echo "Validating Docker Compose..."

docker compose config >/dev/null

echo "Starting Nexus container..."

docker compose pull
docker compose up -d

echo
echo "Waiting for Nexus..."

NEXUS_READY=false

for i in $(seq 1 60); do

    if curl \
        --silent \
        --fail \
        --max-time 5 \
        "http://localhost:${NEXUS_PORT}" \
        >/dev/null 2>&1
    then
        NEXUS_READY=true
        echo "Nexus is ready."
        break
    fi

    echo "Waiting for Nexus... ${i}/60"
    sleep 5

done

if [[ "${NEXUS_READY}" != "true" ]]; then

    echo
    echo "ERROR: Nexus did not become ready."

    docker compose ps || true

    echo
    echo "Last Nexus logs:"

    docker compose logs --tail=100 nexus || true

    exit 1
fi

# =========================================================
# Step 4 - XFCE
# =========================================================

echo
echo "[4/8] Installing XFCE..."

apt_cmd install -y \
    xfce4 \
    xfce4-goodies

# =========================================================
# Step 5 - xRDP
# =========================================================

echo
echo "[5/8] Installing xRDP..."

apt_cmd install -y xrdp

systemctl enable xrdp >/dev/null 2>&1 || true
systemctl start xrdp

if ! systemctl is-active --quiet xrdp; then
    echo "ERROR: xRDP failed to start."
    exit 1
fi

adduser xrdp ssl-cert >/dev/null 2>&1 || true

XSESSION_FILE="${APP_HOME}/.xsession"

if [[ ! -f "${XSESSION_FILE}" ]] || \
   ! grep -qx "startxfce4" "${XSESSION_FILE}" 2>/dev/null
then
    echo "startxfce4" > "${XSESSION_FILE}"
fi

chown "${APP_USER}:${APP_USER}" "${XSESSION_FILE}"

# =========================================================
# Step 6 - Wine
# =========================================================

echo
echo "[6/8] Installing Wine..."

if ! dpkg --print-foreign-architectures | grep -qx i386; then
    echo "Enabling i386 architecture..."
    dpkg --add-architecture i386
fi

add-apt-repository -y universe >/dev/null 2>&1 || true

apt_cmd update

apt_cmd install -y \
    wine64 \
    wine32:i386

echo
echo "Wine version:"
sudo -u "${APP_USER}" wine --version || true

# =========================================================
# Step 7 - Runtime directories
# =========================================================

echo
echo "[7/8] Preparing runtime directories..."

mkdir -p "${BASE_DIR}/downloads"

chown -R "${APP_USER}:${APP_USER}" \
    "${BASE_DIR}/downloads"

# =========================================================
# Step 8 - Health checks
# =========================================================

echo
echo "[8/8] Running final checks..."

FAILED=0

echo
echo "Docker:"

if systemctl is-active --quiet docker; then
    echo "  OK"
else
    echo "  FAIL"
    FAILED=1
fi

echo
echo "Nexus Container:"

if docker ps \
    --format '{{.Names}}' \
    | grep -qx nexus
then
    echo "  OK"
else
    echo "  FAIL"
    FAILED=1
fi

echo
echo "Nexus HTTP:"

if curl \
    --silent \
    --fail \
    --max-time 5 \
    "http://localhost:${NEXUS_PORT}" \
    >/dev/null
then
    echo "  OK"
else
    echo "  FAIL"
    FAILED=1
fi

echo
echo "xRDP:"

if systemctl is-active --quiet xrdp; then
    echo "  OK"
else
    echo "  FAIL"
    FAILED=1
fi

echo
echo "Wine:"

if command -v wine >/dev/null 2>&1; then
    echo "  $(sudo -u "${APP_USER}" wine --version 2>/dev/null || echo "installed")"
else
    echo "  FAIL"
    FAILED=1
fi

echo
echo "Disk:"
df -h /

echo
echo "========================================"

if [[ "${FAILED}" -eq 0 ]]; then
    echo " Bootstrap completed successfully"
else
    echo " Bootstrap completed with errors"
    exit 1
fi

echo "========================================"

echo
echo "Nexus:"
echo "  http://localhost:${NEXUS_PORT}"

echo
echo "VirtualBox NAT Port Forwarding:"
echo
echo "  SSH"
echo "    Host: 127.0.0.1:2222"
echo "    Guest: :22"
echo
echo "  Nexus"
echo "    Host: 127.0.0.1:8081"
echo "    Guest: :8081"
echo
echo "  RDP"
echo "    Host: 127.0.0.1:3390"
echo "    Guest: :3389"

echo
echo "Next:"
echo "  1. Configure VirtualBox port forwarding."
echo "  2. Open Nexus UI."
echo "  3. Create the 'windows-apps' Raw Hosted repository."
echo "  4. Connect to XFCE through RDP."
echo "  5. Run deploy-windows-app.sh from the graphical session."
