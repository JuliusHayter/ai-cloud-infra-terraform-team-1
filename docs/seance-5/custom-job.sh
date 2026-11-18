#!/usr/bin/env bash
# Entraînement final en custom job Vertex AI (séance 5, étape 3).
#
# usage : ./custom-job.sh <équipe> <type de machine> <threads> <premier mois AAAA-MM> <best.json>
#   ./custom-job.sh team1 n2-standard-8 8 2025-08 /gcs/advanced-cloud-ai-models/runs/team1/search/w8-t1/best.json
#
# Le dernier mois est toujours 2026-07 (la validation commence en août). Le modèle est écrit dans
# runs/<équipe>/models/<run_id>/ ; suivre le job :
#   gcloud ai custom-jobs describe <id> --region europe-west1
#   gcloud ai custom-jobs stream-logs <id> --region europe-west1
set -euo pipefail

if [ $# -lt 5 ]; then
  sed -n '4,5p' "$0"
  exit 1
fi

TEAM=$1
MACHINE=$2
THREADS=$3
SINCE=$4
PROJECT=advanced-cloud-ai
REGION=europe-west1
BUCKET=/gcs/advanced-cloud-ai-models
IMAGE=europe-west1-docker.pkg.dev/$PROJECT/cloud-ai/fraud-train:td5
PARAMS=$5
TIMEOUT=${TIMEOUT:-2700s}

CONFIG=$(mktemp -t custom-job.XXXXXX)
trap 'rm -f "$CONFIG"' EXIT
cat > "$CONFIG" <<EOF
workerPoolSpecs:
  - machineSpec:
      machineType: $MACHINE
    replicaCount: 1
    containerSpec:
      imageUri: $IMAGE
      args: [train.job, --train, large, --since, "$SINCE", --params, "$PARAMS",
             --threads, "$THREADS", --out, "$BUCKET/runs/$TEAM/models"]
      env:
        - {name: IMAGE, value: "$IMAGE"}
scheduling:
  timeout: $TIMEOUT
EOF

gcloud ai custom-jobs create \
  --region="$REGION" \
  --display-name="$TEAM-train-large-$SINCE-$MACHINE-t$THREADS" \
  --service-account="$TEAM-train@$PROJECT.iam.gserviceaccount.com" \
  --labels="team=$TEAM" \
  --config="$CONFIG"
