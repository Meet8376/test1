#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Automation Script
# Lab: Working with Cloud Build (CBL139)
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
echo -e "${CYAN}   Working with Cloud Build (CBL139)                             ${NC}"
echo -e "${CYAN}   Google Cloud Skills Boost Automation                          ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# Detect GCP Project ID
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "${DEVSHELL_PROJECT_ID:-}")
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] GCP Project ID is not set. Please set it using: gcloud config set project <PROJECT_ID>${NC}"
    exit 1
fi
echo -e "${GREEN}[INFO] Active Project: ${PROJECT_ID}${NC}"

# Region (Defaulting to europe-west1 per lab instructions)
REGION="${REGION:-europe-west1}"
echo -e "${GREEN}[INFO] Target Region:  ${REGION}${NC}"

# ==============================================================================
# TASK 1: Confirm APIs are Enabled
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 1/4] Ensuring Required APIs are Enabled...${NC}"
gcloud services enable cloudbuild.googleapis.com artifactregistry.googleapis.com --quiet
echo -e "${GREEN}[SUCCESS] Cloud Build and Artifact Registry APIs enabled.${NC}"

# ==============================================================================
# TASK 2: Build Container using Dockerfile & Cloud Build (First Build)
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 2/4] Setting up Artifact Registry & First Docker Image Build...${NC}"

# 2.1 Create Artifact Registry repository if not exists
if gcloud artifacts repositories describe quickstart-docker-repo --location="$REGION" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Artifact Registry repo 'quickstart-docker-repo' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating Artifact Registry Docker repository 'quickstart-docker-repo'...${NC}"
    gcloud artifacts repositories create quickstart-docker-repo \
        --repository-format=docker \
        --location="$REGION" \
        --description="Docker repository" \
        --quiet
fi

# 2.2 Create quickstart.sh
cat <<'EOF' > quickstart.sh
#!/bin/sh
echo "Hello, world! The time is $(date)."
EOF
chmod +x quickstart.sh

# 2.3 Create Dockerfile
cat <<'EOF' > Dockerfile
FROM alpine
COPY quickstart.sh /
CMD ["/quickstart.sh"]
EOF

# 2.4 Submit First Build via Dockerfile
IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/quickstart-docker-repo/quickstart-image:tag1"
echo -e "${BLUE}[INFO] Submitting Build #1 via direct Dockerfile tag (${IMAGE_TAG})...${NC}"
gcloud builds submit --tag "$IMAGE_TAG"

echo -e "${GREEN}[SUCCESS] Image #1 built and pushed successfully!${NC}"

# ==============================================================================
# TASK 3: Build Container using Custom Build Config (cloudbuild.yaml) (Second Build)
# Scored Checkpoint 1: Build two container images in Cloud Build
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 3/4] Creating cloudbuild.yaml and Submitting Build #2...${NC}"

cat <<EOF > cloudbuild.yaml
steps:
- name: 'gcr.io/cloud-builders/docker'
  args: [ 'build', '-t', '${REGION}-docker.pkg.dev/\$PROJECT_ID/quickstart-docker-repo/quickstart-image:tag1', '.' ]
images:
- '${REGION}-docker.pkg.dev/\$PROJECT_ID/quickstart-docker-repo/quickstart-image:tag1'
EOF

echo -e "${BLUE}[INFO] Submitting Build #2 using cloudbuild.yaml...${NC}"
gcloud builds submit --config cloudbuild.yaml

echo -e "${GREEN}[SUCCESS] Checkpoint 1 Complete: Two container images built in Cloud Build!${NC}"

# ==============================================================================
# TASK 4: Test Containers using Build Configuration File (cloudbuild2.yaml)
# Scored Checkpoint 2: Build and test containers with a build configuration file and Cloud Build
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 4/4] Configuring Automated Failure Test via cloudbuild2.yaml...${NC}"

# 4.1 Update quickstart.sh to simulate test failure when argument is passed
cat <<'EOF' > quickstart.sh
#!/bin/sh
if [ -z "$1" ]
then
    echo "Hello, world! The time is $(date)."
    exit 0
else
    exit 1
fi
EOF
chmod +x quickstart.sh

# 4.2 Create cloudbuild2.yaml
cat <<EOF > cloudbuild2.yaml
steps:
- name: 'gcr.io/cloud-builders/docker'
  args: [ 'build', '-t', '${REGION}-docker.pkg.dev/\$PROJECT_ID/quickstart-docker-repo/quickstart-image:tag1', '.' ]
- name: '${REGION}-docker.pkg.dev/\$PROJECT_ID/quickstart-docker-repo/quickstart-image:tag1'
  args: ['fail']
images:
- '${REGION}-docker.pkg.dev/\$PROJECT_ID/quickstart-docker-repo/quickstart-image:tag1'
EOF

# 4.3 Submit Build #3 (Expected intentional test failure)
echo -e "${BLUE}[INFO] Submitting Build #3 using cloudbuild2.yaml (Expected intentional test failure)...${NC}"
gcloud builds submit --config cloudbuild2.yaml || true

echo -e "\n${CYAN}=================================================================${NC}"
echo -e "${GREEN}   ALL TASKS COMPLETED SUCCESSFULLY (100 / 100)!                ${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo -e "You can now click '${GREEN}Check my progress${NC}' for both checkpoints in the lab:"
echo -e "  [x] Checkpoint 1: Build two container images in Cloud Build"
echo -e "  [x] Checkpoint 2: Build and test containers with a build configuration file and Cloud Build\n"
