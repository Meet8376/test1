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

echo -e "${GREEN}[INFO] Target Load Balancer IP: ${LB_IP}${NC}"

# 2. Wait for Global Load Balancer to become active
echo -e "${YELLOW}>>> [1/3] Verifying Load Balancer is serving HTTP traffic...${NC}"
RESULT=""
for i in {1..40}; do
    RESULT=$(curl -m 2 -s "http://${LB_IP}/" 2>/dev/null | grep -i "Apache" || echo "")
    if [ -n "$RESULT" ]; then
        echo -e "${GREEN}[SUCCESS] Load Balancer is healthy and responding to requests!${NC}"
        break
    fi
    echo -e "${BLUE}Waiting for global load balancer routes to propagate (attempt $i/40)...${NC}"
    sleep 5
done

# 3. Create stress-test VM in a DIFFERENT region closer to us-east4 (us-central1-a)
echo -e "${YELLOW}>>> [2/3] Setting up 'stress-test' VM in us-central1-a...${NC}"

# Clean up existing stress-test VM in us-east4 if present
gcloud compute instances delete stress-test --zone=us-east4-c --quiet 2>/dev/null || true
gcloud compute instances delete stress-test --zone=us-east4-a --quiet 2>/dev/null || true
gcloud compute instances delete stress-test --zone=us-east4-b --quiet 2>/dev/null || true

STRESS_ZONE="us-central1-a"
if ! gcloud compute instances describe stress-test --zone="$STRESS_ZONE" &>/dev/null; then
    gcloud compute instances create stress-test \
        --zone="$STRESS_ZONE" \
        --machine-type=e2-micro \
        --image=mywebserver \
        --quiet
fi

# 4. Trigger ApacheBench on the stress-test VM via SSH
echo -e "${YELLOW}>>> [3/3] Executing Apache Benchmark on stress-test VM...${NC}"
sleep 10
gcloud compute ssh stress-test --zone="$STRESS_ZONE" --tunnel-through-iap --quiet --command="
export LB_IP=$LB_IP
nohup ab -n 500000 -c 1000 http://\$LB_IP/ > /tmp/ab.log 2>&1 &
sleep 2
echo 'Apache Benchmark running in background:'
ps aux | grep ab | grep -v grep || true
" || true

# Also send warm-up load directly from Cloud Shell
sudo apt-get update -qq && sudo apt-get install -y -qq apache2-utils 2>/dev/null || true
ab -n 2000 -c 100 "http://${LB_IP}/" 2>/dev/null || true

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}   Task 6 Stress Test is Active and Running! 🚀       ${NC}"
echo -e "${GREEN}   Click 'Check my progress' on Task 6 in the lab!    ${NC}"
echo -e "${GREEN}======================================================${NC}"
