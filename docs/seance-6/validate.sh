#!/usr/bin/env bash
# Lance le job de validation du challenger contre le champion et affiche sa ligne de résultat.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage : ./validate.sh <équipe>

  ./validate.sh team1

Exécute le job <équipe>-validate sur les données de validation avec le modèle d'alias `champion` et celui d'alias
`challenger`, attend la fin de cette exécution, puis affiche sa ligne de log qui commence par `VALIDATION `.

variables facultatives :
  CHAMPION_REF=champion    CANDIDATE_REF=challenger    alias ou numéro de version
  THRESHOLD                seuil d'alerte (défaut : celui que le service en production annonce sur /health)
  DRY_RUN=1                imprime les commandes qui écrivent au lieu de les exécuter
USAGE
}

case "${1:-}" in
  -h | --help) usage; exit 0 ;;
esac
[ $# -eq 1 ] || { usage >&2; exit 1; }

. "$(dirname "$0")/lib.sh"

TEAM=$1
check_team "$TEAM"
JOB="${TEAM}-validate"
MOUNT_JOB=/gcs/${BUCKET}

dry_notice
CHAMPION=$(artifact_dir "$TEAM" "${CHAMPION_REF:-champion}" "$MOUNT_JOB")
CANDIDATE=$(artifact_dir "$TEAM" "${CANDIDATE_REF:-challenger}" "$MOUNT_JOB")

if [ -z "${THRESHOLD:-}" ]; then
  if dry; then
    THRESHOLD=0.5
  else
    HEALTH=$(curl -sS --max-time 30 -H "Authorization: Bearer $(identity_token)" "$(service_url "$TEAM")/health")
    THRESHOLD=$(printf '%s' "$HEALTH" | sed -n 's/.*"threshold": *\([0-9.eE+-]*\).*/\1/p')
    [ -n "$THRESHOLD" ] || die "seuil introuvable dans /health : ${HEALTH} ; renseigner THRESHOLD"
  fi
fi

echo "champion : ${CHAMPION}"
echo "candidat : ${CANDIDATE}"
echo "seuil    : ${THRESHOLD}"

EXECUTION=$(run gcloud run jobs execute "$JOB" --region "$REGION" --project "$PROJECT" --async \
  --update-env-vars "CHAMPION=${CHAMPION},CANDIDATE=${CANDIDATE},THRESHOLD=${THRESHOLD}" \
  --format='value(metadata.name)')
if dry; then
  echo "$EXECUTION"
  EXECUTION="${JOB}-fake1"
fi
[ -n "$EXECUTION" ] || die "le lancement de ${JOB} n'a renvoyé aucune exécution"
echo "exécution : ${EXECUTION}"

STATUS=0
if dry; then
  echo "+ gcloud run jobs executions describe ${EXECUTION} (attente de la fin)"
else
  DESCRIBE="gcloud run jobs executions describe ${EXECUTION} --region ${REGION} --project ${PROJECT}"
  DONE=""
  for i in $(seq 1 90); do
    DONE=$(gcloud run jobs executions describe "$EXECUTION" --region "$REGION" --project "$PROJECT" \
      --format='value(status.completionTime)' 2>/dev/null) || DONE=""
    [ -n "$DONE" ] && break
    if [ $((i % 3)) -eq 0 ]; then
      echo "attente de la fin du job : $((i * 10)) s" >&2
    fi
    sleep 10
  done
  [ -n "$DONE" ] || die "Le job n'est pas terminé après 15 minutes. Suivre l'exécution : ${DESCRIBE}"
  OK=$(gcloud run jobs executions describe "$EXECUTION" --region "$REGION" --project "$PROJECT" \
    --format='value(status.succeededCount)')
  [ "${OK:-0}" -ge 1 ] || STATUS=1
fi

FILTER="resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${JOB}\" AND labels.\"run.googleapis.com/execution_name\"=\"${EXECUTION}\" AND (textPayload=~\"^VALIDATION \" OR jsonPayload.message=~\"^VALIDATION \")"
if dry; then
  echo "+ gcloud logging read '${FILTER}' --project ${PROJECT} --freshness=1d --limit=1"
  exit 0
fi

LINE=""
for _ in 1 2 3 4 5 6; do
  LINE=$(gcloud logging read "$FILTER" --project "$PROJECT" --freshness=1d --limit=1 --order=desc \
    --format='value(textPayload,jsonPayload.message)' | tr -d '\t')
  [ -n "$LINE" ] && break
  sleep 5
done
if [ -n "$LINE" ]; then
  echo "$LINE"
else
  echo "Aucune ligne VALIDATION pour l'exécution ${EXECUTION}. Lire ses logs :" >&2
  echo "  gcloud logging read 'resource.type=\"cloud_run_job\" AND labels.\"run.googleapis.com/execution_name\"=\"${EXECUTION}\"' --project ${PROJECT} --freshness=1d --format='value(textPayload)'" >&2
  STATUS=1
fi
exit "$STATUS"
