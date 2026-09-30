#!/bin/bash
# ==============================================================================
# Verification Script: Validate Internal Load Balancer & Lab Resources
# ==============================================================================

set -euo pipefail

REGION="${REGION:-asia-east1}"
ZONE_UTILITY="${ZONE_UTILITY:-asia-east1-b}"

echo "=========================================================="
echo " 1. Firewall Rules Verification"
echo "=========================================================="
gcloud compute firewall-rules list \
    --filter="name:(fw-allow-lb-access OR fw-allow-health-checks)" \
    --format="table(name,network,allowed,sourceRanges.list(),targetTags.list())"

echo -e "\n=========================================================="
echo " 2. Cloud Router & Cloud NAT Verification"
echo "=========================================================="
gcloud compute routers list --filter="name ~ 'nat-router'" --format="table(name,network,region)"
gcloud compute routers nats list --router="nat-router-$REGION" --region="$REGION" --format="table(name,natIpAllocateOption,sourceSubnetworkIpRangesToNat)"

echo -e "\n=========================================================="
echo " 3. VM Instances Status"
echo "=========================================================="
gcloud compute instances list \
    --filter="zone ~ '$REGION'" \
    --format="table(name,zone,networkInterfaces[0].networkIP,status)"

echo -e "\n=========================================================="
echo " 4. Load Balancer Backend Service Health"
echo "=========================================================="
gcloud compute backend-services get-health my-ilb --region="$REGION" 2>/dev/null || \
gcloud compute backend-services get-health my-ilb-backend-service --region="$REGION" || true

echo -e "\n=========================================================="
echo " 5. Load Balancer Forwarding Rule"
echo "=========================================================="
gcloud compute forwarding-rules describe my-ilb --region="$REGION" \
    --format="table(name,IPAddress,portRange,loadBalancingScheme,backendService.basename())"

echo -e "\n=========================================================="
echo " 6. Active Traffic Test via utility-vm"
echo "=========================================================="
gcloud compute ssh utility-vm --zone="$ZONE_UTILITY" --tunnel-through-iap --quiet --command="
echo 'Curling Load Balancer IP (10.10.30.5) 5 times:'
for i in {1..5}; do
    echo -n \"Response \$i: \"
    curl -s -m 3 http://10.10.30.5 | grep -o 'Server Hostname: [^<]*' || echo 'No response'
done
"
