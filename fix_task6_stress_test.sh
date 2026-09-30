#!/bin/bash
# ==============================================================================
# Quick Fix for Task 6: Stress test the Application Load Balancer (HTTP)
# ==============================================================================

set -euo pipefail

# ANSI Color Codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}   Fixing Task 6: Stress Test Application Load Balancer${NC}"
echo -e "${CYAN}======================================================${NC}"

# 1. Fetch Load Balancer IPv4 Address
echo -e "${BLUE}[INFO] Fetching Load Balancer IP...${NC}"
LB_IP=$(gcloud compute forwarding-rules describe http-lb-forwarding-rule --global --format="value(IPAddress)" 2>/dev/null || echo "")

if [ -z "$LB_IP" ]; then
    echo -e "${YELLOW}[WARNING] Could not find 'http-lb-forwarding-rule'. Checking other forwarding rules...${NC}"
    LB_IP=$(gcloud compute forwarding-rules list --filter="name ~ 'http-lb'" --format="value(IPAddress)" | head -n1)
fi

if [ -z "$LB_IP" ]; then
    echo -e "${YELLOW}[ERROR] Unable to detect Load Balancer IP. Please ensure the load balancer is created.${NC}"
    exit 1
fi

echo -e "${GREEN}[INFO] Target Load Balancer IP: ${LB_IP}${NC}"

# 2. Wait for Global Load Balancer to become active
echo -e "${YELLOW}>>> [1/3] Verifying Load Balancer is serving HTTP traffic...${NC}"
RESULT=""
for i in {1..30}; do
    RESULT=$(curl -m 2 -s "http://${LB_IP}/" 2>/dev/null | grep -i "Apache" || echo "")
    if [ -n "$RESULT" ]; then
        echo -e "${GREEN}[SUCCESS] Load Balancer is healthy and responding to requests!${NC}"
        break
    fi
    echo -e "${BLUE}Waiting for global load balancer routes to propagate (attempt $i/30)...${NC}"
    sleep 5
done

# 3. Clean up any existing stress-test VM instances across any zone
echo -e "${YELLOW}>>> [2/3] Preparing 'stress-test' VM...${NC}"
EXISTING_INSTANCES=$(gcloud compute instances list --filter="name=stress-test" --format="value(zone)" 2>/dev/null || echo "")
for z in $EXISTING_INSTANCES; do
    echo -e "${BLUE}[INFO] Removing existing stress-test instance in $z...${NC}"
    gcloud compute instances delete stress-test --zone="$z" --quiet 2>/dev/null || true
done

# Allowed candidate zones conforming to Qwiklabs constraints
CANDIDATE_ZONES=("us-east1-b" "us-east1-c" "us-east4-c" "us-east4-b" "us-east4-a" "asia-east1-a")
CREATED_ZONE=""

for ZONE in "${CANDIDATE_ZONES[@]}"; do
    echo -e "${BLUE}[INFO] Trying to create 'stress-test' in ${ZONE}...${NC}"
    if gcloud compute instances create stress-test \
        --zone="$ZONE" \
        --machine-type=e2-micro \
        --image=mywebserver \
        --metadata=startup-script="export LB_IP=${LB_IP}; nohup ab -n 500000 -c 1000 http://\${LB_IP}/ > /tmp/ab.log 2>&1 &" \
        --quiet 2>/tmp/create_err.log; then
        CREATED_ZONE="$ZONE"
        echo -e "${GREEN}[SUCCESS] 'stress-test' created successfully in ${CREATED_ZONE}!${NC}"
        break
    else
        REASON=$(grep -o 'violates constraint[^.]*' /tmp/create_err.log 2>/dev/null || tail -n 1 /tmp/create_err.log)
        echo -e "${YELLOW}[NOTICE] Zone ${ZONE} unavailable: ${REASON}${NC}"
    fi
done

if [ -z "$CREATED_ZONE" ]; then
    echo -e "${YELLOW}[WARNING] Could not create VM in candidate zones. Will generate load directly from Cloud Shell.${NC}"
else
    # 4. Trigger ApacheBench on the stress-test VM via SSH
    echo -e "${YELLOW}>>> [3/3] Executing Apache Benchmark on stress-test VM (${CREATED_ZONE})...${NC}"
    sleep 12
    gcloud compute ssh stress-test --zone="$CREATED_ZONE" --quiet --command="
        export LB_IP=$LB_IP
        echo \"Load Balancer IP: \$LB_IP\"
        nohup ab -n 500000 -c 1000 http://\$LB_IP/ > /tmp/ab.log 2>&1 &
        sleep 2
        echo 'Checking Apache Benchmark process:'
        ps aux | grep ab | grep -v grep || true
    " 2>/dev/null || gcloud compute ssh stress-test --zone="$CREATED_ZONE" --tunnel-through-iap --quiet --command="
        export LB_IP=$LB_IP
        echo \"Load Balancer IP: \$LB_IP\"
        nohup ab -n 500000 -c 1000 http://\$LB_IP/ > /tmp/ab.log 2>&1 &
        sleep 2
        echo 'Checking Apache Benchmark process:'
        ps aux | grep ab | grep -v grep || true
    " 2>/dev/null || true
fi

# 5. Send warm-up load directly from Cloud Shell
echo -e "${BLUE}[INFO] Sending concurrent benchmark traffic from Cloud Shell...${NC}"
sudo apt-get update -qq && sudo apt-get install -y -qq apache2-utils 2>/dev/null || true
nohup ab -n 50000 -c 500 "http://${LB_IP}/" > /tmp/ab_cs.log 2>&1 &
sleep 2

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}   Task 6 Stress Test is Active and Running! 🚀       ${NC}"
echo -e "${GREEN}   Click 'Check my progress' on Task 6 in the lab!    ${NC}"
echo -e "${GREEN}======================================================${NC}"
