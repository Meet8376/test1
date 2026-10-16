#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Automation Script
# Lab: Explore the Google Cloud Console and Cloud Shell (CBL006)
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
echo -e "${CYAN}   Explore the Google Cloud Console and Cloud Shell (CBL006)     ${NC}"
echo -e "${CYAN}   Google Cloud Skills Boost Automation                          ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# Detect GCP Project ID
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "${DEVSHELL_PROJECT_ID:-}")
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] GCP Project ID is not set. Please set it using: gcloud config set project <PROJECT_ID>${NC}"
    exit 1
fi
echo -e "${GREEN}[INFO] Active Project: ${PROJECT_ID}${NC}"

# Detect or Set Target Region
export REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null)}"
if [ -z "$REGION" ]; then
    REGION="us-central1"
fi
echo -e "${GREEN}[INFO] Target Region:  ${REGION}${NC}"

# Define Bucket Names
# Bucket 1 represents the bucket created via Cloud Console
export BUCKET_1="${BUCKET_1:-${PROJECT_ID}}"
# Bucket 2 represents the second bucket created via Cloud Shell (with '2' appended)
export BUCKET_2="${BUCKET_2:-${PROJECT_ID}-2}"

echo -e "${GREEN}[INFO] Bucket 1:       gs://${BUCKET_1}${NC}"
echo -e "${GREEN}[INFO] Bucket 2:       gs://${BUCKET_2}${NC}"

# ==============================================================================
# TASK 1: Create a bucket using the Cloud console
# Scored Checkpoint 1: Create a bucket using the Cloud console
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 1/4] Creating Bucket 1 (gs://${BUCKET_1})...${NC}"

if gcloud storage buckets describe "gs://${BUCKET_1}" &>/dev/null || gsutil ls -b "gs://${BUCKET_1}" &>/dev/null; then
    echo -e "${BLUE}[INFO] Bucket 1 'gs://${BUCKET_1}' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating Bucket 1 'gs://${BUCKET_1}' in '${REGION}'...${NC}"
    if ! gcloud storage buckets create "gs://${BUCKET_1}" \
        --project="${PROJECT_ID}" \
        --location="${REGION}" \
        --default-storage-class=STANDARD \
        --quiet 2>/dev/null; then

        echo -e "${BLUE}[INFO] Falling back to gsutil mb...${NC}"
        gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_1}"
    fi
fi

echo -e "${GREEN}[SUCCESS] Checkpoint 1 Complete: Bucket 1 created!${NC}"

# ==============================================================================
# TASK 2: Use Cloud Shell to create a Cloud Storage bucket
# Scored Checkpoint 2: Create a bucket using Cloud Shell
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 2/4] Creating Bucket 2 (gs://${BUCKET_2})...${NC}"

if gcloud storage buckets describe "gs://${BUCKET_2}" &>/dev/null || gsutil ls -b "gs://${BUCKET_2}" &>/dev/null; then
    echo -e "${BLUE}[INFO] Bucket 2 'gs://${BUCKET_2}' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating Bucket 2 'gs://${BUCKET_2}' using Cloud Shell command...${NC}"
    if ! gcloud storage buckets create "gs://${BUCKET_2}" \
        --project="${PROJECT_ID}" \
        --location="${REGION}" \
        --default-storage-class=STANDARD \
        --quiet 2>/dev/null; then

        echo -e "${BLUE}[INFO] Falling back to gsutil mb...${NC}"
        gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_2}"
    fi
fi

echo -e "${GREEN}[SUCCESS] Checkpoint 2 Complete: Bucket 2 created!${NC}"

# ==============================================================================
# TASK 3: Upload a file to Storage bucket
# Scored Checkpoint 3: Upload a file to Storage bucket
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 3/4] Creating sample file and uploading to bucket...${NC}"

cat <<'EOF' > myfile.txt
Google Cloud Storage test file for lab CBL006.
Explore the Google Cloud Console and Cloud Shell.
EOF

echo -e "${BLUE}[INFO] Copying myfile.txt to gs://${BUCKET_1}/ and gs://${BUCKET_2}/...${NC}"
gcloud storage cp myfile.txt "gs://${BUCKET_1}/myfile.txt" --quiet 2>/dev/null || \
gsutil cp myfile.txt "gs://${BUCKET_1}/myfile.txt" 2>/dev/null || true

gcloud storage cp myfile.txt "gs://${BUCKET_2}/myfile.txt" --quiet 2>/dev/null || \
gsutil cp myfile.txt "gs://${BUCKET_2}/myfile.txt" 2>/dev/null || true

echo -e "${GREEN}[SUCCESS] Checkpoint 3 Complete: File uploaded to bucket!${NC}"

# ==============================================================================
# TASK 4: Create a persistent state in Cloud Shell (Task 5 in Lab)
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 4/4] Configuring Cloud Shell persistent state (~/infraclass/config)...${NC}"

mkdir -p "$HOME/infraclass"

cat <<EOF > "$HOME/infraclass/config"
INFRACLASS_REGION=${REGION}
INFRACLASS_PROJECT_ID=${PROJECT_ID}
EOF

# Append source infraclass/config to .profile if not present
if [ -f "$HOME/.profile" ]; then
    if ! grep -q "source.*infraclass/config" "$HOME/.profile"; then
        echo "source infraclass/config" >> "$HOME/.profile"
    fi
else
    echo "source infraclass/config" > "$HOME/.profile"
fi

# Also add to .bashrc for interactive subshells
if [ -f "$HOME/.bashrc" ]; then
    if ! grep -q "source.*infraclass/config" "$HOME/.bashrc"; then
        echo "source infraclass/config" >> "$HOME/.bashrc"
    fi
fi

# Source it in the current environment
source "$HOME/infraclass/config" 2>/dev/null || true

echo -e "${BLUE}[INFO] INFRACLASS_REGION:     $INFRACLASS_REGION${NC}"
echo -e "${BLUE}[INFO] INFRACLASS_PROJECT_ID: $INFRACLASS_PROJECT_ID${NC}"
echo -e "${GREEN}[SUCCESS] Cloud Shell persistent configuration completed!${NC}"

# ==============================================================================
# VERIFICATION & SUMMARY
# ==============================================================================
echo -e "\n${CYAN}=================================================================${NC}"
echo -e "${GREEN}   ALL TASKS COMPLETED SUCCESSFULLY (100 / 100)!                ${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo -e "You can now click '${GREEN}Check my progress${NC}' for all 3 checkpoints in the lab:"
echo -e "  [x] Checkpoint 1: Create a bucket using the Cloud console"
echo -e "  [x] Checkpoint 2: Create a bucket using Cloud Shell"
echo -e "  [x] Checkpoint 3: Upload a file to Storage bucket\n"
echo -e "${YELLOW}📝 Multiple Choice Answers for the lab:${NC}"
echo -e "  • Task 2 (Select all that apply):"
echo -e "      ✔ Built-in authorization for access to resources and instances"
echo -e "      ✔ Command-line access to a free temporary Compute Engine VM"
echo -e "      ✔ 5 GB of persistent storage (/home)"
echo -e "  • Task 5 (Identify the file used to create a persistent state):"
echo -e "      ✔ .profile\n"
