#!/bin/bash
# ==============================================================================
# Quick Reference Commands for Lab: Configure an Internal Network Load Balancer
# Run these commands directly in Google Cloud Shell
# ==============================================================================

# Define Environment Variables
export REGION="asia-southeast1"
export ZONE_UTILITY="asia-southeast1-b"
export ZONE_IG1="asia-southeast1-c"
export ZONE_IG2="asia-southeast1-a"
export NETWORK="my-internal-app"
export SUBNET_A="subnet-a"
export SUBNET_B="subnet-b"

gcloud config set compute/region "$REGION"

# ------------------------------------------------------------------------------
# Task 1: Configure internal traffic and health check firewall rules
# ------------------------------------------------------------------------------
gcloud compute firewall-rules create fw-allow-lb-access \
    --network=$NETWORK \
    --action=ALLOW \
    --direction=INGRESS \
    --source-ranges=10.10.0.0/16 \
    --target-tags=backend-service \
    --rules=all

gcloud compute firewall-rules create fw-allow-health-checks \
    --network=$NETWORK \
    --action=ALLOW \
    --direction=INGRESS \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=backend-service \
    --rules=tcp:80

# ------------------------------------------------------------------------------
# Task 2: Create a NAT configuration using Cloud Router
# ------------------------------------------------------------------------------
gcloud compute routers create nat-router-$REGION \
    --network=$NETWORK \
    --region=$REGION

gcloud compute routers nats create nat-config \
    --router=nat-router-$REGION \
    --region=$REGION \
    --auto-allocate-nat-external-ips \
    --nat-all-subnet-ip-ranges

# ------------------------------------------------------------------------------
# Task 3: Configure instance templates and create instance groups
# ------------------------------------------------------------------------------
# Re-run startup scripts on both backend instances
VM1=$(gcloud compute instances list --filter="name ~ 'instance-group-1'" --format="value(name)" | head -n1)
VM2=$(gcloud compute instances list --filter="name ~ 'instance-group-2'" --format="value(name)" | head -n1)

ZONE_IG1=$(gcloud compute instances list --filter="name='$VM1'" --format="value(zone)" 2>/dev/null | head -n1)
ZONE_IG2=$(gcloud compute instances list --filter="name='$VM2'" --format="value(zone)" 2>/dev/null | head -n1)

gcloud compute ssh "$VM1" --zone="$ZONE_IG1" --tunnel-through-iap --quiet --command="sudo google_metadata_script_runner startup"
gcloud compute ssh "$VM2" --zone="$ZONE_IG2" --tunnel-through-iap --quiet --command="sudo google_metadata_script_runner startup"

# Create utility-vm
gcloud compute instances create utility-vm \
    --zone=$ZONE_UTILITY \
    --machine-type=e2-medium \
    --network=$NETWORK \
    --subnet=$SUBNET_A \
    --private-network-ip=10.10.20.50 \
    --no-address \
    --image-family=debian-12 \
    --image-project=debian-cloud

# Test connection to backends from utility-vm
gcloud compute ssh utility-vm --zone=$ZONE_UTILITY --tunnel-through-iap --quiet --command="curl -s 10.10.20.2 && curl -s 10.10.30.2"

# ------------------------------------------------------------------------------
# Task 4: Configure the internal Network Load Balancer
# ------------------------------------------------------------------------------
# Reserve regional internal IP
gcloud compute addresses create my-ilb-ip \
    --region=$REGION \
    --subnet=$SUBNET_B \
    --addresses=10.10.30.5

# Create TCP health check (regional & global)
gcloud compute health-checks create tcp my-ilb-health-check \
    --region=$REGION \
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

# Create regional backend service (named 'my-ilb' to match lab requirement)
gcloud compute backend-services create my-ilb \
    --load-balancing-scheme=internal \
    --protocol=TCP \
    --region=$REGION \
    --health-checks=my-ilb-health-check \
    --health-checks-region=$REGION 2>/dev/null || \
gcloud compute backend-services create my-ilb \
    --load-balancing-scheme=internal \
    --protocol=TCP \
    --region=$REGION \
    --health-checks=my-ilb-health-check

# Add instance groups to backend service
gcloud compute backend-services add-backend my-ilb \
    --instance-group=instance-group-1 \
    --instance-group-zone=$ZONE_IG1 \
    --region=$REGION 2>/dev/null || true

gcloud compute backend-services add-backend my-ilb \
    --instance-group=instance-group-2 \
    --instance-group-zone=$ZONE_IG2 \
    --region=$REGION 2>/dev/null || true

# Create forwarding rule
gcloud compute forwarding-rules delete my-ilb --region=$REGION --quiet 2>/dev/null || true

gcloud compute forwarding-rules create my-ilb \
    --load-balancing-scheme=internal \
    --ports=80 \
    --network=$NETWORK \
    --subnet=$SUBNET_B \
    --region=$REGION \
    --backend-service=my-ilb \
    --backend-service-region=$REGION \
    --address=my-ilb-ip

# ------------------------------------------------------------------------------
# Task 5: Test the internal Network Load Balancer
# ------------------------------------------------------------------------------
gcloud compute ssh utility-vm --zone=$ZONE_UTILITY --tunnel-through-iap --quiet --command="
for i in {1..10}; do
    curl -s 10.10.30.5 | grep -E 'Server Hostname|Server Location'
done
"
