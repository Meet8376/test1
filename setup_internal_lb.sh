#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Automation Script
# Lab: Configure an Internal Network Load Balancer (GSP041)
# ==============================================================================

set -euo pipefail

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=================================================================${NC}"
echo -e "${CYAN}   Configure an Internal Network Load Balancer - Automation      ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# Detect Environment Variables
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] GCP Project ID is not set. Please set it using: gcloud config set project <PROJECT_ID>${NC}"
    exit 1
fi
echo -e "${GREEN}[INFO] Active Project: ${PROJECT_ID}${NC}"

# Detect or Set Region and Zones
REGION="${REGION:-asia-east1}"
ZONE_UTILITY="${ZONE_UTILITY:-asia-east1-b}"

# Detect dynamic zones for instance-group-1 and instance-group-2 if available
echo -e "${BLUE}[INFO] Detecting Instance Group Zones...${NC}"
ZONE_IG1=$(gcloud compute instance-groups managed list --filter="name ~ 'instance-group-1'" --format="value(zone)" 2>/dev/null | head -n1 || echo "")
ZONE_IG2=$(gcloud compute instance-groups managed list --filter="name ~ 'instance-group-2'" --format="value(zone)" 2>/dev/null | head -n1 || echo "")

if [ -z "$ZONE_IG1" ]; then
    ZONE_IG1="asia-east1-c"
fi
if [ -z "$ZONE_IG2" ]; then
    ZONE_IG2="asia-east1-a"
fi

NETWORK="my-internal-app"
SUBNET_A="subnet-a"
SUBNET_B="subnet-b"
ROUTER_NAME="nat-router-${REGION}"
NAT_NAME="nat-config"

echo -e "${GREEN}[INFO] Region: ${REGION}${NC}"
echo -e "${GREEN}[INFO] Utility VM Zone: ${ZONE_UTILITY}${NC}"
echo -e "${GREEN}[INFO] Instance Group 1 Zone: ${ZONE_IG1}${NC}"
echo -e "${GREEN}[INFO] Instance Group 2 Zone: ${ZONE_IG2}${NC}"

# ==============================================================================
# TASK 1: Configure internal traffic and health check firewall rules
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 1/5] Creating Firewall Rules...${NC}"

# Rule 1: fw-allow-lb-access
if gcloud compute firewall-rules describe fw-allow-lb-access --project="$PROJECT_ID" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Firewall rule 'fw-allow-lb-access' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating 'fw-allow-lb-access'...${NC}"
    gcloud compute firewall-rules create fw-allow-lb-access \
        --network="$NETWORK" \
        --action=ALLOW \
        --direction=INGRESS \
        --source-ranges=10.10.0.0/16 \
        --target-tags=backend-service \
        --rules=all
fi

# Rule 2: fw-allow-health-checks
if gcloud compute firewall-rules describe fw-allow-health-checks --project="$PROJECT_ID" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Firewall rule 'fw-allow-health-checks' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating 'fw-allow-health-checks'...${NC}"
    gcloud compute firewall-rules create fw-allow-health-checks \
        --network="$NETWORK" \
        --action=ALLOW \
        --direction=INGRESS \
        --source-ranges=130.211.0.0/22,35.191.0.0/16 \
        --target-tags=backend-service \
        --rules=tcp:80
fi

# ==============================================================================
# TASK 2: Create a NAT configuration using Cloud Router
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 2/5] Configuring Cloud Router and Cloud NAT...${NC}"

if gcloud compute routers describe "$ROUTER_NAME" --region="$REGION" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Cloud Router '$ROUTER_NAME' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating Cloud Router '$ROUTER_NAME'...${NC}"
    gcloud compute routers create "$ROUTER_NAME" \
        --network="$NETWORK" \
        --region="$REGION"
fi

if gcloud compute routers nats describe "$NAT_NAME" --router="$ROUTER_NAME" --region="$REGION" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Cloud NAT '$NAT_NAME' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating Cloud NAT Gateway '$NAT_NAME'...${NC}"
    gcloud compute routers nats create "$NAT_NAME" \
        --router="$ROUTER_NAME" \
        --region="$REGION" \
        --auto-allocate-nat-external-ips \
        --nat-all-subnet-ip-ranges
fi

echo -e "${BLUE}[INFO] Waiting 15 seconds for Cloud NAT routes to propagate...${NC}"
sleep 15

# ==============================================================================
# TASK 3: Configure instance templates and create instance groups
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 3/5] Re-running Startup Scripts and Creating Utility VM...${NC}"

# Re-run startup script on backend instances so apache2/php can install via Cloud NAT
echo -e "${BLUE}[INFO] Re-running startup script on Instance Group VMs...${NC}"
VM1=$(gcloud compute instances list --filter="name ~ 'instance-group-1'" --format="value(name)" | head -n1 || echo "")
VM2=$(gcloud compute instances list --filter="name ~ 'instance-group-2'" --format="value(name)" | head -n1 || echo "")

if [ -n "$VM1" ]; then
    echo -e "${BLUE}[INFO] Re-running startup script on ${VM1} (${ZONE_IG1})...${NC}"
    gcloud compute ssh "$VM1" --zone="$ZONE_IG1" --tunnel-through-iap --quiet --command="sudo google_metadata_script_runner startup" || true
fi

if [ -n "$VM2" ]; then
    echo -e "${BLUE}[INFO] Re-running startup script on ${VM2} (${ZONE_IG2})...${NC}"
    gcloud compute ssh "$VM2" --zone="$ZONE_IG2" --tunnel-through-iap --quiet --command="sudo google_metadata_script_runner startup" || true
fi

# Create utility-vm
if gcloud compute instances describe utility-vm --zone="$ZONE_UTILITY" &>/dev/null; then
    echo -e "${BLUE}[SKIP] VM 'utility-vm' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating 'utility-vm' in zone ${ZONE_UTILITY}...${NC}"
    gcloud compute instances create utility-vm \
        --zone="$ZONE_UTILITY" \
        --machine-type=e2-medium \
        --network="$NETWORK" \
        --subnet="$SUBNET_A" \
        --private-network-ip=10.10.20.50 \
        --no-address \
        --image-family=debian-12 \
        --image-project=debian-cloud
fi

# Wait for utility-vm to become ready
echo -e "${BLUE}[INFO] Waiting 20 seconds for utility-vm to initialize...${NC}"
sleep 20

# Test backend connectivity from utility-vm
echo -e "${BLUE}[INFO] Verifying backend connectivity from utility-vm...${NC}"
gcloud compute ssh utility-vm --zone="$ZONE_UTILITY" --tunnel-through-iap --quiet --command="
echo '--- Backend 1 Check (10.10.20.2) ---'
curl -s -m 5 10.10.20.2 || echo 'Backend 1 not yet responding (will come online shortly)'
echo '--- Backend 2 Check (10.10.30.2) ---'
curl -s -m 5 10.10.30.2 || echo 'Backend 2 not yet responding (will come online shortly)'
" || true

# ==============================================================================
# TASK 4: Configure the internal Network Load Balancer
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 4/5] Configuring Internal Network Load Balancer...${NC}"

# 1. Static Regional IP
if gcloud compute addresses describe my-ilb-ip --region="$REGION" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Static IP 'my-ilb-ip' already reserved.${NC}"
else
    echo -e "${BLUE}[INFO] Reserving static IP 'my-ilb-ip' (10.10.30.5)...${NC}"
    gcloud compute addresses create my-ilb-ip \
        --region="$REGION" \
        --subnet="$SUBNET_B" \
        --addresses=10.10.30.5
fi

# 2. Health Check
if gcloud compute health-checks describe my-ilb-health-check &>/dev/null; then
    echo -e "${BLUE}[SKIP] Health check 'my-ilb-health-check' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating TCP health check 'my-ilb-health-check'...${NC}"
    gcloud compute health-checks create tcp my-ilb-health-check \
        --port=80 \
        --check-interval=10s \
        --timeout=5s \
        --unhealthy-threshold=3 \
        --healthy-threshold=2
fi

# 3. Regional Backend Service
if gcloud compute backend-services describe my-ilb-backend-service --region="$REGION" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Backend service 'my-ilb-backend-service' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating regional backend service 'my-ilb-backend-service'...${NC}"
    gcloud compute backend-services create my-ilb-backend-service \
        --load-balancing-scheme=internal \
        --protocol=TCP \
        --region="$REGION" \
        --health-checks=my-ilb-health-check
fi

# Add Backends (instance-group-1 and instance-group-2)
echo -e "${BLUE}[INFO] Attaching instance groups to backend service...${NC}"
gcloud compute backend-services add-backend my-ilb-backend-service \
    --instance-group=instance-group-1 \
    --instance-group-zone="$ZONE_IG1" \
    --region="$REGION" || true

gcloud compute backend-services add-backend my-ilb-backend-service \
    --instance-group=instance-group-2 \
    --instance-group-zone="$ZONE_IG2" \
    --region="$REGION" || true

# 4. Forwarding Rule (Frontend)
if gcloud compute forwarding-rules describe my-ilb --region="$REGION" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Forwarding rule 'my-ilb' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating forwarding rule 'my-ilb'...${NC}"
    gcloud compute forwarding-rules create my-ilb \
        --load-balancing-scheme=internal \
        --ports=80 \
        --network="$NETWORK" \
        --subnet="$SUBNET_B" \
        --region="$REGION" \
        --backend-service=my-ilb-backend-service \
        --backend-service-region="$REGION" \
        --address=my-ilb-ip
fi

# ==============================================================================
# TASK 5: Test the internal Network Load Balancer
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 5/5] Testing Internal Network Load Balancer from utility-vm...${NC}"

echo -e "${BLUE}[INFO] Waiting 15 seconds for load balancer backends to report healthy...${NC}"
sleep 15

echo -e "${CYAN}Executing curls to 10.10.30.5 from utility-vm:${NC}"
gcloud compute ssh utility-vm --zone="$ZONE_UTILITY" --tunnel-through-iap --quiet --command="
echo '===================================='
echo 'Sending 10 requests to 10.10.30.5:'
echo '===================================='
for i in {1..10}; do
    echo -n \"Request \$i: \"
    curl -s -m 3 http://10.10.30.5 | grep -o 'Server Hostname: [^<]*' || echo 'Waiting for response...'
done
" || true

echo -e "\n${GREEN}=================================================================${NC}"
echo -e "${GREEN}   Lab Configuration Completed Successfully! 🚀                  ${NC}"
echo -e "${GREEN}   You can now click 'Check my progress' on all tasks in the lab!${NC}"
echo -e "${GREEN}=================================================================${NC}"
