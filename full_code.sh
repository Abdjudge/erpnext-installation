#!/bin/bash

# =============================================================================
# ERPNext v15 Complete Fresh Installation Script
# With improved MariaDB handling and error recovery
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

FRAPPE_USER="frappe"
FRAPPE_VERSION="version-15"
ERPNEXT_VERSION="version-15"
BENCH_PATH="/home/${FRAPPE_USER}/frappe-bench"

# Error handler
error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    error_exit "Please run as root (use sudo)"
fi

# =============================================================================
# Install whiptail
# =============================================================================
if ! command -v whiptail &> /dev/null; then
    echo -e "${YELLOW}Installing whiptail...${NC}"
    apt-get update -y
    apt-get install -y whiptail
fi

# =============================================================================
# Check and Remove Existing Installation
# =============================================================================

EXISTING_INSTALL=false

if [ -d "$BENCH_PATH" ] || id "$FRAPPE_USER" &>/dev/null 2>&1 || \
   [ -f "/etc/nginx/conf.d/frappe-bench.conf" ] || \
   [ -f "/etc/supervisor/conf.d/frappe-bench.conf" ]; then
    EXISTING_INSTALL=true
fi

if [ "$EXISTING_INSTALL" = true ]; then
    if whiptail --title "Existing Installation Detected" --yesno "An existing ERPNext/Frappe installation was detected!\n\nThis script will COMPLETELY REMOVE:\n• Bench directory\n• All sites and databases\n• Frappe user\n• All configurations\n\n⚠️  ALL DATA WILL BE LOST! ⚠️\n\nProceed with fresh installation?" 18 65; then
        
        if whiptail --title "FINAL WARNING" --yesno "⚠️  LAST CHANCE! ⚠️\n\nYou are about to DELETE ALL ERPNext data!\n\nThis action CANNOT be undone!\n\nAre you absolutely sure?" 14 50; then
            
            echo -e "${RED}========================================${NC}"
            echo -e "${RED}  Removing Existing Installation${NC}"
            echo -e "${RED}========================================${NC}"
            
            # Stop services
            supervisorctl stop all 2>/dev/null || true
            systemctl stop nginx 2>/dev/null || true
            
            # Remove configs
            rm -f /etc/supervisor/conf.d/frappe-bench.conf 2>/dev/null || true
            rm -f /etc/supervisor/conf.d/frappe*.conf 2>/dev/null || true
            rm -f /etc/nginx/conf.d/frappe-bench.conf 2>/dev/null || true
            rm -f /etc/nginx/conf.d/frappe*.conf 2>/dev/null || true
            rm -f /etc/nginx/sites-enabled/frappe* 2>/dev/null || true
            rm -f /etc/nginx/sites-available/frappe* 2>/dev/null || true
            
            supervisorctl reread 2>/dev/null || true
            supervisorctl update 2>/dev/null || true
            
            # Remove bench
            rm -rf $BENCH_PATH 2>/dev/null || true
            rm -rf /home/$FRAPPE_USER/frappe* 2>/dev/null || true
            
            # Remove user
            pkill -u $FRAPPE_USER 2>/dev/null || true
            sleep 2
            sed -i "/$FRAPPE_USER/d" /etc/sudoers 2>/dev/null || true
            userdel -r $FRAPPE_USER 2>/dev/null || true
            rm -rf /home/$FRAPPE_USER 2>/dev/null || true
            
            # Clean up
            rm -rf /tmp/frappe* 2>/dev/null || true
            
            echo -e "${GREEN}Existing installation removed!${NC}"
            sleep 2
        else
            exit 0
        fi
    else
        exit 0
    fi
fi

# =============================================================================
# Welcome & User Input
# =============================================================================

whiptail --title "ERPNext v15 Fresh Installation" --msgbox "Welcome to ERPNext v15 Fresh Installation!\n\nThis script will install:\n• All dependencies\n• MariaDB, Redis, Node.js 18\n• Frappe Framework v15\n• ERPNext v15\n• Production environment\n• SSL (optional)\n\nPress OK to continue." 18 60

# Get Site Name
SITE_NAME=$(whiptail --title "Site Configuration" --inputbox "Enter your site name / domain:\n\n(e.g., erp.yourdomain.com)" 12 60 "erp.example.com" 3>&1 1>&2 2>&3)
[ -z "$SITE_NAME" ] && error_exit "Site name cannot be empty"

# Get Admin Password
ADMIN_PASSWORD=$(whiptail --title "Admin Password" --passwordbox "Enter admin password for ERPNext:\n\n(Minimum 8 characters)" 12 60 3>&1 1>&2 2>&3)
[ -z "$ADMIN_PASSWORD" ] || [ ${#ADMIN_PASSWORD} -lt 8 ] && error_exit "Password must be at least 8 characters"

# Confirm Password
ADMIN_PASSWORD_CONFIRM=$(whiptail --title "Confirm Password" --passwordbox "Confirm admin password:" 10 60 3>&1 1>&2 2>&3)
[ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ] && error_exit "Passwords do not match"

# SSL Configuration
if whiptail --title "SSL Configuration" --yesno "Setup SSL with Let's Encrypt?\n\nRequirements:\n• Domain must point to this server\n• Ports 80/443 must be open" 12 60; then
    SETUP_SSL="y"
    SSL_EMAIL=$(whiptail --title "SSL Email" --inputbox "Enter email for SSL certificate:" 10 60 3>&1 1>&2 2>&3)
    [ -z "$SSL_EMAIL" ] && error_exit "Email required for SSL"
else
    SETUP_SSL="n"
    SSL_EMAIL=""
fi

# Generate MySQL password
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 20)

# Confirmation
SUMMARY="Site: $SITE_NAME\nSSL: $SETUP_SSL"
whiptail --title "Confirm" --yesno "$SUMMARY\n\nProceed?" 10 50 || exit 0

# =============================================================================
# START INSTALLATION
# =============================================================================

clear
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          ERPNext v15 Fresh Installation Starting                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# [1/15] Update System
# =============================================================================
echo -e "${YELLOW}[1/15] Updating system...${NC}"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# =============================================================================
# [2/15] Install Dependencies
# =============================================================================
echo -e "${YELLOW}[2/15] Installing dependencies...${NC}"
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git python3-dev python3-pip python3-setuptools python3-venv \
    software-properties-common redis-server xvfb libfontconfig \
    wkhtmltopdf libmysqlclient-dev curl wget supervisor nginx \
    fontconfig libxrender1 xfonts-75dpi xfonts-base snapd cron ufw openssl

# =============================================================================
# [3/15] Install Node.js 18
# =============================================================================
echo -e "${YELLOW}[3/15] Installing Node.js 18...${NC}"
apt-get remove -y nodejs npm 2>/dev/null || true
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs
npm install -g yarn

# =============================================================================
# [4/15] Install MariaDB (WITH IMPROVED HANDLING)
# =============================================================================
echo -e "${YELLOW}[4/15] Installing MariaDB...${NC}"

# First, completely clean any existing MariaDB
systemctl stop mariadb 2>/dev/null || true
systemctl stop mysql 2>/dev/null || true
pkill -9 mysqld 2>/dev/null || true
pkill -9 mariadbd 2>/dev/null || true
sleep 2

# Remove any existing installation that might be corrupted
apt-get remove --purge -y mariadb-server mariadb-client mariadb-common 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true

# Clean up directories
rm -rf /var/lib/mysql 2>/dev/null || true
rm -rf /var/log/mysql 2>/dev/null || true
rm -rf /var/run/mysqld 2>/dev/null || true
rm -rf /run/mysqld 2>/dev/null || true
rm -f /etc/mysql/mariadb.conf.d/99-frappe.cnf 2>/dev/null || true

# Fresh install
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server mariadb-client

# Create required directories
mkdir -p /var/run/mysqld
mkdir -p /run/mysqld
chown mysql:mysql /var/run/mysqld
chown mysql:mysql /run/mysqld
chmod 755 /var/run/mysqld
chmod 755 /run/mysqld

# =============================================================================
# [5/15] Configure MariaDB
# =============================================================================
echo -e "${YELLOW}[5/15] Configuring MariaDB...${NC}"

# Start MariaDB
systemctl start mariadb
sleep 3

# Check if started
if ! systemctl is-active --quiet mariadb; then
    echo -e "${RED}MariaDB failed to start. Checking logs...${NC}"
    journalctl -xeu mariadb.service | tail -20
    
    # Try one more time
    rm -rf /var/run/mysqld/*
    mkdir -p /var/run/mysqld
    chown mysql:mysql /var/run/mysqld
    systemctl start mariadb
    sleep 3
    
    if ! systemctl is-active --quiet mariadb; then
        error_exit "MariaDB failed to start. Please check: journalctl -xeu mariadb.service"
    fi
fi

systemctl enable mariadb
echo -e "${GREEN}  -> MariaDB is running${NC}"

# Secure MariaDB
echo -e "${BLUE}  -> Securing MariaDB...${NC}"
mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

# Create Frappe config
cat > /etc/mysql/mariadb.conf.d/99-frappe.cnf <<EOF
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOF

systemctl restart mariadb
sleep 2

# Verify MariaDB is working with password
if mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" &>/dev/null; then
    echo -e "${GREEN}  -> MariaDB configured successfully!${NC}"
else
    error_exit "MariaDB password configuration failed"
fi

# =============================================================================
# [6/15] Configure Redis
# =============================================================================
echo -e "${YELLOW}[6/15] Configuring Redis...${NC}"
systemctl start redis-server
systemctl enable redis-server

# =============================================================================
# [7/15] Create Frappe User
# =============================================================================
echo -e "${YELLOW}[7/15] Creating Frappe user...${NC}"
if ! id -u $FRAPPE_USER > /dev/null 2>&1; then
    useradd -m -s /bin/bash $FRAPPE_USER
fi
usermod -aG sudo $FRAPPE_USER
grep -q "^$FRAPPE_USER ALL=(ALL) NOPASSWD:ALL" /etc/sudoers || \
    echo "$FRAPPE_USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# =============================================================================
# [8/15] Install Bench
# =============================================================================
echo -e "${YELLOW}[8/15] Installing Bench...${NC}"
pip3 install frappe-bench --break-system-packages 2>/dev/null || pip3 install frappe-bench

# =============================================================================
# [9/15] Initialize Bench
# =============================================================================
echo -e "${YELLOW}[9/15] Initializing Bench (5-10 minutes)...${NC}"
su - $FRAPPE_USER <<EOSU
cd /home/$FRAPPE_USER
bench init frappe-bench --frappe-branch $FRAPPE_VERSION --python python3
EOSU

[ ! -d "$BENCH_PATH" ] && error_exit "Bench initialization failed"

# =============================================================================
# [10/15] Create Site
# =============================================================================
echo -e "${YELLOW}[10/15] Creating site: $SITE_NAME...${NC}"
su - $FRAPPE_USER <<EOSU
cd $BENCH_PATH
bench new-site $SITE_NAME --admin-password '$ADMIN_PASSWORD' --mariadb-root-password '$MYSQL_ROOT_PASSWORD'
bench use $SITE_NAME
EOSU

# =============================================================================
# [11/15] Install ERPNext
# =============================================================================
echo -e "${YELLOW}[11/15] Installing ERPNext (10-15 minutes)...${NC}"
su - $FRAPPE_USER <<EOSU
cd $BENCH_PATH
bench get-app erpnext --branch $ERPNEXT_VERSION
bench --site $SITE_NAME install-app erpnext
EOSU

# =============================================================================
# [12/15] Configure Site
# =============================================================================
echo -e "${YELLOW}[12/15] Configuring site...${NC}"
su - $FRAPPE_USER <<EOSU
cd $BENCH_PATH
bench --site $SITE_NAME enable-scheduler
bench --site $SITE_NAME set-maintenance-mode off
bench use $SITE_NAME
EOSU

# =============================================================================
# [13/15] Setup Production
# =============================================================================
echo -e "${YELLOW}[13/15] Setting up production...${NC}"

systemctl stop nginx 2>/dev/null || true
rm -f /etc/nginx/conf.d/frappe-bench.conf 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
rm -f /etc/supervisor/conf.d/frappe-bench.conf 2>/dev/null || true

# Setup supervisor
su - $FRAPPE_USER <<EOSU
cd $BENCH_PATH
yes | bench setup supervisor --yes
EOSU
ln -sf $BENCH_PATH/config/supervisor.conf /etc/supervisor/conf.d/frappe-bench.conf
supervisorctl reread
supervisorctl update

# Setup domain and nginx
su - $FRAPPE_USER <<EOSU
cd $BENCH_PATH
bench config dns_multitenant on
bench setup add-domain $SITE_NAME --site $SITE_NAME
yes | bench setup nginx --yes
EOSU

# Fix and copy nginx config
cp "$BENCH_PATH/config/nginx.conf" "/etc/nginx/conf.d/frappe-bench.conf"
sed -i 's/access_log.*main;/access_log \/var\/log\/nginx\/access.log;/g' /etc/nginx/conf.d/frappe-bench.conf
sed -i 's/ main;/;/g' /etc/nginx/conf.d/frappe-bench.conf

# =============================================================================
# [14/15] Start Services
# =============================================================================
echo -e "${YELLOW}[14/15] Starting services...${NC}"

ufw allow 22/tcp 2>/dev/null || true
ufw allow 80/tcp 2>/dev/null || true
ufw allow 443/tcp 2>/dev/null || true
ufw --force enable 2>/dev/null || true

chmod -R o+rx /home/$FRAPPE_USER
chown -R $FRAPPE_USER:$FRAPPE_USER $BENCH_PATH

nginx -t && systemctl start nginx && systemctl enable nginx
supervisorctl start all
sleep 5

# =============================================================================
# [15/15] SSL Setup
# =============================================================================
echo -e "${YELLOW}[15/15] SSL Setup...${NC}"

if [[ "$SETUP_SSL" == "y" ]]; then
    snap install core 2>/dev/null || true
    snap install --classic certbot 2>/dev/null || true
    ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true
    sleep 3
    
    certbot --nginx -d $SITE_NAME --non-interactive --agree-tos --email "$SSL_EMAIL" || \
    echo -e "${YELLOW}SSL setup failed. Run manually: sudo certbot --nginx -d $SITE_NAME${NC}"
    
    sed -i 's/access_log.*main;/access_log \/var\/log\/nginx\/access.log;/g' /etc/nginx/conf.d/frappe-bench.conf
    nginx -t && systemctl reload nginx
fi

# Final restart
supervisorctl restart all
systemctl reload nginx 2>/dev/null || true
sleep 3

# =============================================================================
# Save Credentials & Display Results
# =============================================================================

SERVER_IP=$(hostname -I | awk '{print $1}')
[[ "$SETUP_SSL" == "y" ]] && SITE_URL="https://$SITE_NAME" || SITE_URL="http://$SITE_NAME"

CRED_FILE="/root/erpnext_credentials_$(date +%Y%m%d_%H%M%S).txt"
cat > $CRED_FILE <<EOF
ERPNext Credentials - $(date)
==============================
Site URL: $SITE_URL
Server IP: $SERVER_IP

Login: Administrator
Password: $ADMIN_PASSWORD

MySQL Root: $MYSQL_ROOT_PASSWORD
==============================
EOF
chmod 600 $CRED_FILE

clear
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        🎉 ERPNext v15 Installation Complete! 🎉                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}Site URL:${NC}     ${YELLOW}$SITE_URL${NC}"
echo -e "  ${GREEN}Server IP:${NC}    ${YELLOW}$SERVER_IP${NC}"
echo ""
echo -e "  ${GREEN}Username:${NC}     ${YELLOW}Administrator${NC}"
echo -e "  ${GREEN}Password:${NC}     ${YELLOW}$ADMIN_PASSWORD${NC}"
echo ""
echo -e "  ${GREEN}MySQL Root:${NC}   ${YELLOW}$MYSQL_ROOT_PASSWORD${NC}"
echo ""
echo -e "${CYAN}Service Status:${NC}"
supervisorctl status
echo ""
echo -e "${GREEN}Credentials saved to:${NC} ${YELLOW}$CRED_FILE${NC}"
echo ""
echo -e "${GREEN}Installation complete!${NC}"
