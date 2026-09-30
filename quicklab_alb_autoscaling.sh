#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Automation Script
# Lab: Configure an Application Load Balancer with Autoscaling (OCBL105)
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
echo -e "${CYAN}   Configure Application Load Balancer with Autoscaling (OCBL105) ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# Detect Environment Variables
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "$DEVSHELL_PROJECT_ID")
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] GCP Project ID is not set. Please set it using: gcloud config set project <PROJECT_ID>${NC}"
    exit 1
fi
echo -e "${GREEN}[INFO] Active Project: ${PROJECT_ID}${NC}"

# Define Regions and Zones
REGION1="${REGION1:-us-east4}"
ZONE1="${ZONE1:-${REGION1}-a}"
REGION2="${REGION2:-asia-east1}"

gcloud config set compute/region "$REGION1" --quiet 2>/dev/null || true

echo -e "${GREEN}[INFO] Primary Region (Region 1): ${REGION1} (Zone: ${ZONE1})${NC}"
echo -e "${GREEN}[INFO] Secondary Region (Region 2): ${REGION2}${NC}"

# ==============================================================================
# TASK 1: Configure a health check firewall rule
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 1/6] Creating Health Check Firewall Rule...${NC}"

if gcloud compute firewall-rules describe fw-allow-health-checks &>/dev/null; then
    echo -e "${BLUE}[SKIP] Firewall rule 'fw-allow-health-checks' already exists.${NC}"
else
    gcloud compute firewall-rules create fw-allow-health-checks \
        --network=default \
        --action=ALLOW \
        --direction=INGRESS \
        --source-ranges=130.211.0.0/22,35.191.0.0/16 \
        --target-tags=allow-health-checks \
        --rules=tcp:80 \
        --quiet
fi
echo -e "${GREEN}[SUCCESS] Task 1 completed! You can check progress for Task 1.${NC}"

# ==============================================================================
# TASK 2: Create a NAT configuration using Cloud Router
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 2/6] Configuring Cloud Router and Cloud NAT...${NC}"

if gcloud compute routers describe nat-router-us1 --region="$REGION1" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Cloud Router 'nat-router-us1' already exists.${NC}"
else
    gcloud compute routers create nat-router-us1 \
        --network=default \
        --region="$REGION1" \
        --quiet
fi

if gcloud compute routers nats describe nat-config --router=nat-router-us1 --region="$REGION1" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Cloud NAT 'nat-config' already exists.${NC}"
else
    gcloud compute routers nats create nat-config \
        --router=nat-router-us1 \
        --region="$REGION1" \
        --auto-allocate-nat-external-ips \
        --nat-all-subnet-ip-ranges \
        --quiet
fi

echo -e "${BLUE}[INFO] Waiting 10 seconds for Cloud NAT routes to propagate...${NC}"
sleep 10
echo -e "${GREEN}[SUCCESS] Task 2 completed! You can check progress for Task 2.${NC}"

# ==============================================================================
# TASK 3: Create a custom image for a web server
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 3/6] Creating Custom Web Server Image 'mywebserver'...${NC}"

if gcloud compute images describe mywebserver &>/dev/null; then
    echo -e "${BLUE}[SKIP] Custom image 'mywebserver' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Provisioning temporary VM 'webserver' in ${ZONE1}...${NC}"
    gcloud compute instances create webserver \
        --zone="$ZONE1" \
        --machine-type=e2-medium \
        --network=default \
        --tags=allow-health-checks \
        --no-address \
        --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y apache2
systemctl enable apache2
systemctl start apache2' \
        --quiet

    echo -e "${BLUE}[INFO] Waiting 35 seconds for Apache installation via Cloud NAT...${NC}"
    sleep 35

    echo -e "${BLUE}[INFO] Deleting 'webserver' while keeping boot disk...${NC}"
    gcloud compute instances delete webserver --zone="$ZONE1" --keep-disks=boot --quiet

    echo -e "${BLUE}[INFO] Creating image 'mywebserver' from disk 'webserver'...${NC}"
    gcloud compute images create mywebserver \
        --source-disk=webserver \
        --source-disk-zone="$ZONE1" \
        --quiet
fi
echo -e "${GREEN}[SUCCESS] Task 3 completed! You can check progress for Task 3.${NC}"

# ==============================================================================
# TASK 4: Configure an instance template and create instance groups
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 4/6] Creating Instance Template & Managed Instance Groups...${NC}"

# 1. Health check for MIGs
if ! gcloud compute health-checks describe http-health-check &>/dev/null; then
    echo -e "${BLUE}[INFO] Creating health check 'http-health-check'...${NC}"
    gcloud compute health-checks create http http-health-check \
        --port=80 \
        --quiet
fi

# 2. Instance Template
if ! gcloud compute instance-templates describe mywebserver-template &>/dev/null; then
    echo -e "${BLUE}[INFO] Creating instance template 'mywebserver-template'...${NC}"
    gcloud compute instance-templates create mywebserver-template \
        --machine-type=e2-micro \
        --network-interface=network=default,no-address \
        --tags=allow-health-checks \
        --image=mywebserver \
        --quiet
fi

# 3. Create us-1-mig in Region 1
if ! gcloud compute instance-groups managed describe us-1-mig --region="$REGION1" &>/dev/null; then
    echo -e "${BLUE}[INFO] Creating managed instance group 'us-1-mig' in ${REGION1}...${NC}"
    gcloud compute instance-groups managed create us-1-mig \
        --template=mywebserver-template \
        --region="$REGION1" \
        --size=1 \
        --health-check=http-health-check \
        --initial-delay=60 \
        --quiet

    gcloud compute instance-groups managed set-autoscaling us-1-mig \
        --region="$REGION1" \
        --min-num-replicas=1 \
        --max-num-replicas=2 \
        --target-load-balancing-utilization=0.8 \
        --cool-down-period=60 \
        --quiet
fi

# 4. Create notus-1-mig in Region 2
if ! gcloud compute instance-groups managed describe notus-1-mig --region="$REGION2" &>/dev/null; then
    echo -e "${BLUE}[INFO] Creating managed instance group 'notus-1-mig' in ${REGION2}...${NC}"
    gcloud compute instance-groups managed create notus-1-mig \
        --template=mywebserver-template \
        --region="$REGION2" \
        --size=1 \
        --health-check=http-health-check \
        --initial-delay=60 \
        --quiet

    gcloud compute instance-groups managed set-autoscaling notus-1-mig \
        --region="$REGION2" \
        --min-num-replicas=1 \
        --max-num-replicas=2 \
        --target-load-balancing-utilization=0.8 \
        --cool-down-period=60 \
        --quiet
fi

# Set named ports
gcloud compute instance-groups managed set-named-ports us-1-mig --region="$REGION1" --named-ports=http:80 --quiet 2>/dev/null || true
gcloud compute instance-groups managed set-named-ports notus-1-mig --region="$REGION2" --named-ports=http:80 --quiet 2>/dev/null || true

echo -e "${GREEN}[SUCCESS] Task 4 completed! You can check progress for Task 4.${NC}"

# ==============================================================================
# TASK 5: Configure the Application Load Balancer (HTTP)
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 5/6] Configuring Application Load Balancer (HTTP)...${NC}"

# 1. Backend Service
if ! gcloud compute backend-services describe http-backend --global &>/dev/null; then
    echo -e "${BLUE}[INFO] Creating global backend service 'http-backend'...${NC}"
    gcloud compute backend-services create http-backend \
        --protocol=HTTP \
        --port-name=http \
        --health-checks=http-health-check \
        --global \
        --enable-logging \
        --logging-sample-rate=1.0 \
        --quiet
fi

# Add backends
echo -e "${BLUE}[INFO] Attaching backends to 'http-backend'...${NC}"
gcloud compute backend-services add-backend http-backend \
    --instance-group=us-1-mig \
    --instance-group-region="$REGION1" \
    --balancing-mode=RATE \
    --max-rate-per-instance=50 \
    --capacity-scaler=1.0 \
    --global \
    --quiet 2>/dev/null || true

gcloud compute backend-services add-backend http-backend \
    --instance-group=notus-1-mig \
    --instance-group-region="$REGION2" \
    --balancing-mode=UTILIZATION \
    --max-utilization=0.8 \
    --capacity-scaler=1.0 \
    --global \
    --quiet 2>/dev/null || true

# 2. URL Map
if ! gcloud compute url-maps describe http-lb &>/dev/null; then
    echo -e "${BLUE}[INFO] Creating URL Map 'http-lb'...${NC}"
    gcloud compute url-maps create http-lb \
        --default-service=http-backend \
        --quiet
fi

# 3. Target HTTP Proxy
if ! gcloud compute target-http-proxies describe http-lb-target-proxy &>/dev/null; then
    echo -e "${BLUE}[INFO] Creating Target HTTP Proxy 'http-lb-target-proxy'...${NC}"
    gcloud compute target-http-proxies create http-lb-target-proxy \
        --url-map=http-lb \
        --quiet
fi

# 4. Forwarding Rules (IPv4 and IPv6)
if ! gcloud compute forwarding-rules describe http-lb-forwarding-rule --global &>/dev/null; then
    echo -e "${BLUE}[INFO] Creating IPv4 forwarding rule 'http-lb-forwarding-rule'...${NC}"
    gcloud compute forwarding-rules create http-lb-forwarding-rule \
        --global \
        --target-http-proxy=http-lb-target-proxy \
        --ports=80 \
        --ip-version=IPV4 \
        --quiet
fi

if ! gcloud compute forwarding-rules describe http-lb-forwarding-rule-2 --global &>/dev/null; then
    echo -e "${BLUE}[INFO] Creating IPv6 forwarding rule 'http-lb-forwarding-rule-2'...${NC}"
    gcloud compute forwarding-rules create http-lb-forwarding-rule-2 \
        --global \
        --target-http-proxy=http-lb-target-proxy \
        --ports=80 \
        --ip-version=IPV6 \
        --quiet
fi

LB_IPV4=$(gcloud compute forwarding-rules describe http-lb-forwarding-rule --global --format="value(IPAddress)" 2>/dev/null || echo "")
LB_IPV6=$(gcloud compute forwarding-rules describe http-lb-forwarding-rule-2 --global --format="value(IPAddress)" 2>/dev/null || echo "")

echo -e "${GREEN}[INFO] Load Balancer IPv4: ${LB_IPV4}${NC}"
echo -e "${GREEN}[INFO] Load Balancer IPv6: ${LB_IPV6}${NC}"
echo -e "${GREEN}[SUCCESS] Task 5 completed! You can check progress for Task 5.${NC}"

# ==============================================================================
# TASK 6: Stress test the Application Load Balancer (HTTP)
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 6/6] Setting up Stress Test...${NC}"

# Wait for load balancer to become active
echo -e "${BLUE}[INFO] Waiting for Load Balancer to respond...${NC}"
for i in {1..30}; do
    if curl -m 2 -s "http://${LB_IPV4}/" 2>/dev/null | grep -i "Apache" &>/dev/null; then
        echo -e "${GREEN}[SUCCESS] Load Balancer is healthy!${NC}"
        break
    fi
    sleep 5
done

# Create stress-test VM in us-central1-a (different region from us-east4)
STRESS_ZONE="us-central1-a"
if ! gcloud compute instances describe stress-test --zone="$STRESS_ZONE" &>/dev/null; then
    echo -e "${BLUE}[INFO] Creating VM 'stress-test' in ${STRESS_ZONE}...${NC}"
    gcloud compute instances create stress-test \
        --zone="$STRESS_ZONE" \
        --machine-type=e2-micro \
        --image=mywebserver \
        --quiet
fi

echo -e "${BLUE}[INFO] Launching ApacheBench from stress-test instance...${NC}"
sleep 10
gcloud compute ssh stress-test --zone="$STRESS_ZONE" --tunnel-through-iap --quiet --command="
export LB_IP=$LB_IPV4
nohup ab -n 500000 -c 1000 http://\$LB_IP/ > /tmp/ab.log 2>&1 &
sleep 2
" || true

# Send direct requests from Cloud Shell
sudo apt-get update -qq && sudo apt-get install -y -qq apache2-utils 2>/dev/null || true
ab -n 2000 -c 100 "http://${LB_IPV4}/" 2>/dev/null || true

echo -e "\n${GREEN}=================================================================${NC}"
echo -e "${GREEN}   All Tasks Completed Successfully! 🚀                          ${NC}"
echo -e "${GREEN}   Click 'Check my progress' on ALL tasks in the lab!            ${NC}"
echo -e "${GREEN}=================================================================${NC}"
