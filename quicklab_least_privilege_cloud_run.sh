#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Automation Script
# Lab: Implementing Least Privilege IAM Policy Bindings in Cloud Run (CBL418)
# ==============================================================================

set -uo pipefail

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

pause_step() {
    local prompt_msg="$1"
    echo -e "\n${YELLOW}=================================================================${NC}"
    echo -e "${YELLOW}${prompt_msg}${NC}"
    echo -e "${YELLOW}=================================================================${NC}"
    if [ -t 0 ]; then
        read -p "Press [Enter] once verified to continue..."
    elif [ -e /dev/tty ]; then
        read -p "Press [Enter] once verified to continue..." < /dev/tty
    else
        echo "Continuing in 10 seconds..."
        sleep 10
    fi
}

echo -e "${CYAN}=================================================================${NC}"
echo -e "${CYAN}   Implementing Least Privilege IAM Policy Bindings in Cloud Run  ${NC}"
echo -e "${CYAN}   Lab ID: CBL418 / GSP723                                       ${NC}"
echo -e "${CYAN}   Google Cloud Skills Boost Automation                          ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# Detect GCP Project ID
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "${DEVSHELL_PROJECT_ID:-}")
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] GCP Project ID is not set. Please set it using: gcloud config set project <PROJECT_ID>${NC}"
    exit 1
fi
echo -e "${GREEN}[INFO] Active Project: ${PROJECT_ID}${NC}"

# Detect active student admin account
export STUDENT_ACCOUNT=$(gcloud config get-value account 2>/dev/null)
echo -e "${GREEN}[INFO] Student Account: ${STUDENT_ACCOUNT}${NC}"

# Region (Defaulting to europe-west1 per lab instructions)
REGION="${REGION:-europe-west1}"
echo -e "${GREEN}[INFO] Target Region:  ${REGION}${NC}"

# ==============================================================================
# TASK 1: Configure Environment & Enable Cloud Run API
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 1/5] Enabling Cloud Run API & Setting Region...${NC}"
gcloud services enable run.googleapis.com --quiet
gcloud config set run/region "$REGION"
echo -e "${GREEN}[SUCCESS] Cloud Run API enabled and default region set to ${REGION}.${NC}"

# ==============================================================================
# TASK 2: Create and Deploy a Public Service
# Checkpoint 1: Deploy a public Cloud Run Service
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 2/5] Deploying public billing-service...${NC}"
gcloud run deploy billing-service \
    --image gcr.io/qwiklabs-resources/gsp723-parking-service \
    --region "$REGION" \
    --allow-unauthenticated \
    --quiet

BILLING_SERVICE_URL=$(gcloud run services list --format='value(URL)' --filter="billing-service")
echo -e "${BLUE}[INFO] Billing Service URL: ${BILLING_SERVICE_URL}${NC}"

echo -e "${BLUE}[INFO] Testing unauthenticated invocation...${NC}"
curl -s -X POST -H "Content-Type: application/json" "$BILLING_SERVICE_URL" -d '{"userid": "1234", "minBalance": 100}'
echo -e "${GREEN}[SUCCESS] Public service deployed and tested.${NC}"

pause_step "👉 CHECKPOINT 1: Click 'Check my progress' for:\n   [Task 2] Deploy a public Cloud Run Service"

# ==============================================================================
# TASK 3: Authenticating Service Requests & Creating Service Account
# Checkpoint 2: Create a service account
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 3/5] Securing billing-service & creating service account...${NC}"

# 3.1 Delete existing public service
echo -e "${BLUE}[INFO] Deleting unauthenticated billing-service...${NC}"
gcloud run services delete billing-service --region "$REGION" --quiet

# 3.2 Redeploy with no unauthenticated access
echo -e "${BLUE}[INFO] Redeploying billing-service with --no-allow-unauthenticated...${NC}"
gcloud run deploy billing-service \
    --image gcr.io/qwiklabs-resources/gsp723-parking-service \
    --region "$REGION" \
    --no-allow-unauthenticated \
    --quiet

BILLING_SERVICE_URL=$(gcloud run services list --format='value(URL)' --filter="billing-service")

# 3.3 Create service account "Billing Initiator"
echo -e "${BLUE}[INFO] Creating service account 'Billing Initiator'...${NC}"
gcloud iam service-accounts create billing-initiator \
    --display-name="Billing Initiator" \
    --quiet || true

export BILLING_INITIATOR_EMAIL=$(gcloud iam service-accounts list --filter="displayName:Billing Initiator" --format="value(email)")
echo -e "${GREEN}[INFO] Service Account Email: ${BILLING_INITIATOR_EMAIL}${NC}"

# 3.4 Grant project-level Cloud Run Invoker role
echo -e "${BLUE}[INFO] Granting roles/run.invoker to service account at project level...${NC}"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${BILLING_INITIATOR_EMAIL}" \
    --role="roles/run.invoker" \
    --quiet

echo -e "${GREEN}[SUCCESS] Service account created and project role assigned.${NC}"

pause_step "👉 CHECKPOINT 2: Click 'Check my progress' for:\n   [Task 3] Create a service account"

# ==============================================================================
# TASK 4: Invoke the Service with Authentication
# Checkpoint 3: Invoke a Cloud Run service with authentication
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 4/5] Generating SA key & invoking service with auth token...${NC}"

# 4.1 Create key file
gcloud iam service-accounts keys create key.json --iam-account="${BILLING_INITIATOR_EMAIL}" --quiet

# 4.2 Activate service account
echo -e "${BLUE}[INFO] Activating service account credentials...${NC}"
gcloud auth activate-service-account --key-file=key.json

# 4.3 Invoke service with identity token
echo -e "${BLUE}[INFO] Invoking billing-service with service account identity token...${NC}"
curl -s -X POST -H "Content-Type: application/json" \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    "$BILLING_SERVICE_URL" -d '{"userid": "1234", "minBalance": 500}'

# 4.4 Switch back to student admin account
echo -e "${BLUE}[INFO] Switching back to student administrator account...${NC}"
gcloud config set account "$STUDENT_ACCOUNT"

echo -e "${GREEN}[SUCCESS] Authenticated invocation completed.${NC}"

pause_step "👉 CHECKPOINT 3: Click 'Check my progress' for:\n   [Task 4] Invoke a Cloud Run service with authentication"

# ==============================================================================
# TASK 5: Implement Least Privilege
# Checkpoint 4: Use least privilege to invoke a Cloud Run service
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 5/5] Deploying second service & enforcing least privilege...${NC}"

# 5.1 Deploy second service
echo -e "${BLUE}[INFO] Deploying billing-service-2...${NC}"
gcloud run deploy billing-service-2 \
    --image gcr.io/qwiklabs-resources/gsp723-parking-service \
    --region "$REGION" \
    --no-allow-unauthenticated \
    --quiet

BILLING_SERVICE_2_URL=$(gcloud run services list --format='value(URL)' --filter="billing-service-2")

# 5.2 Test that service account can invoke second service (due to project inheritance)
echo -e "${BLUE}[INFO] Testing that SA currently has broad access to billing-service-2...${NC}"
gcloud auth activate-service-account --key-file=key.json
curl -s -X POST -H "Content-Type: application/json" \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    "$BILLING_SERVICE_2_URL" -d '{"userid": "1234", "minBalance": 900}'

# Switch back to student account to modify IAM policies
gcloud config set account "$STUDENT_ACCOUNT"

# 5.3 Remove broad project-level role
echo -e "${BLUE}[INFO] Removing broad project-level invoker role...${NC}"
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${BILLING_INITIATOR_EMAIL}" \
    --role="roles/run.invoker" \
    --quiet

# 5.4 Add permission to service account on billing-service only
echo -e "${BLUE}[INFO] Adding invoker role to billing-service only (least privilege)...${NC}"
gcloud run services add-iam-policy-binding billing-service \
    --region "$REGION" \
    --member="serviceAccount:${BILLING_INITIATOR_EMAIL}" \
    --role="roles/run.invoker" \
    --platform managed \
    --quiet

# 5.5 Test least privilege enforcement
echo -e "${BLUE}[INFO] Verifying least privilege access...${NC}"
gcloud auth activate-service-account --key-file=key.json
sleep 5

echo -e "${BLUE}[TEST 1] Invoking billing-service (Should SUCCEED):${NC}"
curl -s -X POST -H "Content-Type: application/json" \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    "$BILLING_SERVICE_URL" -d '{"userid": "1234", "minBalance": 700}'
echo ""

echo -e "${BLUE}[TEST 2] Invoking billing-service-2 (Should FAIL with 403 Forbidden):${NC}"
curl -s -X POST -H "Content-Type: application/json" \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    "$BILLING_SERVICE_2_URL" -d '{"userid": "1234", "minBalance": 500}'
echo ""

# Reset account to student
gcloud config set account "$STUDENT_ACCOUNT"

echo -e "\n${GREEN}=================================================================${NC}"
echo -e "${GREEN}🎉 ALL TASKS COMPLETE! 100/100 READY                             ${NC}"
echo -e "${YELLOW}👉 Click 'Check my progress' for:                               ${NC}"
echo -e "${GREEN}   [Task 5] Use least privilege to invoke a Cloud Run service    ${NC}"
echo -e "${GREEN}=================================================================${NC}"
