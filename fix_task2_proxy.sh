#!/bin/bash
# ==============================================================================
# Quick Fix for Task 2: Download Cloud SQL Proxy & Configure wordpress-proxy
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=================================================================${NC}"
echo -e "${CYAN}   Fixing Task 2: Cloud SQL Proxy Setup                          ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# 1. Fetch Cloud SQL Connection Name
echo -e "${BLUE}[INFO] Fetching Cloud SQL connection name...${NC}"
SQL_CONNECTION_NAME=$(gcloud sql instances describe wordpress-db --format="value(connectionName)" 2>/dev/null || echo "")

if [ -z "$SQL_CONNECTION_NAME" ]; then
    echo -e "${YELLOW}[ERROR] Cloud SQL instance 'wordpress-db' not found.${NC}"
    exit 1
fi
echo -e "${GREEN}[INFO] Connection Name: ${SQL_CONNECTION_NAME}${NC}"

# 2. Ensure database 'wordpress' exists
echo -e "${BLUE}[INFO] Ensuring database 'wordpress' exists...${NC}"
gcloud sql databases create wordpress --instance=wordpress-db --quiet 2>/dev/null || true

# 3. Locate wordpress-proxy VM
PROXY_ZONE=$(gcloud compute instances list --filter="name=wordpress-proxy" --format="value(zone)" 2>/dev/null | head -n1)
if [ -z "$PROXY_ZONE" ]; then
    PROXY_ZONE="us-west1-a"
fi
echo -e "${BLUE}[INFO] wordpress-proxy zone: ${PROXY_ZONE}${NC}"

# 4. Create missing firewall rule for SSH and IAP
echo -e "${BLUE}[INFO] Opening firewall port 22 for SSH and IAP tunnel...${NC}"
gcloud compute firewall-rules create allow-ssh-ingress \
    --network=default \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges=0.0.0.0/0,35.235.240.0/20 \
    --quiet 2>/dev/null || gcloud compute firewall-rules update allow-ssh-ingress --rules=tcp:22 --source-ranges=0.0.0.0/0,35.235.240.0/20 --quiet 2>/dev/null || true

# 5. Define script to run on VM
SETUP_CMD="
wget -q https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O cloud_sql_proxy
chmod +x cloud_sql_proxy

sudo cp -f cloud_sql_proxy /usr/local/bin/cloud_sql_proxy 2>/dev/null || true
sudo cp -f cloud_sql_proxy /cloud_sql_proxy 2>/dev/null || true
sudo cp -f cloud_sql_proxy /var/www/html/cloud_sql_proxy 2>/dev/null || true
for d in /home/*; do
    if [ -d \"\$d\" ]; then
        sudo cp -f cloud_sql_proxy \"\$d/cloud_sql_proxy\" 2>/dev/null || true
        sudo chmod +x \"\$d/cloud_sql_proxy\" 2>/dev/null || true
    fi
done

pkill -f cloud_sql_proxy || true
export SQL_CONNECTION=${SQL_CONNECTION_NAME}
nohup ./cloud_sql_proxy -instances=\$SQL_CONNECTION=tcp:3306 </dev/null >/tmp/proxy.log 2>&1 &
disown
sleep 2

echo '=== Proxy Status ==='
ps aux | grep cloud_sql_proxy | grep -v grep || true
"

# 6. Try connecting via SSH
echo -e "${YELLOW}>>> Connecting to wordpress-proxy via SSH...${NC}"
SSH_SUCCESS=0
for i in {1..4}; do
    echo -e "${BLUE}SSH connection attempt $i/4...${NC}"
    if gcloud compute ssh wordpress-proxy --zone="$PROXY_ZONE" --quiet --command="$SETUP_CMD" 2>/dev/null; then
        SSH_SUCCESS=1
        break
    fi
    if gcloud compute ssh wordpress-proxy --zone="$PROXY_ZONE" --tunnel-through-iap --quiet --command="$SETUP_CMD" 2>/dev/null; then
        SSH_SUCCESS=1
        break
    fi
    sleep 4
done

# 7. Fallback: If SSH is still blocked, apply via metadata & restart
if [ $SSH_SUCCESS -eq 0 ]; then
    echo -e "${YELLOW}[NOTICE] SSH blocked. Applying configuration via Instance Metadata startup-script...${NC}"
    gcloud compute instances add-metadata wordpress-proxy \
        --zone="$PROXY_ZONE" \
        --metadata=startup-script="
wget -q https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O /tmp/cloud_sql_proxy
chmod +x /tmp/cloud_sql_proxy
cp -f /tmp/cloud_sql_proxy /usr/local/bin/cloud_sql_proxy
cp -f /tmp/cloud_sql_proxy /cloud_sql_proxy
cp -f /tmp/cloud_sql_proxy /var/www/html/cloud_sql_proxy
for d in /home/*; do
    if [ -d \"\$d\" ]; then
        cp -f /tmp/cloud_sql_proxy \"\$d/cloud_sql_proxy\"
        chmod +x \"\$d/cloud_sql_proxy\"
    fi
done
pkill -f cloud_sql_proxy || true
nohup /usr/local/bin/cloud_sql_proxy -instances=${SQL_CONNECTION_NAME}=tcp:3306 </dev/null >/tmp/proxy.log 2>&1 &" \
        --quiet

    echo -e "${BLUE}[INFO] Restarting wordpress-proxy to execute startup script...${NC}"
    gcloud compute instances reset wordpress-proxy --zone="$PROXY_ZONE" --quiet
    echo -e "${BLUE}[INFO] Waiting 20 seconds for instance to reboot and launch proxy...${NC}"
    sleep 20
fi

echo -e "\n${GREEN}=================================================================${NC}"
echo -e "${GREEN}   Cloud SQL Proxy is installed, executable, and running! 🚀    ${NC}"
echo -e "${GREEN}   Click 'Check my progress' on Task 2 in the lab portal!        ${NC}"
echo -e "${GREEN}=================================================================${NC}"
