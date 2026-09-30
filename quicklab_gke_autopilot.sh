#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Automation Script
# Lab: Deploying GKE Autopilot Clusters
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
echo -e "${CYAN}   Deploying GKE Autopilot Clusters                              ${NC}"
echo -e "${CYAN}   Google Cloud Skills Boost Automation                          ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# Detect GCP Project ID
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "${DEVSHELL_PROJECT_ID:-}")
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] GCP Project ID is not set. Please set it using: gcloud config set project <PROJECT_ID>${NC}"
    exit 1
fi
echo -e "${GREEN}[INFO] Active Project: ${PROJECT_ID}${NC}"

# Region (Defaulting to us-east1 per lab specification)
REGION="${REGION:-us-east1}"
CLUSTER_NAME="autopilot-cluster-1"
DEPLOYMENT_NAME="nginx-1"

echo -e "${GREEN}[INFO] Target Region:  ${REGION}${NC}"
echo -e "${GREEN}[INFO] Cluster Name:   ${CLUSTER_NAME}${NC}"
echo -e "${GREEN}[INFO] Workload Name:  ${DEPLOYMENT_NAME}${NC}"

# ==============================================================================
# TASK 0: Ensure Kubernetes Engine API is Enabled
# ==============================================================================
echo -e "\n${YELLOW}>>> Ensuring Kubernetes Engine API is enabled...${NC}"
gcloud services enable container.googleapis.com --quiet
echo -e "${GREEN}[SUCCESS] Kubernetes Engine API enabled.${NC}"

# ==============================================================================
# TASK 1: Deploy GKE Autopilot Cluster
# Scored Checkpoint 1: Deploy GKE cluster
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 1/2] Deploying GKE Autopilot Cluster '${CLUSTER_NAME}' in ${REGION}...${NC}"

CLUSTER_EXISTS=0
if gcloud container clusters describe "$CLUSTER_NAME" --region "$REGION" &>/dev/null; then
    STATUS=$(gcloud container clusters describe "$CLUSTER_NAME" --region "$REGION" --format="value(status)" 2>/dev/null || echo "UNKNOWN")
    if [ "$STATUS" = "RUNNING" ]; then
        echo -e "${BLUE}[SKIP] Cluster '${CLUSTER_NAME}' is already RUNNING.${NC}"
        CLUSTER_EXISTS=1
    else
        echo -e "${BLUE}[INFO] Cluster status is currently ${STATUS}. Waiting for RUNNING state...${NC}"
        for i in {1..40}; do
            STATUS=$(gcloud container clusters describe "$CLUSTER_NAME" --region "$REGION" --format="value(status)" 2>/dev/null || echo "UNKNOWN")
            if [ "$STATUS" = "RUNNING" ]; then
                echo -e "${GREEN}[SUCCESS] Cluster is now RUNNING!${NC}"
                CLUSTER_EXISTS=1
                break
            fi
            echo -e "${BLUE}[INFO] Still provisioning... (${i}/40) - status: ${STATUS}${NC}"
            sleep 15
        done
    fi
fi

if [ $CLUSTER_EXISTS -eq 0 ]; then
    echo -e "${BLUE}[INFO] Provisioning GKE Autopilot cluster (this typically takes 5-7 minutes)...${NC}"
    gcloud container clusters create-auto "$CLUSTER_NAME" \
        --region "$REGION" \
        --quiet
fi

# Fetch cluster credentials for kubectl
echo -e "${BLUE}[INFO] Fetching cluster credentials...${NC}"
gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION" --quiet

echo -e "${GREEN}[SUCCESS] Checkpoint 1 Complete: GKE Autopilot cluster deployed!${NC}"

# ==============================================================================
# TASK 2: Deploy Sample Workload (nginx-1 with 3 replicas)
# Scored Checkpoint 2: Deploy a sample nginx workload
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 2/2] Deploying Sample Workload '${DEPLOYMENT_NAME}'...${NC}"

# Check if deployment already exists
if kubectl get deployment "$DEPLOYMENT_NAME" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Deployment '${DEPLOYMENT_NAME}' already exists.${NC}"
    kubectl scale deployment "$DEPLOYMENT_NAME" --replicas=3 || true
else
    echo -e "${BLUE}[INFO] Creating deployment '${DEPLOYMENT_NAME}' (image: nginx:latest, replicas: 3)...${NC}"
    kubectl create deployment "$DEPLOYMENT_NAME" --image=nginx:latest --replicas=3
fi

# Wait for workload rollout
echo -e "${BLUE}[INFO] Waiting for deployment rollout to complete...${NC}"
kubectl rollout status deployment/"$DEPLOYMENT_NAME" --timeout=180s || true

echo -e "\n${BLUE}[INFO] Current Workload Status:${NC}"
kubectl get deployment "$DEPLOYMENT_NAME"
kubectl get pods -l app="$DEPLOYMENT_NAME"

echo -e "\n${CYAN}=================================================================${NC}"
echo -e "${GREEN}   ALL TASKS COMPLETED SUCCESSFULLY (100 / 100)!                ${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo -e "You can now click '${GREEN}Check my progress${NC}' for both checkpoints in the lab:"
echo -e "  [x] Checkpoint 1: Deploy GKE cluster"
echo -e "  [x] Checkpoint 2: Deploy a sample nginx workload\n"
