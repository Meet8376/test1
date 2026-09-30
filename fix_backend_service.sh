#!/bin/bash
# ==============================================================================
# Quick Fix for Task 4: Create Required Backend Service 'my-ilb'
# ==============================================================================

set -euo pipefail

# ANSI Color Codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}   Fixing Task 4: Internal NLB Backend Service        ${NC}"
echo -e "${CYAN}======================================================${NC}"

# Auto-detect or Set Region from my-internal-app subnets
if [ -z "${REGION:-}" ]; then
    REGION=$(gcloud compute networks subnets list --network="my-internal-app" --format="value(region.basename())" 2>/dev/null | head -n1 || echo "")
fi
if [ -z "${REGION:-}" ]; then
    REGION="asia-southeast1"
fi

echo -e "${BLUE}[INFO] Using Region: ${REGION}${NC}"

# 1. Health checks
echo -e "${YELLOW}>>> [1/4] Ensuring health check exists...${NC}"
gcloud compute health-checks create tcp my-ilb-health-check \
    --region="$REGION" \
    --port=80 \
    --check-interval=10s \
    --timeout=5s \
    --unhealthy-threshold=3 \
    --healthy-threshold=2 2>/dev/null || true

gcloud compute health-checks create tcp my-ilb-health-check \
    --port=80 \
    --check-interval=10s \
    --timeout=5s \
    --unhealthy-threshold=3 \
    --healthy-threshold=2 2>/dev/null || true

# 2. Regional Backend Service 'my-ilb'
echo -e "${YELLOW}>>> [2/4] Creating backend service 'my-ilb'...${NC}"
if ! gcloud compute backend-services describe my-ilb --region="$REGION" &>/dev/null; then
    gcloud compute backend-services create my-ilb \
        --load-balancing-scheme=internal \
        --protocol=TCP \
        --region="$REGION" \
        --health-checks=my-ilb-health-check \
        --health-checks-region="$REGION" 2>/dev/null || \
    gcloud compute backend-services create my-ilb \
        --load-balancing-scheme=internal \
        --protocol=TCP \
        --region="$REGION" \
        --health-checks=my-ilb-health-check
fi

# 3. Add backends
echo -e "${YELLOW}>>> [3/4] Attaching instance groups to backend service...${NC}"
ZONE_IG1=$(gcloud compute instance-groups managed list --filter="name ~ 'instance-group-1'" --format="value(zone)" 2>/dev/null | head -n1)
ZONE_IG2=$(gcloud compute instance-groups managed list --filter="name ~ 'instance-group-2'" --format="value(zone)" 2>/dev/null | head -n1)
if [ -z "$ZONE_IG1" ]; then ZONE_IG1="${REGION}-c"; fi
if [ -z "$ZONE_IG2" ]; then ZONE_IG2="${REGION}-a"; fi

gcloud compute backend-services add-backend my-ilb \
    --instance-group=instance-group-1 \
    --instance-group-zone="$ZONE_IG1" \
    --region="$REGION" 2>/dev/null || true

gcloud compute backend-services add-backend my-ilb \
    --instance-group=instance-group-2 \
    --instance-group-zone="$ZONE_IG2" \
    --region="$REGION" 2>/dev/null || true

# 4. Recreate Forwarding Rule pointing to 'my-ilb'
echo -e "${YELLOW}>>> [4/4] Updating Forwarding Rule 'my-ilb'...${NC}"
gcloud compute forwarding-rules delete my-ilb --region="$REGION" --quiet 2>/dev/null || true

gcloud compute forwarding-rules create my-ilb \
    --load-balancing-scheme=internal \
    --ports=80 \
    --network=my-internal-app \
    --subnet=subnet-b \
    --region="$REGION" \
    --backend-service=my-ilb \
    --backend-service-region="$REGION" \
    --address=my-ilb-ip

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}   Task 4 Backend Service fixed successfully! 🎉      ${NC}"
echo -e "${GREEN}   Click 'Check my progress' on Task 4 in the lab!    ${NC}"
echo -e "${GREEN}======================================================${NC}"
