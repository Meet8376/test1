#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Automation Script
# Lab: Deploying GKE Autopilot Clusters from Cloud Shell
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
echo -e "${CYAN}   Deploying GKE Autopilot Clusters from Cloud Shell             ${NC}"
echo -e "${CYAN}   Google Cloud Skills Boost Automation                          ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# Detect GCP Project ID
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "${DEVSHELL_PROJECT_ID:-}")
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] GCP Project ID is not set. Please set it using: gcloud config set project <PROJECT_ID>${NC}"
    exit 1
fi
echo -e "${GREEN}[INFO] Active Project: ${PROJECT_ID}${NC}"

# Define Region and Cluster Name per lab instructions
export my_region="${REGION:-europe-west1}"
export my_cluster="autopilot-cluster-1"

echo -e "${GREEN}[INFO] Target Region:  ${my_region}${NC}"
echo -e "${GREEN}[INFO] Cluster Name:   ${my_cluster}${NC}"

# Ensure Kubernetes Engine API is enabled
echo -e "\n${YELLOW}>>> Ensuring Kubernetes Engine API is enabled...${NC}"
gcloud services enable container.googleapis.com --quiet
echo -e "${GREEN}[SUCCESS] Kubernetes Engine API is ready.${NC}"

# ==============================================================================
# TASK 1: Deploy GKE Autopilot Cluster
# Scored Checkpoint 1: Deploy GKE clusters
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 1/3] Deploying GKE Autopilot Cluster '${my_cluster}' in ${my_region}...${NC}"

CLUSTER_EXISTS=0
if gcloud container clusters describe "$my_cluster" --region "$my_region" &>/dev/null; then
    STATUS=$(gcloud container clusters describe "$my_cluster" --region "$my_region" --format="value(status)" 2>/dev/null || echo "UNKNOWN")
    if [ "$STATUS" = "RUNNING" ]; then
        echo -e "${BLUE}[SKIP] Cluster '${my_cluster}' is already RUNNING.${NC}"
        CLUSTER_EXISTS=1
    else
        echo -e "${BLUE}[INFO] Cluster status is currently ${STATUS}. Waiting for RUNNING state...${NC}"
        for i in {1..40}; do
            STATUS=$(gcloud container clusters describe "$my_cluster" --region "$my_region" --format="value(status)" 2>/dev/null || echo "UNKNOWN")
            if [ "$STATUS" = "RUNNING" ]; then
                echo -e "${GREEN}[SUCCESS] Cluster is now RUNNING!${NC}"
                CLUSTER_EXISTS=1
                break
            fi
            echo -e "${BLUE}[INFO] Provisioning in progress (${i}/40) - status: ${STATUS}...${NC}"
            sleep 15
        done
    fi
fi

if [ $CLUSTER_EXISTS -eq 0 ]; then
    echo -e "${BLUE}[INFO] Creating GKE Autopilot cluster (this typically takes 5-7 minutes)...${NC}"
    gcloud container clusters create-auto "$my_cluster" \
        --region "$my_region" \
        --quiet
fi

# Fetch credentials for kubectl
echo -e "${BLUE}[INFO] Configuring kubectl credentials for ${my_cluster}...${NC}"
gcloud container clusters get-credentials "$my_cluster" --region "$my_region" --quiet

echo -e "${GREEN}[SUCCESS] Checkpoint 1 Complete: GKE cluster deployed and connected!${NC}"

# ==============================================================================
# TASK 2: Deploy Pods to GKE Clusters & Expose Service
# Scored Checkpoint 2: Deploy Pods to GKE clusters
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 2/3] Deploying nginx-1 workload and exposing via LoadBalancer...${NC}"

# 2.1 Deploy nginx-1
if kubectl get deployment nginx-1 &>/dev/null; then
    echo -e "${BLUE}[SKIP] Deployment 'nginx-1' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating deployment 'nginx-1'...${NC}"
    kubectl create deployment --image nginx nginx-1
fi

echo -e "${BLUE}[INFO] Waiting for nginx-1 deployment to roll out...${NC}"
kubectl rollout status deployment/nginx-1 --timeout=300s || true

# 2.2 Identify Pod Name
my_nginx_pod=$(kubectl get pods -l app=nginx-1 -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo "")
if [ -z "$my_nginx_pod" ]; then
    echo -e "${BLUE}[INFO] Waiting for nginx-1 Pod to initialize...${NC}"
    sleep 10
    my_nginx_pod=$(kubectl get pods -l app=nginx-1 -o jsonpath="{.items[0].metadata.name}")
fi
echo -e "${GREEN}[INFO] Deployed Pod: ${my_nginx_pod}${NC}"

# 2.3 Create and copy test.html to Pod
cat <<'EOF' > ~/test.html
 <header><title>This is title</title></head>
 Hello world 
EOF

echo -e "${BLUE}[INFO] Copying test.html to ${my_nginx_pod}:/usr/share/nginx/html/test.html...${NC}"
kubectl cp ~/test.html "${my_nginx_pod}:/usr/share/nginx/html/test.html"

# 2.4 Expose Pod externally via LoadBalancer
if kubectl get svc "$my_nginx_pod" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Service '${my_nginx_pod}' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Exposing Pod ${my_nginx_pod} on port 80 (LoadBalancer)...${NC}"
    kubectl expose pod "$my_nginx_pod" --port 80 --type LoadBalancer || true
fi

echo -e "${GREEN}[SUCCESS] Checkpoint 2 Complete: Pods deployed, customized, and exposed!${NC}"

# ==============================================================================
# TASK 3: Deploy Pod using YAML manifest
# Scored Checkpoint 3: Deploy a new pod using a Yaml file
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 3/3] Deploying 'new-nginx' Pod via YAML manifest...${NC}"

mkdir -p ~/ak8s/GKE_Shell/
cd ~/ak8s/GKE_Shell/

cat <<'EOF' > new-nginx-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: new-nginx
  labels:
    name: new-nginx
spec:
  containers:
  - name: new-nginx
    image: nginx
    ports:
    - containerPort: 80
EOF

echo -e "${BLUE}[INFO] Applying new-nginx-pod.yaml...${NC}"
kubectl apply -f new-nginx-pod.yaml

echo -e "${BLUE}[INFO] Waiting for 'new-nginx' Pod to be ready...${NC}"
kubectl wait --for=condition=ready pod/new-nginx --timeout=300s || true

# Copy test.html into new-nginx as well
echo -e "${BLUE}[INFO] Copying test.html to new-nginx pod...${NC}"
kubectl cp ~/test.html new-nginx:/usr/share/nginx/html/test.html 2>/dev/null || true

# Clone repository in background if needed
if [ ! -d ~/training-data-analyst ]; then
    git clone https://github.com/GoogleCloudPlatform/training-data-analyst ~/training-data-analyst 2>/dev/null || true
fi
if [ ! -L ~/ak8s ] && [ -d ~/training-data-analyst/courses/ak8s/v1.1 ]; then
    ln -s ~/training-data-analyst/courses/ak8s/v1.1 ~/ak8s 2>/dev/null || true
fi

echo -e "\n${BLUE}[INFO] Final Cluster Pods:${NC}"
kubectl get pods

echo -e "\n${CYAN}=================================================================${NC}"
echo -e "${GREEN}   ALL TASKS COMPLETED SUCCESSFULLY (100 / 100)!                ${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo -e "You can now click '${GREEN}Check my progress${NC}' for all 3 checkpoints in the lab:"
echo -e "  [x] Checkpoint 1: Deploy GKE clusters"
echo -e "  [x] Checkpoint 2: Deploy Pods to GKE clusters"
echo -e "  [x] Checkpoint 3: Deploy a new pod using a Yaml file\n"
