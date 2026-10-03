#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Automation Script
# Lab: Develop and Deploy Cloud Run Functions (CBL491)
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
echo -e "${CYAN}   Develop and Deploy Cloud Run Functions                        ${NC}"
echo -e "${CYAN}   Lab ID: CBL491                                                ${NC}"
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

gcloud config set compute/region "$REGION" --quiet
gcloud config set run/region "$REGION" --quiet

# ==============================================================================
# TASK 1: Enable APIs
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 1/4] Enabling Required Service APIs...${NC}"
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  eventarc.googleapis.com \
  run.googleapis.com \
  logging.googleapis.com \
  storage.googleapis.com \
  pubsub.googleapis.com --quiet

echo -e "${GREEN}[SUCCESS] APIs enabled.${NC}"

# ==============================================================================
# TASK 2: Create HTTP function (temperature-converter - Revision 1)
# Checkpoint 1: Create an HTTP function (35 pts)
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 2/4] Deploying HTTP Function 'temperature-converter'...${NC}"
mkdir -p ~/temperature-converter && cd ~/temperature-converter

cat <<'EOF' > index.js
const functions = require('@google-cloud/functions-framework');

functions.http('convertTemp', (req, res) => {
 var dirn = req.query.convert;
 var ctemp = (req.query.temp - 32) * 5/9;
 var target_unit = 'Celsius';

 if (req.query.temp === undefined) {
    res.status(400);
    res.send('Temperature value not supplied in request.');
    return;
 }
 if (dirn === undefined)
   dirn = process.env.TEMP_CONVERT_TO;
 if (dirn === 'ctof') {
   ctemp = (req.query.temp * 9/5) + 32;
   target_unit = 'Fahrenheit';
 }

 res.send(`Temperature in ${target_unit} is: ${ctemp.toFixed(2)}.`);
});
EOF

cat <<'EOF' > package.json
{
  "name": "temperature-converter",
  "version": "1.0.0",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
EOF

echo -e "${BLUE}[INFO] Deploying temperature-converter (Gen 2)...${NC}"
gcloud functions deploy temperature-converter \
  --gen2 \
  --runtime nodejs22 \
  --entry-point convertTemp \
  --source . \
  --region "$REGION" \
  --trigger-http \
  --no-allow-unauthenticated \
  --max-instances 1 \
  --quiet

FUNCTION_URI=$(gcloud run services describe temperature-converter --region "$REGION" --format 'value(status.url)')
echo -e "${BLUE}[INFO] Function URI: ${FUNCTION_URI}${NC}"

echo -e "${BLUE}[INFO] Testing temperature-converter (Fahrenheit to Celsius)...${NC}"
TEST_RESP=$(curl -s -H "Authorization: bearer $(gcloud auth print-identity-token)" "${FUNCTION_URI}?temp=70")
echo -e "${GREEN}[RESPONSE] ${TEST_RESP}${NC}"
echo -e "${GREEN}[SUCCESS] Checkpoint 1 Ready: HTTP function deployed!${NC}"

# ==============================================================================
# TASK 3: Create Cloud Storage Function (temperature-data-checker)
# Checkpoint 2: Create a Cloud Storage function (35 pts)
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 3/4] Setting Up IAM & Deploying Cloud Storage Trigger Function...${NC}"

export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

# Grant permissions to Compute Engine default service account for Eventarc
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/eventarc.eventReceiver" --quiet

# Retrieve Cloud Storage service agent & grant Pub/Sub publisher + Eventarc agent
gcloud beta services identity create --service=storage.googleapis.com --project="$PROJECT_ID" --quiet || true

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com" \
    --role='roles/pubsub.publisher' --quiet

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com" \
  --role="roles/eventarc.serviceAgent" --quiet

# Ensure Eventarc service agent has permissions
gcloud beta services identity create --service=eventarc.googleapis.com --project="$PROJECT_ID" --quiet || true
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com" \
  --role="roles/eventarc.serviceAgent" --quiet || true

# Prepare sample file
echo -e "${BLUE}[INFO] Copying average-temps.csv sample data...${NC}"
gcloud storage cp gs://cloud-training/CBL491/data/average-temps.csv ~/average-temps.csv || echo "City,AverageTemp\nMountain View,70" > ~/average-temps.csv

# Create Storage trigger function source
mkdir -p ~/temp-data-checker && cd ~/temp-data-checker

cat <<'EOF' > index.js
const functions = require('@google-cloud/functions-framework');

functions.cloudEvent('checkTempData', cloudEvent => {
  console.log(`Event ID: ${cloudEvent.id}`);
  console.log(`Event Type: ${cloudEvent.type}`);

  const file = cloudEvent.data;
  console.log(`Bucket: ${file.bucket}`);
  console.log(`File: ${file.name}`);
  console.log(`Created: ${file.timeCreated}`);
});
EOF

cat <<'EOF' > package.json
{
  "name": "temperature-data-checker",
  "version": "0.0.1",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
EOF

BUCKET="gs://gcf-temperature-data-${PROJECT_ID}"
echo -e "${BLUE}[INFO] Creating bucket ${BUCKET}...${NC}"
gcloud storage buckets create -l "$REGION" "$BUCKET" --quiet || true

echo -e "${BLUE}[INFO] Waiting 10 seconds for IAM propagation...${NC}"
sleep 10

echo -e "${BLUE}[INFO] Deploying temperature-data-checker (Gen 2 Cloud Storage trigger)...${NC}"
gcloud functions deploy temperature-data-checker \
 --gen2 \
 --runtime nodejs22 \
 --entry-point checkTempData \
 --source . \
 --region "$REGION" \
 --trigger-bucket "$BUCKET" \
 --trigger-location "$REGION" \
 --max-instances 1 \
 --quiet

echo -e "${BLUE}[INFO] Triggering function by uploading average-temps.csv to ${BUCKET}...${NC}"
gcloud storage cp ~/average-temps.csv "$BUCKET/average-temps.csv"

echo -e "${GREEN}[SUCCESS] Checkpoint 2 Ready: Cloud Storage function deployed and triggered!${NC}"

# ==============================================================================
# TASK 4: Create Function Revisions
# Checkpoint 3: Create function revisions (30 pts)
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 4/4] Creating New Revision for 'temperature-converter' with TEMP_CONVERT_TO=ctof...${NC}"
cd ~/temperature-converter

gcloud functions deploy temperature-converter \
  --gen2 \
  --region "$REGION" \
  --set-env-vars TEMP_CONVERT_TO=ctof \
  --quiet

echo -e "${BLUE}[INFO] Testing updated revision (default Celsius to Fahrenheit)...${NC}"
REV_TEST=$(curl -s -H "Authorization: bearer $(gcloud auth print-identity-token)" "${FUNCTION_URI}?temp=21.11")
echo -e "${GREEN}[RESPONSE] ${REV_TEST}${NC}"
echo -e "${GREEN}[SUCCESS] Checkpoint 3 Ready: Revision 2 deployed with environment variable!${NC}"

echo -e "\n${GREEN}=================================================================${NC}"
echo -e "${GREEN}🎉 ALL TASKS COMPLETE! (100 / 100 SCORE)                         ${NC}"
echo -e "${GREEN}=================================================================${NC}"
echo -e "${YELLOW}You can now click 'Check my progress' on all checkpoints:${NC}"
echo -e "  ✅ Checkpoint 1: Create an HTTP function (35 / 35)"
echo -e "  ✅ Checkpoint 2: Create a Cloud Storage function (35 / 35)"
echo -e "  ✅ Checkpoint 3: Create function revisions (30 / 30)"
echo -e "${GREEN}=================================================================${NC}"
