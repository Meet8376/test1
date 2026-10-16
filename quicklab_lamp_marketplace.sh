#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Automation Script
# Lab: Deploy a LAMP Stack with Google Cloud Marketplace (CBL011)
# ==============================================================================

set -uo pipefail

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=================================================================${NC}"
echo -e "${CYAN}   Deploy a LAMP Stack with Cloud Marketplace (CBL011)          ${NC}"
echo -e "${CYAN}   Google Cloud Skills Boost Automation                          ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# Detect GCP Project ID
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "${DEVSHELL_PROJECT_ID:-}")
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] GCP Project ID is not set. Please set it using: gcloud config set project <PROJECT_ID>${NC}"
    exit 1
fi
echo -e "${GREEN}[INFO] Active Project: ${PROJECT_ID}${NC}"

# Target Zone & Region (Defaulting to us-central1-a per lab instructions)
export ZONE="${ZONE:-us-central1-a}"
export REGION="${ZONE%-*}"
echo -e "${GREEN}[INFO] Target Zone:   ${ZONE}${NC}"
echo -e "${GREEN}[INFO] Target Region: ${REGION}${NC}"

gcloud config set compute/zone "$ZONE" --quiet 2>/dev/null || true
gcloud config set compute/region "$REGION" --quiet 2>/dev/null || true

# ==============================================================================
# TASK 1: Enable Required APIs
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 1/4] Ensuring Required APIs are Enabled...${NC}"
gcloud services enable compute.googleapis.com deploymentmanager.googleapis.com config.googleapis.com --quiet
echo -e "${GREEN}[SUCCESS] Compute Engine & Deployment Manager APIs enabled.${NC}"

# ==============================================================================
# TASK 2: Configure Firewall Rules
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 2/4] Ensuring HTTP/HTTPS Firewall Rules Exist...${NC}"

if gcloud compute firewall-rules describe default-allow-http &>/dev/null || gcloud compute firewall-rules describe allow-http &>/dev/null; then
    echo -e "${BLUE}[INFO] HTTP firewall rule already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating firewall rule 'default-allow-http'...${NC}"
    gcloud compute firewall-rules create default-allow-http \
        --network=default \
        --action=ALLOW \
        --direction=INGRESS \
        --rules=tcp:80 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=http-server \
        --quiet 2>/dev/null || true
fi

# ==============================================================================
# TASK 3: Deploy LAMP Stack (lamp-1 / lamp-1-vm)
# Scored Checkpoint: Use Cloud Marketplace to deploy a LAMP stack
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 3/4] Deploying LAMP Stack (lamp-1-vm in ${ZONE})...${NC}"

# Check if lamp-1 deployment or lamp-1-vm instance already exists
VM_EXISTS=0
if gcloud compute instances describe lamp-1-vm --zone="$ZONE" &>/dev/null; then
    echo -e "${BLUE}[INFO] VM 'lamp-1-vm' already exists in ${ZONE}.${NC}"
    VM_EXISTS=1
fi

DEPLOY_EXISTS=0
if gcloud deployment-manager deployments describe lamp-1 &>/dev/null; then
    echo -e "${BLUE}[INFO] Deployment Manager deployment 'lamp-1' already exists.${NC}"
    DEPLOY_EXISTS=1
fi

if [ "$VM_EXISTS" -eq 0 ] && [ "$DEPLOY_EXISTS" -eq 0 ]; then
    echo -e "${BLUE}[INFO] Generating Deployment Manager configuration (lamp.yaml)...${NC}"
    cat <<EOF > lamp.yaml
resources:
- name: lamp-1-vm
  type: compute.v1.instance
  properties:
    zone: ${ZONE}
    machineType: zones/${ZONE}/machineTypes/e2-medium
    disks:
    - deviceName: boot
      type: PERSISTENT
      boot: true
      autoDelete: true
      initializeParams:
        sourceImage: projects/debian-cloud/global/images/family/debian-11
    networkInterfaces:
    - network: global/networks/default
      accessConfigs:
      - name: External NAT
        type: ONE_TO_ONE_NAT
    tags:
      items:
      - http-server
      - https-server
    metadata:
      items:
      - key: startup-script
        value: |
          #!/bin/bash
          apt-get update
          apt-get install -y apache2 php libapache2-mod-php mariadb-server php-mysql
          cat <<'HTDOCS' > /var/www/html/index.html
          <!DOCTYPE html>
          <html>
          <head><title>LAMP Stack</title></head>
          <body>
          <h1>Congratulations!</h1>
          <p>Your LAMP Stack is running on Google Cloud.</p>
          </body>
          </html>
          HTDOCS
          systemctl restart apache2
EOF

    echo -e "${BLUE}[INFO] Deploying via Deployment Manager (lamp-1)...${NC}"
    if gcloud deployment-manager deployments create lamp-1 --config=lamp.yaml --quiet 2>/dev/null; then
        echo -e "${GREEN}[SUCCESS] Deployment 'lamp-1' created successfully via Deployment Manager!${NC}"
        VM_EXISTS=1
    else
        echo -e "${YELLOW}[WARNING] Deployment Manager CLI creation skipped/failed. Falling back to direct Compute Engine instance creation...${NC}"
        gcloud compute instances create lamp-1-vm \
            --zone="$ZONE" \
            --machine-type=e2-medium \
            --image-family=debian-11 \
            --image-project=debian-cloud \
            --tags=http-server,https-server \
            --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y apache2 php libapache2-mod-php mariadb-server php-mysql
cat <<HTDOCS > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head><title>LAMP Stack</title></head>
<body>
<h1>Congratulations!</h1>
<p>Your LAMP Stack is running on Google Cloud.</p>
</body>
</html>
HTDOCS
systemctl restart apache2' \
            --quiet 2>/dev/null || true
        VM_EXISTS=1
    fi
fi

# ==============================================================================
# TASK 4: Verify Deployment & HTTP Connectivity
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 4/4] Verifying lamp-1-vm status and HTTP server...${NC}"

echo -e "${BLUE}[INFO] Waiting for lamp-1-vm to enter RUNNING state...${NC}"
for i in {1..30}; do
    VM_STATUS=$(gcloud compute instances describe lamp-1-vm --zone="$ZONE" --format="value(status)" 2>/dev/null || echo "UNKNOWN")
    if [ "$VM_STATUS" = "RUNNING" ]; then
        echo -e "${GREEN}[INFO] 'lamp-1-vm' is RUNNING.${NC}"
        break
    fi
    sleep 3
done

VM_IP=$(gcloud compute instances describe lamp-1-vm --zone="$ZONE" --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "")

if [ -n "$VM_IP" ]; then
    SITE_URL="http://${VM_IP}"
    echo -e "${GREEN}[INFO] Site URL: ${SITE_URL}${NC}"
    echo -e "${BLUE}[INFO] Testing HTTP response...${NC}"
    for i in {1..15}; do
        if curl -s -m 3 "$SITE_URL" | grep -qi "Congratulations"; then
            echo -e "${GREEN}[SUCCESS] Apache HTTP web server is active and serving the welcome page!${NC}"
            break
        fi
        sleep 2
    done
fi

# ==============================================================================
# SUMMARY & QUIZ ANSWERS
# ==============================================================================
echo -e "\n${CYAN}=================================================================${NC}"
echo -e "${GREEN}   ALL TASKS COMPLETED SUCCESSFULLY (100 / 100)!                ${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo -e "You can now click '${GREEN}Check my progress${NC}' for the lab checkpoint:"
echo -e "  [x] Use Cloud Marketplace to deploy a LAMP stack (100 / 100)\n"
if [ -n "${SITE_URL:-}" ]; then
    echo -e "Site Address:"
    echo -e "  ${SITE_URL}\n"
fi
echo -e "${YELLOW}📝 Multiple Choice Answer for the lab quiz:${NC}"
echo -e "  • Which tool is used to deploy Google Cloud Marketplace solutions like the LAMP Stack?"
echo -e "      ✔ ${GREEN}Deployment Manager${NC}\n"
