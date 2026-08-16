# Nexus + Wine Automation

Automation project for deploying Windows applications from a Nexus Repository to an Ubuntu Linux machine and running them through Wine.

The project provisions the required services and provides scripts for downloading, validating, and executing Windows applications stored in Nexus.

---

## Architecture

```text
                    Windows Host
                         |
          +--------------+--------------+
          |              |              |
         SSH           Browser          RDP
      localhost:2222 localhost:8081 localhost:3390
          |              |              |
          +--------------+--------------+
                         |
                         v
                  Ubuntu 22.04 VM
                         |
          +--------------+--------------+
          |                             |
          | Docker                      | XFCE Desktop
          |                             |
          | Nexus Repository            | xRDP
          |     |                       |
          |     |                       | Wine
          |     |                       |
          | windows-apps                | Windows Apps
          |     |
          |     +-- apps/
          |          |
          |          +-- 7zip/
          |               |
          |               +-- 7z2602-x64.exe
          |
          +--------------------------------
```

Application deployment flow:

```text
Upload Windows Application
          |
          v
Nexus Raw Repository
          |
          v
Download to Ubuntu
          |
          v
Validate Windows PE Executable
          |
          v
Execute with Wine
```

---

## Tested Environment

The current lab has been tested with:

* Ubuntu 22.04 LTS
* Docker Engine
* Docker Compose Plugin
* Nexus Repository Community Edition
* XFCE Desktop
* xRDP
* Wine 64-bit
* Wine 32-bit
* VirtualBox
* NAT networking

Recommended VM resources:

```text
CPU:    2 vCPU or more
RAM:    4 GB minimum
Disk:   25 GB minimum
```

For Nexus, XFCE, and Wine running together, 6 GB RAM and additional disk space are recommended.

---

# Project Structure

```text
/opt/automate/
├── .gitignore
├── README.md
│
├── config/
│   ├── automate.env
│   └── automate.env.example
│
├── docker/
│   └── nexus/
│       └── docker-compose.yml
│
├── downloads/
│
└── scripts/
    ├── bootstrap.sh
    ├── deploy-windows-app.sh
    └── health-check.sh
```

### Important

The following runtime files must **not** be committed to Git:

```text
config/automate.env
downloads/
*.exe
*.msi
```

The example configuration is safe to commit:

```text
config/automate.env.example
```

---

# Configuration

Copy the example configuration:

```bash
cd /opt/automate

cp config/automate.env.example \
   config/automate.env
```

Example configuration:

```ini
APP_USER=mobina

NEXUS_URL=http://localhost:8081
NEXUS_REPOSITORY=windows-apps

DOWNLOAD_DIR=/opt/automate/downloads
```

Change `APP_USER` to the Linux user that will use the graphical Wine environment.

For example:

```ini
APP_USER=ubuntu
```

or:

```ini
APP_USER=mobina
```

---

# Bootstrap

The bootstrap script prepares the Ubuntu machine.

It installs and configures:

* Required system packages
* Docker Engine
* Docker Compose
* Nexus Repository
* XFCE
* xRDP
* Wine 64-bit
* Wine 32-bit
* Application download directory

Run:

```bash
cd /opt/automate

sudo ./scripts/bootstrap.sh
```

The script must be executed as `root` or through `sudo`.

---

# Docker and Nexus

Nexus is deployed through Docker Compose.

Compose file:

```text
/opt/automate/docker/nexus/docker-compose.yml
```

Validate the Compose configuration:

```bash
cd /opt/automate/docker/nexus

docker compose config
```

Start Nexus:

```bash
docker compose up -d
```

Check the container:

```bash
docker ps
```

Example:

```text
CONTAINER ID   IMAGE                    STATUS       PORTS
xxxxxxxxxxxx   sonatype/nexus3:latest   Up           0.0.0.0:8081->8081/tcp
```

Check Nexus HTTP:

```bash
curl -I http://localhost:8081
```

Expected result:

```text
HTTP/1.1 200 OK
```

View Nexus logs:

```bash
docker logs -f nexus
```

---

# Nexus Initial Login

For a new Nexus installation, retrieve the initial admin password:

```bash
docker exec nexus cat /nexus-data/admin.password
```

Login with:

```text
Username:
admin

Password:
<output of admin.password>
```

After the first login, Nexus asks you to configure a new administrator password.

---

# Nexus Repository Configuration

Create a repository from the Nexus UI.

Navigate to:

```text
Settings
→ Repositories
→ Create repository
```

Select:

```text
raw (hosted)
```

Use:

```text
Name:
windows-apps
```

Recommended configuration:

```text
Online:
Enabled

Blob Store:
default

Deployment Policy:
Allow redeploy
```

Then create the repository.

---

# Uploading Applications

Windows application installers can be stored inside the Raw repository.

Example:

```text
7z2602-x64.exe
```

Recommended path:

```text
apps/7zip/7z2602-x64.exe
```

The resulting Nexus URL inside the Ubuntu VM is:

```text
http://localhost:8081/repository/windows-apps/apps/7zip/7z2602-x64.exe
```

Check that the application exists:

```bash
curl -I \
http://localhost:8081/repository/windows-apps/apps/7zip/7z2602-x64.exe
```

Expected:

```text
HTTP/1.1 200 OK
```

---

# Deploying a Windows Application

The deployment script downloads the requested application from Nexus and runs it using Wine.

Run this script from the **XFCE/xRDP graphical session**.

Example:

```bash
cd /opt/automate

./scripts/deploy-windows-app.sh \
  apps/7zip/7z2602-x64.exe
```

The script performs:

```text
Load configuration
        |
        v
Check required commands
        |
        v
Check application in Nexus
        |
        v
Download application
        |
        v
Validate Windows PE executable
        |
        v
Check Wine
        |
        v
Check graphical DISPLAY
        |
        v
Execute application with Wine
```

---

# Manual Download Test

Applications can also be downloaded manually.

Example:

```bash
wget \
http://localhost:8081/repository/windows-apps/apps/7zip/7z2602-x64.exe
```

Validate the downloaded file:

```bash
file 7z2602-x64.exe
```

Example output:

```text
PE32+ executable (GUI) x86-64, for MS Windows
```

This confirms that the downloaded file is a Windows executable.

---

# Running Applications with Wine

Wine must normally be executed by the graphical Linux user, not by `root`.

Check:

```bash
whoami
```

Example:

```text
mobina
```

Check the graphical display:

```bash
echo "$DISPLAY"
```

Example:

```text
:10.0
```

Check Wine:

```bash
wine --version
```

Initial Wine configuration:

```bash
winecfg
```

Run an application:

```bash
wine /opt/automate/downloads/7z2602-x64.exe
```

For 7-Zip, this should display the Windows installer inside the XFCE desktop.

---

# Wine Prefix

Wine creates a Windows-like filesystem for each Linux user.

Default location:

```text
~/.wine
```

For example:

```text
/home/mobina/.wine
```

The emulated Windows C drive is:

```text
/home/mobina/.wine/drive_c/
```

Example installed application:

```text
/home/mobina/.wine/drive_c/Program Files/7-Zip/
```

---

# XFCE and xRDP

XFCE provides the graphical Linux desktop.

xRDP allows connecting to this desktop from Windows Remote Desktop.

The user's session is configured through:

```text
~/.xsession
```

Expected content:

```bash
startxfce4
```

Check xRDP:

```bash
systemctl status xrdp
```

Check listening port:

```bash
ss -lntp | grep 3389
```

---

# VirtualBox NAT Port Forwarding

When using VirtualBox NAT networking, configure Port Forwarding.

## SSH

```text
Protocol:    TCP
Host IP:     127.0.0.1
Host Port:   2222
Guest Port:  22
```

Connect from Windows:

```bash
ssh mobina@127.0.0.1 -p 2222
```

---

## Nexus

```text
Protocol:    TCP
Host IP:     127.0.0.1
Host Port:   8081
Guest Port:  8081
```

Open from Windows:

```text
http://127.0.0.1:8081
```

---

## RDP

```text
Protocol:    TCP
Host IP:     127.0.0.1
Host Port:   3390
Guest Port:  3389
```

On Windows run:

```text
mstsc
```

Connect to:

```text
127.0.0.1:3390
```

Login with the Linux user configured in:

```text
config/automate.env
```

---

# Health Check

Run:

```bash
cd /opt/automate

sudo ./scripts/health-check.sh
```

The script checks:

```text
Docker
Nexus Container
Nexus HTTP
xRDP
Wine
Disk Usage
```

Expected output is similar to:

```text
[Docker]
OK - Docker is running

[Nexus Container]
OK - Nexus container is running

[Nexus HTTP]
OK - Nexus HTTP is responding

[xRDP]
OK - xRDP is running

[Wine]
wine-...

[Storage]
...
```

---

# Manual Service Checks

## Docker

```bash
systemctl status docker
```

```bash
docker ps
```

## Nexus

```bash
curl -I http://localhost:8081
```

```bash
docker logs nexus --tail=100
```

## xRDP

```bash
systemctl status xrdp
```

## Wine

```bash
wine --version
```

---

# Git

Initialize the repository:

```bash
cd /opt/automate

git init
git branch -m main
```

Before adding files:

```bash
git status
```

Verify ignored files:

```bash
git check-ignore -v config/automate.env
```

```bash
git check-ignore -v downloads/7z2602-x64.exe
```

These files should **not** be committed:

```text
config/automate.env
downloads/
*.exe
*.msi
```

Add project files:

```bash
git add .
```

Check carefully:

```bash
git status
```

Expected files:

```text
.gitignore
README.md
config/automate.env.example
docker/nexus/docker-compose.yml
scripts/bootstrap.sh
scripts/deploy-windows-app.sh
scripts/health-check.sh
```

Then commit:

```bash
git commit -m "Initial Nexus and Wine automation setup"
```

---

# `.gitignore`

Recommended `.gitignore`:

```gitignore
# Secrets / local configuration
config/automate.env

# Downloaded Windows applications
downloads/
*.exe
*.msi

# Logs
*.log
logs/

# Environment files
.env
*.env

# Keep example configuration
!config/automate.env.example

# Editors
.vscode/
.idea/

# OS files
.DS_Store
Thumbs.db

# Temporary files
*.tmp
*.swp
```

---

# Security

Never commit:

* Nexus administrator passwords
* Nexus user passwords
* API tokens
* Repository credentials
* `.env` files containing credentials
* Windows application binaries unless explicitly required
* Private certificates or private keys

Use:

```text
config/automate.env
```

for local configuration.

The file is excluded through `.gitignore`.

---

# Troubleshooting

## Nexus container is not running

Check:

```bash
docker ps -a
```

Then:

```bash
docker logs nexus --tail=100
```

---

## Nexus UI is not accessible from Windows

First test from Ubuntu:

```bash
curl -I http://localhost:8081
```

If this works, check VirtualBox Port Forwarding.

---

## SSH does not work through NAT

Check Ubuntu SSH:

```bash
systemctl status ssh
```

Check:

```bash
ss -lntp | grep ':22'
```

VirtualBox should forward:

```text
127.0.0.1:2222
        ↓
Guest:22
```

---

## Wine GUI does not open

Do not run GUI Wine applications from a root SSH session.

Check:

```bash
whoami
```

and:

```bash
echo "$DISPLAY"
```

`DISPLAY` must not be empty.

Run the application inside the XFCE/xRDP graphical session.

---

## `wine32` is missing

Verify i386 support:

```bash
dpkg --print-foreign-architectures
```

Expected:

```text
i386
```

Install:

```bash
sudo apt install wine32:i386
```

---

## Application returns 404 from Nexus

Verify the exact asset path in:

```text
Nexus
→ Browse
→ windows-apps
```

Then test the exact URL:

```bash
curl -I \
http://localhost:8081/repository/windows-apps/<asset-path>
```

---

# Current Example

The current lab has successfully tested the following workflow:

```text
7z2602-x64.exe
        |
        v
Nexus Raw Repository
windows-apps
        |
        v
apps/7zip/7z2602-x64.exe
        |
        v
Ubuntu download
        |
        v
Windows PE validation
        |
        v
Wine
        |
        v
7-Zip Windows Installer GUI
```

This confirms that the complete Nexus → Ubuntu → Wine application delivery path is working.

---

# Future Improvements

Possible next steps:

* Nexus authentication in deployment scripts
* Silent application installation
* Application version management
* Automatic update detection
* SHA256 checksum validation
* Application manifests
* Centralized logging
* Better health checks
* Docker image version pinning
* Nexus backup automation
* CI/CD integration
* GitLab CI integration
* Automated upload to Nexus
* Multi-application deployment
* Rollback support

