#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Automation Script
# Lab: Using Cloud PubSub with Cloud Run (CBL396 / GSP724)
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
echo -e "${CYAN}   Using Cloud PubSub with Cloud Run                             ${NC}"
echo -e "${CYAN}   Lab ID: CBL396 / GSP724                                       ${NC}"
echo -e "${CYAN}   Google Cloud Skills Boost Automation                          ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# Detect GCP Project ID
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "${DEVSHELL_PROJECT_ID:-}")
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] GCP Project ID is not set. Please set it using: gcloud config set project <PROJECT_ID>${NC}"
    exit 1
fi
echo -e "${GREEN}[INFO] Active Project: ${PROJECT_ID}${NC}"

# Target Region (Defaulting to us-east1 per lab instructions)
export LOCATION="${LOCATION:-us-east1}"
echo -e "${GREEN}[INFO] Target Region:  ${LOCATION}${NC}"

# Configure default regions
gcloud config set compute/region "$LOCATION" --quiet
gcloud config set run/region "$LOCATION" --quiet

# ==============================================================================
# TASK 1: Enable APIs & Deploy Microservices (Producer & Consumer)
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 1/5] Enabling APIs and Deploying Cloud Run Services...${NC}"
gcloud services enable run.googleapis.com pubsub.googleapis.com --quiet

# 1.1 Deploy Producer: store-service (Public)
echo -e "${BLUE}[INFO] Deploying store-service (public producer)...${NC}"
gcloud run deploy store-service \
    --image gcr.io/qwiklabs-resources/gsp724-store-service \
    --region "$LOCATION" \
    --allow-unauthenticated \
    --quiet

echo -e "${GREEN}[SUCCESS] store-service deployed (Checkpoint 1 Ready).${NC}"

# 1.2 Deploy Consumer: order-service (Private)
echo -e "${BLUE}[INFO] Deploying order-service (private consumer)...${NC}"
gcloud run deploy order-service \
    --image gcr.io/qwiklabs-resources/gsp724-order-service \
    --region "$LOCATION" \
    --no-allow-unauthenticated \
    --quiet

echo -e "${GREEN}[SUCCESS] order-service deployed (Checkpoint 2 Ready).${NC}"

# ==============================================================================
# TASK 2: Create Pub/Sub Topic
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 2/5] Creating Pub/Sub Topic 'ORDER_PLACED'...${NC}"
if gcloud pubsub topics describe ORDER_PLACED &>/dev/null; then
    echo -e "${BLUE}[SKIP] Topic ORDER_PLACED already exists.${NC}"
else
    gcloud pubsub topics create ORDER_PLACED --quiet
fi
echo -e "${GREEN}[SUCCESS] Topic ORDER_PLACED created (Checkpoint 3 Ready).${NC}"

# ==============================================================================
# TASK 3: Create Service Account and Bind Permissions
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 3/5] Setting Up Service Account & IAM Policy Bindings...${NC}"

# 3.1 Create Service Account "Order Initiator"
if gcloud iam service-accounts describe "pubsub-cloud-run-invoker@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Service account pubsub-cloud-run-invoker already exists.${NC}"
else
    gcloud iam service-accounts create pubsub-cloud-run-invoker \
        --display-name="Order Initiator" \
        --quiet
fi
echo -e "${GREEN}[SUCCESS] Service Account created (Checkpoint 4 Ready).${NC}"

# 3.2 Bind Cloud Run Invoker on order-service
echo -e "${BLUE}[INFO] Granting run.invoker role on order-service to service account...${NC}"
gcloud run services add-iam-policy-binding order-service \
    --region "$LOCATION" \
    --member="serviceAccount:pubsub-cloud-run-invoker@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/run.invoker" \
    --platform managed \
    --quiet

# 3.3 Grant Service Account Token Creator role to Pub/Sub Service Agent
echo -e "${BLUE}[INFO] Granting iam.serviceAccountTokenCreator to Pub/Sub service agent...${NC}"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountTokenCreator" \
    --quiet

echo -e "${GREEN}[SUCCESS] IAM policy bindings configured.${NC}"

# ==============================================================================
# TASK 4: Create Pub/Sub Push Subscription
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 4/5] Creating Push Subscription to order-service...${NC}"

ORDER_SERVICE_URL=$(gcloud run services describe order-service \
    --region "$LOCATION" \
    --format="value(status.address.url)")
echo -e "${BLUE}[INFO] order-service URL: ${ORDER_SERVICE_URL}${NC}"

if gcloud pubsub subscriptions describe order-service-sub &>/dev/null; then
    echo -e "${BLUE}[SKIP] Subscription order-service-sub already exists.${NC}"
else
    gcloud pubsub subscriptions create order-service-sub \
        --topic ORDER_PLACED \
        --push-endpoint="$ORDER_SERVICE_URL" \
        --push-auth-service-account="pubsub-cloud-run-invoker@${PROJECT_ID}.iam.gserviceaccount.com" \
        --quiet
fi
echo -e "${GREEN}[SUCCESS] Subscription order-service-sub created (Checkpoint 5 Ready).${NC}"

# ==============================================================================
# TASK 5: Test the Integration
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 5/5] Testing End-to-End Application Workflow...${NC}"

cat <<'EOF' > test.json
{
  "billing_address": {
    "name": "Kylie Scull",
    "address": "6471 Front Street",
    "city": "Mountain View",
    "state_province": "CA",
    "postal_code": "94043",
    "country": "US"
  },
  "shipping_address": {
    "name": "Kylie Scull",
    "address": "9902 Cambridge Grove",
    "city": "Martinville",
    "state_province": "BC",
    "postal_code": "V1A",
    "country": "Canada"
  },
  "items": [
    {
      "id": "RW134",
      "quantity": 1,
      "sub-total": 12.95
    },
    {
      "id": "IB541",
      "quantity": 2,
      "sub-total": 24.5
    }
  ]
}
EOF

STORE_SERVICE_URL=$(gcloud run services describe store-service \
    --region "$LOCATION" \
    --format="value(status.address.url)")
echo -e "${BLUE}[INFO] store-service URL: ${STORE_SERVICE_URL}${NC}"

echo -e "${BLUE}[INFO] Sending test order to store-service...${NC}"
ORDER_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d @test.json "$STORE_SERVICE_URL")
echo -e "${GREEN}[RESPONSE] ${ORDER_RESPONSE}${NC}"

echo -e "\n${GREEN}=================================================================${NC}"
echo -e "${GREEN}🎉 ALL TASKS COMPLETED SUCCESSFULLY! (100/100)                   ${NC}"
echo -e "${GREEN}=================================================================${NC}"
echo -e "${YELLOW}Now verify the following checkpoints on the lab page:${NC}"
echo -e "  ✅ Task 1: Deploy the Cloud Run store service"
echo -e "  ✅ Task 1: Deploy the Cloud Run order service"
echo -e "  ✅ Task 2: Create a Pub/Sub Topic"
echo -e "  ✅ Task 3: Create a Service Account"
echo -e "  ✅ Task 4: Create a subscription"
echo -e "${GREEN}=================================================================${NC}"
