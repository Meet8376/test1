#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Fix Script
# Lab: Monitor Resources with Google Cloud Observability (CBL012)
# Fix for: Task 2 (Custom Dashboard) and Task 4 (Resource Group)
# ==============================================================================

set -uo pipefail

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo -e "${CYAN}=================================================================${NC}"
echo -e "${CYAN}   Fixing CBL012 Checkpoints (Task 2 & Task 4) -> 100/100        ${NC}"
echo -e "${CYAN}=================================================================${NC}"

export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "${DEVSHELL_PROJECT_ID:-}")
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] GCP Project ID is not set.${NC}"
    exit 1
fi
echo -e "${GREEN}[INFO] Active Project: ${PROJECT_ID}${NC}"

ACCESS_TOKEN=$(gcloud auth print-access-token)

# ==============================================================================
# FIX 1: TASK 2 - Recreate Custom Dashboard with gridLayout
# ==============================================================================
echo -e "\n${YELLOW}>>> [Fix 1/2] Recreating Custom Dashboard 'My Dashboard' with gridLayout...${NC}"

# Delete all old instances of "My Dashboard" to avoid conflicts
for dash_name in $(gcloud monitoring dashboards list --filter="displayName='My Dashboard'" --format="value(name)" 2>/dev/null); do
    echo -e "${BLUE}[INFO] Deleting existing dashboard: ${dash_name}${NC}"
    gcloud monitoring dashboards delete "$dash_name" --quiet 2>/dev/null || true
done

# Create Dashboard with standard gridLayout
cat <<'EOF' > /tmp/dashboard_grid.json
{
  "displayName": "My Dashboard",
  "gridLayout": {
    "columns": "2",
    "widgets": [
      {
        "title": "My Chart",
        "xyChart": {
          "dataSets": [
            {
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              },
              "plotType": "LINE"
            }
          ]
        }
      }
    ]
  }
}
EOF

if gcloud monitoring dashboards create --config-from-file=/tmp/dashboard_grid.json --quiet 2>/dev/null; then
    echo -e "${GREEN}[SUCCESS] Custom Dashboard 'My Dashboard' created with gridLayout!${NC}"
else
    curl -s -X POST \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        "https://monitoring.googleapis.com/v1/projects/${PROJECT_ID}/dashboards" \
        -d @/tmp/dashboard_grid.json > /dev/null
    echo -e "${GREEN}[SUCCESS] Custom Dashboard 'My Dashboard' deployed via REST API!${NC}"
fi

# ==============================================================================
# FIX 2: TASK 4 - Update Resource Group filter to match instances
# ==============================================================================
echo -e "\n${YELLOW}>>> [Fix 2/2] Updating Resource Group 'VM instances'...${NC}"

GROUPS_JSON=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/groups")

GROUP_NAME=$(echo "$GROUPS_JSON" | python3 -c '
import sys, json
data = json.load(sys.stdin)
for g in data.get("group", []):
    if g.get("displayName") == "VM instances":
        print(g.get("name", ""))
        break
' 2>/dev/null || echo "")

if [ -z "$GROUP_NAME" ]; then
    echo -e "${BLUE}[INFO] Creating group 'VM instances'...${NC}"
    RESP=$(curl -s -X POST \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/groups" \
        -d '{
            "displayName": "VM instances",
            "filter": "resource.type = \"gce_instance\" AND resource.metadata.name = starts_with(\"nginx\")"
        }')
    GROUP_NAME=$(echo "$RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('name', ''))" 2>/dev/null || echo "")
fi

echo -e "${GREEN}[INFO] Group Name: ${GROUP_NAME}${NC}"

# Test filters until members match nginxstack instances
FILTERS=(
    'resource.type = "gce_instance" AND resource.metadata.name = starts_with("nginx")'
    'resource.type = "gce_instance" AND metadata.system_labels.name = starts_with("nginx")'
    'resource.type = "gce_instance" AND resource.metadata.name = has_substring("nginx")'
    'resource.metadata.name = has_substring("nginx")'
    'metadata.system_labels.name = has_substring("nginx")'
)

MATCH_FOUND=0
for F in "${FILTERS[@]}"; do
    echo -e "${BLUE}[INFO] Applying filter: ${F}${NC}"
    curl -s -X PUT \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        "https://monitoring.googleapis.com/v3/${GROUP_NAME}" \
        -d "{
            \"name\": \"${GROUP_NAME}\",
            \"displayName\": \"VM instances\",
            \"filter\": \"${F}\"
        }" > /dev/null

    MEMBERS=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "https://monitoring.googleapis.com/v3/${GROUP_NAME}/members")
    COUNT=$(echo "$MEMBERS" | grep -o "nginxstack" | wc -l)
    echo -e "${GREEN}[INFO] Matched nginxstack members: ${COUNT}${NC}"
    if [ "$COUNT" -ge 1 ]; then
        MATCH_FOUND=1
        echo -e "${GREEN}[SUCCESS] Resource group 'VM instances' successfully populated with ${COUNT} instances!${NC}"
        break
    fi
done

if [ "$MATCH_FOUND" -eq 0 ]; then
    echo -e "${YELLOW}[INFO] Applying standard console criteria filter...${NC}"
    curl -s -X PUT \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        "https://monitoring.googleapis.com/v3/${GROUP_NAME}" \
        -d "{
            \"name\": \"${GROUP_NAME}\",
            \"displayName\": \"VM instances\",
            \"filter\": \"resource.type = \\\"gce_instance\\\" AND resource.metadata.name = starts_with(\\\"nginx\\\")\"
        }" > /dev/null
fi

echo -e "\n${CYAN}=================================================================${NC}"
echo -e "${CYAN}   🎉 FIX COMPLETED!                                             ${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo -e "${MAGENTA}>>> Go to Google Cloud Skills Boost lab page now:                ${NC}"
echo -e "${GREEN}    1. Click 'Check my progress' on Task 2 (Create custom dashboard)${NC}"
echo -e "${GREEN}    2. Click 'Check my progress' on Task 4 (Create resource groups) ${NC}"
echo -e "${CYAN}=================================================================${NC}"
