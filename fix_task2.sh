#!/bin/bash
set -uo pipefail

export REGION="us-central1"

echo "=== Fixing Checkpoint 1 (Create an HTTP function) ==="

# 1. Ensure max-instances is 1 on Cloud Run service
gcloud run services update temperature-converter \
  --region "$REGION" \
  --max-instances 1 \
  --quiet

# 2. Find Revision 1 (the original Task 2 revision without TEMP_CONVERT_TO)
REV1=$(gcloud run revisions list --service temperature-converter --region "$REGION" --format="value(name)" --sort-by=creationTimestamp | head -n 1)
echo "Routing 100% traffic to Revision 1: $REV1"

gcloud run services update-traffic temperature-converter \
  --region "$REGION" \
  --to-revisions "${REV1}=100" \
  --quiet

# 3. Test invocation with temp=70 (Must return 21.11 Celsius for Task 2 test)
FUNCTION_URI=$(gcloud run services describe temperature-converter --region "$REGION" --format 'value(status.url)')
echo "Testing: ${FUNCTION_URI}?temp=70"
curl -s -H "Authorization: bearer $(gcloud auth print-identity-token)" "${FUNCTION_URI}?temp=70"
echo ""

echo "=== Done! Now click 'Check my progress' on Checkpoint 1 ==="
