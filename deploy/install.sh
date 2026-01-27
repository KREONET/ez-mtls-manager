#!/bin/sh

# ==============================================================================
# EZ-mTLS Manager Installation Script
#
# This script configures the environment for deploying EZ-mTLS Manager on Ubuntu 24.04 LTS.
# Root privileges (sudo) are required before execution.
# ==============================================================================

set -e

# Color Codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

printf "${GREEN}=== Starting EZ-mTLS Manager Installation ===${NC}\n"

# 2. Environment Check (OS & Prerequisites)
printf "${YELLOW}[1/7] Checking environment compatibility...${NC}\n"

# 2-1. Check OS Version (Ubuntu 24.04 or higher)
if [ -f /etc/os-release ]; then
    . /etc/os-release
    # Extract major version (e.g., 24.04 -> 24)
    MAJOR_VER=$(echo "$VERSION_ID" | cut -d. -f1)

    if [ "$NAME" != "Ubuntu" ] || [ -z "$MAJOR_VER" ] || [ "$MAJOR_VER" -lt 24 ]; then
        printf "${RED}[Error] This script only works on Ubuntu 24.04 LTS or higher.${NC}\n"
        printf "Detected environment: $PRETTY_NAME\n"
        exit 1
    fi
else
    printf "${RED}[Error] /etc/os-release file not found.${NC}\n"
    exit 1
fi

# 2-2. Check Nginx & Certbot Installation
if ! command -v nginx > /dev/null 2>&1 || ! command -v certbot > /dev/null 2>&1; then
    printf "${RED}[Error] Nginx and Certbot are not installed.${NC}\n"
    printf "${YELLOW}Please install the web server and SSL tools first with the following commands:${NC}\n"
    printf "  sudo apt update\n"
    printf "  sudo apt install -y nginx python3-certbot-nginx\n"
    printf "  # (Optional) If domain is ready, proceed with SSL issuance:\n"
    printf "  # sudo certbot --nginx\n"
    exit 1
fi

printf "${GREEN}Environment check complete.${NC}\n"

INSTALL_DIR="/opt/ez-mtls-manager"
REPO_URL="https://github.com/kreonet/ez-mtls-manager.git"

# APT Update Function (Skip if within 7 days)
update_apt_if_needed() {
    if [ -z "$(find /var/cache/apt/pkgcache.bin -mtime -7 2>/dev/null)" ]; then
        printf "${YELLOW}Updating APT cache...${NC}\n"
        apt update
    else
        echo "APT cache is up to date (within 7 days). Skipping update."
    fi
}

# Check for local settings file (before directory change)
LOCAL_SETTINGS_SRC=""
if [ -f "$(pwd)/settings.py" ]; then
    LOCAL_SETTINGS_SRC="$(pwd)/settings.py"
    printf "${GREEN}Found settings.py in current directory. Using it as configuration file for EZmTLS Manager installation.${NC}\n"
fi

# Check for local password file
LOCAL_STEP_CA_PASSWORD_FILE=""
if [ -f "$(pwd)/password.txt" ]; then
    LOCAL_STEP_CA_PASSWORD_FILE="$(pwd)/password.txt"
    printf "${GREEN}Found password.txt in current directory. Using it as STEP_CA_PASSWORD_FILE during installation.${NC}\n"
fi

# Pre-read existing settings (if settings.py exists)
DEFAULT_CA_NAME="EZmTLS"
DEFAULT_VALID_DAYS=90

if [ -n "$LOCAL_SETTINGS_SRC" ]; then
    # Add current directory to pythonpath for import
    DETECTED_CA_NAME=$(python3 -c "import sys; sys.path.append('$(pwd)'); import settings; print(getattr(settings, 'STEP_CA_NAME', ''))" 2>/dev/null)
    DETECTED_VALID_HOURS=$(python3 -c "import sys; sys.path.append('$(pwd)'); import settings; print(getattr(settings, 'STEP_CERT_VALID_HOURS', 0))" 2>/dev/null)
    
    if [ -n "$DETECTED_CA_NAME" ]; then
        printf "Detected CA Name from settings file: ${GREEN}$DETECTED_CA_NAME${NC}\n"
        DEFAULT_CA_NAME="$DETECTED_CA_NAME"
    fi
    
    if [ "$DETECTED_VALID_HOURS" -gt 0 ]; then
        DETECTED_DAYS=$((DETECTED_VALID_HOURS / 24))
        printf "Detected Certificate Validity from settings file: ${GREEN}${DETECTED_DAYS} days${NC}\n"
        DEFAULT_VALID_DAYS=$DETECTED_DAYS
    fi
fi

# Clone or move if current directory is not install path
if [ "$(pwd)" != "$INSTALL_DIR" ]; then
    printf "${YELLOW}=== Checking installation path ($INSTALL_DIR)... ===${NC}\n"
    
    # Check git installation
    if ! command -v git > /dev/null 2>&1; then
        printf "${YELLOW}Installing Git...${NC}\n"
        update_apt_if_needed
        apt install -y git
    fi

    if [ ! -d "$INSTALL_DIR" ]; then
        printf "${YELLOW}Cloning repository... ($REPO_URL)${NC}\n"
        git clone "$REPO_URL" "$INSTALL_DIR"
    else
        printf "${GREEN}Installation directory already exists. Moving to path.${NC}\n"
    fi
    
    cd "$INSTALL_DIR"
fi

# 3. User Input
printf "${YELLOW}[2/9] User Input Required${NC}\n"


# 3-1. Input CA Name
if [ -n "$STEP_CA_NAME" ]; then
    printf "Environment variable STEP_CA_NAME detected: ${GREEN}$STEP_CA_NAME${NC}\n"
else
    printf "Enter Step CA Name (Press Enter to use default '$DEFAULT_CA_NAME'): "
    read USER_STEP_CA_NAME
    if [ -z "$USER_STEP_CA_NAME" ]; then
        export STEP_CA_NAME="$DEFAULT_CA_NAME"
    else
        export STEP_CA_NAME="$USER_STEP_CA_NAME"
    fi
fi

# 3-2. Input Certificate Validity (7~365 days)
while true; do
    printf "Enter Certificate Validity in days (7~365, Press Enter to use default ${DEFAULT_VALID_DAYS} days): "
    read USER_VALID_DAYS
    
    if [ -z "$USER_VALID_DAYS" ]; then
        VALID_DAYS=$DEFAULT_VALID_DAYS
        break
    fi
    
    # POSIX compatible number check
    is_valid_number=0
    case "$USER_VALID_DAYS" in
        ""|*[!0-9]*) is_valid_number=0 ;;
        *) is_valid_number=1 ;;
    esac

    if [ "$is_valid_number" -eq 1 ] && [ "$USER_VALID_DAYS" -ge 7 ] && [ "$USER_VALID_DAYS" -le 365 ]; then
        VALID_DAYS=$USER_VALID_DAYS
        break
    else
        printf "${RED}[Error] Please enter a number between 7 and 365.${NC}\n"
    fi
done

# Convert days to hours
CERT_VALID_HOURS=$((VALID_DAYS * 24))
printf "Certificate Validity will be set to ${GREEN}${VALID_DAYS} days (${CERT_VALID_HOURS} hours)${NC}.\n"


# 4. Install Essential Packages
printf "${YELLOW}[3/9] Updating and installing system packages...${NC}\n"
update_apt_if_needed
apt install -y curl vim git gpg ca-certificates libssl-dev

# 5. Install SmallStep CA
printf "${YELLOW}[4/9] Installing SmallStep CA...${NC}\n"
if ! command -v step > /dev/null 2>&1; then
    curl -fsSL https://packages.smallstep.com/keys/apt/repo-signing-key.gpg -o /etc/apt/trusted.gpg.d/smallstep.asc
    echo 'deb [signed-by=/etc/apt/trusted.gpg.d/smallstep.asc] https://packages.smallstep.com/stable/debian debs main' | tee /etc/apt/sources.list.d/smallstep.list
    apt update
    apt install -y step-cli step-ca
else
    echo "SmallStep CA is already installed."
fi

# 6. Prepare Configuration File
printf "${YELLOW}[5/9] Preparing configuration file (settings.py)...${NC}\n"

# 6-1. Secure settings.py
if [ -n "$LOCAL_SETTINGS_SRC" ] && [ -f "$LOCAL_SETTINGS_SRC" ]; then
    printf "${GREEN}Using detected local settings file: $LOCAL_SETTINGS_SRC${NC}\n"
    cp "$LOCAL_SETTINGS_SRC" "$INSTALL_DIR/settings.py"
elif [ -f "$INSTALL_DIR/settings.py.example" ]; then
    echo "Generating settings.py from default example."
    cp "$INSTALL_DIR/settings.py.example" "$INSTALL_DIR/settings.py"
else
    printf "${RED}[Warning] settings.py.example file not found.${NC}\n"
fi

# 6-2. Handle DB Password
# Read DB_PASSWORD from current file
CURRENT_DB_PASS=$(python3 -c "import sys; sys.path.append('$INSTALL_DIR'); import settings; print(getattr(settings, 'DB_PASSWORD', ''))" 2>/dev/null)

is_default_db_pass=0
case "$CURRENT_DB_PASS" in
    CHANGE_ME*) is_default_db_pass=1 ;;
esac

if [ -z "$CURRENT_DB_PASS" ] || [ "$is_default_db_pass" -eq 1 ]; then
    echo "Generating new DB password."
    DB_PASS=$(openssl rand -hex 12)
    sed -i "s/DB_PASSWORD = .*/DB_PASSWORD = \"${DB_PASS}\"/" "$INSTALL_DIR/settings.py"
else
    echo "Keeping existing DB password."
    DB_PASS="$CURRENT_DB_PASS"
fi

# 6-3. Handle Secret Key
# Read FLASK_SECRET_KEY from current file
CURRENT_FLASK_SECRET_KEY=$(python3 -c "import sys; sys.path.append('$INSTALL_DIR'); import settings; print(getattr(settings, 'FLASK_SECRET_KEY', ''))" 2>/dev/null)

is_default_secret_key=0
case "$CURRENT_FLASK_SECRET_KEY" in
    CHANGE_ME*) is_default_secret_key=1 ;;
esac

if [ -z "$CURRENT_FLASK_SECRET_KEY" ] || [ "$is_default_secret_key" -eq 1 ]; then
    echo "Generating new Flask Secret Key."
    NEW_SECRET_KEY=$(openssl rand -hex 32)
    # Replace if exists, append if not
    if grep -q "FLASK_SECRET_KEY =" "$INSTALL_DIR/settings.py"; then
        sed -i "s/FLASK_SECRET_KEY = .*/FLASK_SECRET_KEY = \"${NEW_SECRET_KEY}\"/" "$INSTALL_DIR/settings.py"
    else
        echo "FLASK_SECRET_KEY = \"${NEW_SECRET_KEY}\"" >> "$INSTALL_DIR/settings.py"
    fi
fi

# 6-4. Update Validity and CA Name Settings (Common)
if [ -f "$INSTALL_DIR/settings.py" ]; then
    sed -i "s/^CERT_VALID_HOURS = .*/CERT_VALID_HOURS = ${CERT_VALID_HOURS}/" "$INSTALL_DIR/settings.py"
    sed -i "s/^STEP_CA_NAME = .*/STEP_CA_NAME = \"${STEP_CA_NAME}\"/" "$INSTALL_DIR/settings.py"
fi


# 7. Install and Initialize Database
printf "${YELLOW}[6/9] Installing and initializing Database (MariaDB)...${NC}\n"
apt install -y mariadb-server

# 7-1. Setup DB User and Security
echo "Configuring database user (ezmtls)."
# Create user (if not exists)
sudo mariadb -e "CREATE USER IF NOT EXISTS 'ezmtls'@'localhost' IDENTIFIED BY '${DB_PASS}';" >/dev/null 2>&1
# Sync password (ensure it matches settings.py even if user exists)
sudo mariadb -e "ALTER USER 'ezmtls'@'localhost' IDENTIFIED BY '${DB_PASS}';" >/dev/null 2>&1
# Grant privileges
sudo mariadb -e "GRANT ALL PRIVILEGES ON \`ezmtls\`.* TO 'ezmtls'@'localhost';" >/dev/null 2>&1
sudo mariadb -e "FLUSH PRIVILEGES;" >/dev/null 2>&1

# 7-2. Apply DB Schema
if [ -f "$INSTALL_DIR/init_db.sql" ]; then
    sudo mariadb < "$INSTALL_DIR/init_db.sql"
    echo "Database schema applied."
else
        printf "${RED}[Warning] init_db.sql not found, skipping DB initialization.${NC}\n"
fi

# 8. Install Python and App Dependencies
printf "${YELLOW}[7/9] Installing Python packages...${NC}\n"
apt install -y python3-flask python3-flask-login python3-flask-sqlalchemy \
               python3-pymysql python3-flaskext.wtf python3-authlib \
               python3-dotenv python3-requests python3-cryptography \
               gunicorn python3-gunicorn

# 8. Create Service Account
printf "${YELLOW}[7/9] Creating service account (flask)...${NC}\n"
if id "flask" > /dev/null 2>&1; then
    echo "flask account already exists."
else
    useradd -m -s /bin/bash flask
    echo "flask account created."
fi

# 9. Initialize Step CA
printf "${YELLOW}[8/9] Initializing and Configuring Step CA${NC}\n"

CA_DIR="/opt/ez-mtls-manager/step-ca"
STEP_CA_PASSWORD_FILE="$CA_DIR/password.txt"
SVC_USER="flask"
SVC_GROUP="flask"

echo "=== Starting Step CA Initialization ($CA_DIR) ==="

# 9-1. Create Directory
if [ -d "$CA_DIR" ]; then
    echo "Directory $CA_DIR already exists. Skipping creation."
else
    mkdir -p "$CA_DIR"
    echo "Created directory $CA_DIR."
fi

# 9-2. Create Password File
if [ -f "$STEP_CA_PASSWORD_FILE" ]; then
    echo "Password file already exists."
elif [ -n "$LOCAL_STEP_CA_PASSWORD_FILE" ] && [ -f "$LOCAL_STEP_CA_PASSWORD_FILE" ]; then
    echo "Copying detected local password file: $LOCAL_STEP_CA_PASSWORD_FILE"
    cp "$LOCAL_STEP_CA_PASSWORD_FILE" "$STEP_CA_PASSWORD_FILE"
    chmod 600 "$STEP_CA_PASSWORD_FILE"
else
    echo "Generating new password..."
    openssl rand -base64 32 > "$STEP_CA_PASSWORD_FILE"
    chmod 600 "$STEP_CA_PASSWORD_FILE"
fi

# 9-3. Init CA
if [ -f "$CA_DIR/config/ca.json" ]; then
    echo "CA seems already initialized (ca.json exists). Skipping initialization."
else
    echo "Running 'step ca init'..."
    
    HOSTNAME=$(hostname -f)
    export STEPPATH="$CA_DIR"
    
    step ca init \
        --name "$STEP_CA_NAME" \
        --dns "localhost" \
        --dns "$HOSTNAME" \
        --address ":8443" \
        --provisioner "admin" \
        --password-file "$STEP_CA_PASSWORD_FILE" \
        --provisioner-password-file "$STEP_CA_PASSWORD_FILE" \
        --deployment-type standalone
        
    echo "CA Initialization complete."
    
    # 9-4. Patch ca.json (Certificate Validity)
    echo "Patching ca.json (Setting certificate validity)..."
    # Export env var for Python script
    export PY_CERT_VALID_HOURS="${CERT_VALID_HOURS}h"
    
    python3 -c '
import json
import os

config_path = "/opt/ez-mtls-manager/step-ca/config/ca.json"
cert_duration = os.environ.get("PY_CERT_VALID_HOURS", "2160h")
default_duration = "720h" # Default 30 days

if os.path.exists(config_path):
    with open(config_path, "r") as f:
        data = json.load(f)
    
    updated = False

    # 1. Enable CRL
    if "crl" not in data:
        data["crl"] = {"enabled": True, "generateOnRevoke": True}
        updated = True
    elif not data["crl"].get("enabled"):
        data["crl"]["enabled"] = True
        data["crl"]["generateOnRevoke"] = True
        updated = True

    # 2. Find admin provisioner and add claims
    if "authority" in data and "provisioners" in data["authority"]:
        for prov in data["authority"]["provisioners"]:
            if prov["name"] == "admin":
                prov["claims"] = {
                    "enableSSHCA": True,
                    "maxTLSCertDuration": cert_duration,
                    "defaultTLSCertDuration": default_duration
                }
                updated = True
    
    if updated:
        with open(config_path, "w") as f:
            json.dump(data, f, indent=4)
        print(f"Successfully updated ca.json (CRL Enabled, Duration: {cert_duration})")
    else:
        print("No changes needed for ca.json.")
'
fi

# 9-5. Set Permissions
echo "Setting permissions ($SVC_USER:$SVC_GROUP)..."
mkdir -p "$INSTALL_DIR/certs"
touch "$INSTALL_DIR/app.log"

# App permissions
chown -R $SVC_USER:$SVC_GROUP "$INSTALL_DIR/certs"
chown -R $SVC_USER:$SVC_GROUP "$INSTALL_DIR/app.log"

# Step CA permissions (Required for service to run as flask user)
chown -R $SVC_USER:$SVC_GROUP "$CA_DIR"

# Secure settings.py (root owner, flask group read-only)
if [ -f "$INSTALL_DIR/settings.py" ]; then
    chown root:$SVC_GROUP "$INSTALL_DIR/settings.py"
    chmod 640 "$INSTALL_DIR/settings.py"
fi

# 10. Register and Start Service
printf "${YELLOW}[9/9] Registering and Starting Service...${NC}\n"
cp deploy/ez-mtls.service /etc/systemd/system/
cp deploy/step-ca.service /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now step-ca
systemctl enable --now ez-mtls

printf "${GREEN}=== Installation Complete! ===${NC}\n"
printf "
Next Steps:
1. ${YELLOW}Review Configuration${NC}: Check '/opt/ez-mtls-manager/settings.py'
2. ${YELLOW}Nginx Setup${NC}: Add config to '/etc/nginx/sites-available/' referring to 'deploy/nginx.conf.example'
   (Use existing Nginx and Certbot to connect your domain.)

Check Service Status:
systemctl status step-ca
systemctl status ez-mtls
\n"
