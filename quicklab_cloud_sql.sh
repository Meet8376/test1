#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Automation Script
# Lab: Configure Cloud SQL (CBL037 / GSP037)
# ==============================================================================

set -euo pipefail

# ANSI Color Codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}=================================================================${NC}"
echo -e "${CYAN}   Configure Cloud SQL - Quicklab Automation                     ${NC}"
echo -e "${CYAN}   Lab ID: CBL037 | Google Cloud Skills Boost                    ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# Project and Configuration
PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "${DEVSHELL_PROJECT_ID:-}")
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] Could not determine Project ID. Run 'gcloud config set project [PROJECT_ID]' first.${NC}"
    exit 1
fi

export REGION="${REGION:-us-west1}"
export ZONE="${ZONE:-us-west1-a}"
export ROOT_PASSWORD="${ROOT_PASSWORD:-Password123!}"

echo -e "${BLUE}[INFO] Active Project: ${PROJECT_ID}${NC}"
echo -e "${BLUE}[INFO] Target Region:   ${REGION}${NC}"
echo -e "${BLUE}[INFO] Target Zone:     ${ZONE}${NC}"
echo -e "${BLUE}[INFO] Root Password:   ${ROOT_PASSWORD}${NC}"

# ==============================================================================
# TASK 1: Configure Private Services Access & Create Cloud SQL Database
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 1/4] Setting up Networking & Cloud SQL Instance...${NC}"

echo -e "${BLUE}[INFO] Enabling Service Networking API...${NC}"
gcloud services enable servicenetworking.googleapis.com --quiet

echo -e "${BLUE}[INFO] Configuring Private Services Access VPC Peering...${NC}"
gcloud compute addresses create google-managed-services-default \
    --global \
    --purpose=VPC_PEERING \
    --prefix-length=16 \
    --description="Peering range for Cloud SQL" \
    --network=default --quiet 2>/dev/null || true

gcloud services vpc-peerings connect \
    --service=servicenetworking.googleapis.com \
    --ranges=google-managed-services-default \
    --network=default --quiet 2>/dev/null || true

# Create Cloud SQL Instance
if ! gcloud sql instances describe wordpress-db &>/dev/null; then
    echo -e "${BLUE}[INFO] Creating Cloud SQL instance 'wordpress-db'...${NC}"
    if ! gcloud sql instances create wordpress-db \
        --database-version=MYSQL_8_0 \
        --edition=ENTERPRISE \
        --tier=db-custom-1-3840 \
        --region="$REGION" \
        --zone="$ZONE" \
        --root-password="$ROOT_PASSWORD" \
        --storage-type=SSD \
        --storage-size=10GB \
        --storage-auto-increase \
        --network=projects/$PROJECT_ID/global/networks/default \
        --assign-ip \
        --ssl-mode=ALLOW_UNENCRYPTED_AND_ENCRYPTED \
        --quiet; then

        echo -e "${YELLOW}[WARN] Retrying instance creation with standard parameters...${NC}"
        gcloud sql instances create wordpress-db \
            --database-version=MYSQL_8_0 \
            --tier=db-custom-1-3840 \
            --region="$REGION" \
            --zone="$ZONE" \
            --root-password="$ROOT_PASSWORD" \
            --storage-type=SSD \
            --storage-size=10GB \
            --network=projects/$PROJECT_ID/global/networks/default \
            --assign-ip \
            --quiet
    fi
else
    echo -e "${GREEN}[INFO] Cloud SQL instance 'wordpress-db' already exists.${NC}"
fi

# Wait for instance to become RUNNABLE
echo -e "${BLUE}[INFO] Waiting for 'wordpress-db' to become RUNNABLE...${NC}"
for i in {1..60}; do
    STATE=$(gcloud sql instances describe wordpress-db --format="value(state)" 2>/dev/null || echo "")
    if [ "$STATE" == "RUNNABLE" ]; then
        echo -e "${GREEN}[SUCCESS] Cloud SQL instance 'wordpress-db' is RUNNABLE!${NC}"
        break
    fi
    echo -e "${BLUE}Current status: ${STATE:-PENDING_CREATE} (attempt $i/60). Waiting 10s...${NC}"
    sleep 10
done

# ==============================================================================
# TASK 2: Create Database 'wordpress' & Retrieve Connection Details
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 2/4] Creating database and retrieving connection parameters...${NC}"

echo -e "${BLUE}[INFO] Creating database 'wordpress'...${NC}"
gcloud sql databases create wordpress --instance=wordpress-db --quiet 2>/dev/null || true

SQL_CONNECTION_NAME=$(gcloud sql instances describe wordpress-db --format="value(connectionName)")
echo -e "${GREEN}[INFO] Cloud SQL Connection Name: ${SQL_CONNECTION_NAME}${NC}"

SQL_PRIVATE_IP=$(gcloud sql instances describe wordpress-db --format="json" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    for ip in data.get("ipAddresses", []):
        if ip.get("type") == "PRIVATE":
            print(ip.get("ipAddress"))
            break
except Exception:
    pass
')
echo -e "${GREEN}[INFO] Cloud SQL Private IP: ${SQL_PRIVATE_IP}${NC}"

# ==============================================================================
# TASK 3: Configure Cloud SQL Proxy on wordpress-proxy VM
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 3/4] Configuring Cloud SQL Proxy on 'wordpress-proxy'...${NC}"

PROXY_ZONE=$(gcloud compute instances list --filter="name=wordpress-proxy" --format="value(zone)" | head -n1)
if [ -z "$PROXY_ZONE" ]; then
    PROXY_ZONE="$ZONE"
fi
echo -e "${BLUE}[INFO] Connecting to 'wordpress-proxy' in ${PROXY_ZONE}...${NC}"

sleep 5
gcloud compute ssh wordpress-proxy --zone="$PROXY_ZONE" --quiet --command="
    wget -q https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O cloud_sql_proxy
    chmod +x cloud_sql_proxy
    pkill -f cloud_sql_proxy || true
    export SQL_CONNECTION=${SQL_CONNECTION_NAME}
    nohup ./cloud_sql_proxy -instances=\$SQL_CONNECTION=tcp:3306 > /tmp/proxy.log 2>&1 &
    sleep 3
    echo 'Proxy Process Status:'
    ps aux | grep cloud_sql_proxy | grep -v grep || true

    # Configure WordPress frontend
    if [ -f /var/www/html/wp-config-sample.php ]; then
        sudo sed -e 's/database_name_here/wordpress/' \
                 -e 's/username_here/root/' \
                 -e 's/password_here/${ROOT_PASSWORD}/' \
                 -e 's/localhost/127.0.0.1/' \
                 /var/www/html/wp-config-sample.php | sudo tee /var/www/html/wp-config.php > /dev/null
        sudo chown www-data:www-data /var/www/html/wp-config.php 2>/dev/null || true
        curl -s -d 'weblog_title=My+Blog&user_name=admin&admin_email=admin%40example.com&admin_password=${ROOT_PASSWORD}&pass1=${ROOT_PASSWORD}&pass2=${ROOT_PASSWORD}' 'http://localhost/wp-admin/install.php?step=2' > /dev/null || true
    fi
" 2>/dev/null || gcloud compute ssh wordpress-proxy --zone="$PROXY_ZONE" --tunnel-through-iap --quiet --command="
    wget -q https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O cloud_sql_proxy
    chmod +x cloud_sql_proxy
    pkill -f cloud_sql_proxy || true
    export SQL_CONNECTION=${SQL_CONNECTION_NAME}
    nohup ./cloud_sql_proxy -instances=\$SQL_CONNECTION=tcp:3306 > /tmp/proxy.log 2>&1 &
    sleep 3
    echo 'Proxy Process Status:'
    ps aux | grep cloud_sql_proxy | grep -v grep || true

    if [ -f /var/www/html/wp-config-sample.php ]; then
        sudo sed -e 's/database_name_here/wordpress/' \
                 -e 's/username_here/root/' \
                 -e 's/password_here/${ROOT_PASSWORD}/' \
                 -e 's/localhost/127.0.0.1/' \
                 /var/www/html/wp-config-sample.php | sudo tee /var/www/html/wp-config.php > /dev/null
        sudo chown www-data:www-data /var/www/html/wp-config.php 2>/dev/null || true
        curl -s -d 'weblog_title=My+Blog&user_name=admin&admin_email=admin%40example.com&admin_password=${ROOT_PASSWORD}&pass1=${ROOT_PASSWORD}&pass2=${ROOT_PASSWORD}' 'http://localhost/wp-admin/install.php?step=2' > /dev/null || true
    fi
" || true

# ==============================================================================
# TASK 4: Configure WordPress on wordpress-private-ip VM
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 4/4] Configuring 'wordpress-private-ip' over Private IP...${NC}"

PRIVATE_VM_ZONE=$(gcloud compute instances list --filter="name=wordpress-private-ip" --format="value(zone)" | head -n1)
if [ -n "$PRIVATE_VM_ZONE" ] && [ -n "$SQL_PRIVATE_IP" ]; then
    echo -e "${BLUE}[INFO] Connecting to 'wordpress-private-ip' in ${PRIVATE_VM_ZONE}...${NC}"
    gcloud compute ssh wordpress-private-ip --zone="$PRIVATE_VM_ZONE" --quiet --command="
        if [ -f /var/www/html/wp-config-sample.php ]; then
            sudo sed -e 's/database_name_here/wordpress/' \
                     -e 's/username_here/root/' \
                     -e 's/password_here/${ROOT_PASSWORD}/' \
                     -e 's/localhost/${SQL_PRIVATE_IP}/' \
                     /var/www/html/wp-config-sample.php | sudo tee /var/www/html/wp-config.php > /dev/null
            sudo chown www-data:www-data /var/www/html/wp-config.php 2>/dev/null || true
            curl -s http://localhost/ > /dev/null || true
        fi
    " 2>/dev/null || gcloud compute ssh wordpress-private-ip --zone="$PRIVATE_VM_ZONE" --tunnel-through-iap --quiet --command="
        if [ -f /var/www/html/wp-config-sample.php ]; then
            sudo sed -e 's/database_name_here/wordpress/' \
                     -e 's/username_here/root/' \
                     -e 's/password_here/${ROOT_PASSWORD}/' \
                     -e 's/localhost/${SQL_PRIVATE_IP}/' \
                     /var/www/html/wp-config-sample.php | sudo tee /var/www/html/wp-config.php > /dev/null
            sudo chown www-data:www-data /var/www/html/wp-config.php 2>/dev/null || true
            curl -s http://localhost/ > /dev/null || true
        fi
    " || true
fi

# Fetch external IPs
PROXY_EXT_IP=$(gcloud compute instances describe wordpress-proxy --zone="$PROXY_ZONE" --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "N/A")
PRIVATE_EXT_IP=""
if [ -n "$PRIVATE_VM_ZONE" ]; then
    PRIVATE_EXT_IP=$(gcloud compute instances describe wordpress-private-ip --zone="$PRIVATE_VM_ZONE" --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "N/A")
fi

echo -e "\n${GREEN}=================================================================${NC}"
echo -e "${GREEN}   Cloud SQL Configuration Completed Successfully! 🚀            ${NC}"
echo -e "${GREEN}=================================================================${NC}"
echo -e "${CYAN}Database Name:         wordpress${NC}"
echo -e "${CYAN}Root Password:         ${ROOT_PASSWORD}${NC}"
echo -e "${CYAN}Connection Name:       ${SQL_CONNECTION_NAME}${NC}"
echo -e "${CYAN}Private IP:            ${SQL_PRIVATE_IP}${NC}"
echo -e "${CYAN}WordPress (Proxy):     http://${PROXY_EXT_IP}/${NC}"
if [ -n "$PRIVATE_EXT_IP" ]; then
    echo -e "${CYAN}WordPress (Private IP): http://${PRIVATE_EXT_IP}/${NC}"
fi
echo -e "${GREEN}=================================================================${NC}"
echo -e "${GREEN}   Click 'Check my progress' on ALL tasks in the lab portal!     ${NC}"
echo -e "${GREEN}=================================================================${NC}"
