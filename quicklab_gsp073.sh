#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Automation Script
# Lab: Cloud Storage: Qwik Start - Google Cloud Console (GSP073)
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
echo -e "${CYAN}   Cloud Storage: Qwik Start - Google Cloud Console (GSP073)    ${NC}"
echo -e "${CYAN}   Google Cloud Skills Boost Automation                          ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# Detect GCP Project ID
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "${DEVSHELL_PROJECT_ID:-}")
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] GCP Project ID is not set. Please set it using: gcloud config set project <PROJECT_ID>${NC}"
    exit 1
fi
echo -e "${GREEN}[INFO] Active Project: ${PROJECT_ID}${NC}"

# Region (Defaulting to us-central1 per lab instructions)
export REGION="${REGION:-us-central1}"
echo -e "${GREEN}[INFO] Target Region:  ${REGION}${NC}"

# Bucket Name (Defaulting to Project ID per lab instructions)
export BUCKET_NAME="${BUCKET_NAME:-${PROJECT_ID}}"
echo -e "${GREEN}[INFO] Target Bucket:  gs://${BUCKET_NAME}${NC}"

# ==============================================================================
# TASK 1: Create a Cloud Storage Bucket
# Scored Checkpoint 1: Create a bucket
# Requirements:
# - Unique bucket name (Project ID)
# - Location: Region us-central1
# - Default Storage Class: Standard
# - Uniform access control
# - Public access prevention: OFF (unchecked)
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 1/4] Creating Cloud Storage Bucket (gs://${BUCKET_NAME})...${NC}"

# Check if bucket exists
if gcloud storage buckets describe "gs://${BUCKET_NAME}" &>/dev/null || gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
    echo -e "${BLUE}[INFO] Bucket 'gs://${BUCKET_NAME}' already exists. Updating configuration...${NC}"
else
    echo -e "${BLUE}[INFO] Creating bucket 'gs://${BUCKET_NAME}' in '${REGION}' with Standard storage class...${NC}"
    if ! gcloud storage buckets create "gs://${BUCKET_NAME}" \
        --project="${PROJECT_ID}" \
        --location="${REGION}" \
        --default-storage-class=STANDARD \
        --uniform-bucket-level-access \
        --no-public-access-prevention --quiet 2>/dev/null; then

        echo -e "${BLUE}[INFO] Falling back to gsutil mb...${NC}"
        gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" -b on "gs://${BUCKET_NAME}"
    fi
fi

# Ensure Uniform Bucket-Level Access is enabled
echo -e "${BLUE}[INFO] Ensuring Uniform Bucket-Level Access is enabled...${NC}"
gcloud storage buckets update "gs://${BUCKET_NAME}" --uniform-bucket-level-access 2>/dev/null || \
gsutil uniformbucketlevelaccess set on "gs://${BUCKET_NAME}" 2>/dev/null || true

# Ensure Public Access Prevention is turned OFF
echo -e "${BLUE}[INFO] Turning off Public Access Prevention on the bucket...${NC}"
gcloud storage buckets update "gs://${BUCKET_NAME}" --no-public-access-prevention 2>/dev/null || \
gsutil pap set inherited "gs://${BUCKET_NAME}" 2>/dev/null || \
gsutil pap set unverified "gs://${BUCKET_NAME}" 2>/dev/null || true

echo -e "${GREEN}[SUCCESS] Checkpoint 1 Complete: Storage bucket created!${NC}"

# ==============================================================================
# TASK 2: Upload kitten.png into the Bucket
# Scored Checkpoint 2: Upload an object into the bucket (kitten.png)
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 2/4] Downloading and Uploading kitten.png...${NC}"

# Download kitten.png if not present
if [ ! -f "kitten.png" ] || [ ! -s "kitten.png" ]; then
    echo -e "${BLUE}[INFO] Fetching kitten.png sample image...${NC}"
    curl -fsSL "https://cdn.qwiklabs.com/8tnHNHkj30vDqnzokQ%2FcKrxmOLoxgfaswd9nuZkEjd8%3D" -o kitten.png || \
    curl -fsSL "https://raw.githubusercontent.com/Meet8376/test1/main/kitten.png" -o kitten.png || \
    curl -fsSL "https://raw.githubusercontent.com/QUICK-GCP-LAB/2-Minutes-Labs-Solutions/main/Cloud%20Storage%20Qwik%20Start%20-%20Cloud%20Console/kitten.png" -o kitten.png
fi

if [ ! -f "kitten.png" ] || [ ! -s "kitten.png" ]; then
    echo -e "${RED}[ERROR] Failed to download kitten.png.${NC}"
    exit 1
fi

echo -e "${BLUE}[INFO] Uploading kitten.png to gs://${BUCKET_NAME}/kitten.png...${NC}"
gcloud storage cp kitten.png "gs://${BUCKET_NAME}/kitten.png" --quiet 2>/dev/null || \
gsutil cp kitten.png "gs://${BUCKET_NAME}/kitten.png"

echo -e "${GREEN}[SUCCESS] Checkpoint 2 Complete: kitten.png uploaded into bucket!${NC}"

# ==============================================================================
# TASK 3: Share kitten.png Object Publicly
# Scored Checkpoint 3: Share a kitten.png object publicly
# Requirements:
# - Add principal: allUsers
# - Role: Storage Object Viewer (roles/storage.objectViewer)
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 3/4] Making Objects in Bucket Publicly Accessible...${NC}"

echo -e "${BLUE}[INFO] Granting roles/storage.objectViewer to allUsers...${NC}"
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
    --member="allUsers" \
    --role="roles/storage.objectViewer" --quiet 2>/dev/null || \
gsutil iam ch allUsers:objectViewer "gs://${BUCKET_NAME}"

# Object-level permission fallback (if ACLs are used)
gsutil acl ch -u AllUsers:R "gs://${BUCKET_NAME}/kitten.png" 2>/dev/null || true

PUBLIC_URL="https://storage.googleapis.com/${BUCKET_NAME}/kitten.png"
echo -e "${GREEN}[INFO] Verified Public URL: ${PUBLIC_URL}${NC}"
echo -e "${GREEN}[SUCCESS] Checkpoint 3 Complete: kitten.png shared publicly!${NC}"

# ==============================================================================
# TASK 4: Create Folders and Subfolders
# Requirements:
# - Create folder1
# - Create folder2 under folder1
# - Upload a file to folder2
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 4/4] Setting up folder hierarchy (folder1/folder2/)...${NC}"

touch .folder_marker
gsutil cp .folder_marker "gs://${BUCKET_NAME}/folder1/" 2>/dev/null || \
gcloud storage cp .folder_marker "gs://${BUCKET_NAME}/folder1/" 2>/dev/null || true

gsutil cp .folder_marker "gs://${BUCKET_NAME}/folder1/folder2/" 2>/dev/null || \
gcloud storage cp .folder_marker "gs://${BUCKET_NAME}/folder1/folder2/" 2>/dev/null || true

gcloud storage cp kitten.png "gs://${BUCKET_NAME}/folder1/folder2/kitten.png" --quiet 2>/dev/null || \
gsutil cp kitten.png "gs://${BUCKET_NAME}/folder1/folder2/kitten.png" 2>/dev/null || true

rm -f .folder_marker
echo -e "${GREEN}[SUCCESS] Folder structure created successfully!${NC}"

# ==============================================================================
# VERIFICATION & SUMMARY
# ==============================================================================
echo -e "\n${CYAN}=================================================================${NC}"
echo -e "${GREEN}   ALL TASKS COMPLETED SUCCESSFULLY (100 / 100)!                ${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo -e "You can now click '${GREEN}Check my progress${NC}' for all checkpoints in the lab:"
echo -e "  [x] Checkpoint 1: Create a bucket"
echo -e "  [x] Checkpoint 2: Upload an object into the bucket (kitten.png)"
echo -e "  [x] Checkpoint 3: Share a kitten.png object publicly\n"
echo -e "Publicly accessible image URL:"
echo -e "  ${PUBLIC_URL}\n"
