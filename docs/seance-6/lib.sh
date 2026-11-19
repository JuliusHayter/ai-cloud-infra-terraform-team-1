# Fonctions communes des scripts de la séance 6. À charger avec : . "$(dirname "$0")/lib.sh"
export LC_ALL=C
PROJECT=${PROJECT:-advanced-cloud-ai}
REGION=${REGION:-europe-west1}
BUCKET=${BUCKET:-advanced-cloud-ai-models}

dry() {
  [ "${DRY_RUN:-0}" = 1 ]
}

die() {
  echo "$*" >&2
  exit 1
}

run() {
  if dry; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

check_team() {
  case "${1:-}" in
    [a-z]*) ;;
    *) die "identifiant d'équipe attendu (exemple : team1), reçu : '${1:-}'" ;;
  esac
  case "$1" in
    *[!a-z0-9-]*) die "identifiant d'équipe invalide : '$1'" ;;
  esac
}

dry_notice() {
  if dry; then
    echo "# DRY_RUN : les lectures sont remplacées par des valeurs factices, aucune écriture" >&2
  fi
}

model_id() {
  if dry; then
    echo "0000000000"
    return 0
  fi
  local name
  name=$(gcloud ai models list --region "$REGION" --project "$PROJECT" \
    --filter="displayName=fraud-scorer-${1}" --format='value(name)')
  [ -n "$name" ] || die "fraud-scorer-${1} est absent du registre"
  echo "${name##*/}"
}

model_info() {
  local team=$1 ref=$2 info id
  if dry; then
    if [ "$ref" = champion ]; then
      printf '1\tgs://%s/models\n' "$BUCKET"
    else
      printf '2\tgs://%s/runs/%s/models/20261119-0000\n' "$BUCKET" "$team"
    fi
    return 0
  fi
  id=$(model_id "$team") || exit 1
  info=$(gcloud ai models describe "${id}@${ref}" --region "$REGION" --project "$PROJECT" \
    --format='value(versionId,artifactUri)')
  [ -n "$info" ] || die "fraud-scorer-${team}@${ref} : version introuvable"
  echo "$info"
}

uri_to_mount() {
  local uri=${1%/} prefix=${2:-${MOUNT:-/mnt/models}}
  case "$uri" in
    "gs://${BUCKET}/"*) echo "${prefix}/${uri#"gs://${BUCKET}/"}" ;;
    *) die "artefact hors du bucket gs://${BUCKET} : $uri" ;;
  esac
}

artifact_dir() {
  local info
  info=$(model_info "$1" "$2") || exit 1
  uri_to_mount "${info#*$'\t'}" "${3:-}"
}

base_revision() {
  local team=$1 prefer=${2:-} table line="" rev tag pct
  if dry; then
    if [ -n "${DRY_CANDIDATE:-}" ] && [ -n "$prefer" ]; then
      echo "${team}-scorer-candidate-fake ${prefer} 0"
    else
      echo "${team}-scorer-00001-fake champion 100"
    fi
    return 0
  fi
  table=$(gcloud run services describe "${team}-scorer" --region "$REGION" --project "$PROJECT" \
    --flatten='status.traffic[]' \
    --format='csv[no-heading](status.traffic.revisionName,status.traffic.tag,status.traffic.percent)')
  if [ -n "$prefer" ]; then
    line=$(printf '%s\n' "$table" | awk -F, -v t="$prefer" '$2==t{print;exit}')
  fi
  if [ -z "$line" ]; then
    line=$(printf '%s\n' "$table" | sort -t, -k3,3nr | sed -n 1p)
  fi
  IFS=, read -r rev tag pct <<EOF_LINE
$line
EOF_LINE
  if [ -z "$rev" ]; then
    rev=$(gcloud run services describe "${team}-scorer" --region "$REGION" --project "$PROJECT" \
      --format='value(status.latestReadyRevisionName)')
  fi
  [ -n "$rev" ] || die "${team}-scorer : aucune révision en service"
  echo "${rev} ${tag:--} ${pct:-0}"
}

revision_env() {
  if dry; then
    printf '%s\n' FEATURE_SOURCE=bigquery FEATURE_READER=snapshot BQ_DATASET=scoring \
      MODELS_DIR=/mnt/models/models MODEL_VERSION=1 GOOGLE_CLOUD_PROJECT=advanced-cloud-ai \
      WEB_CONCURRENCY=1 XGB_NTHREAD=1 DATA_DIR=/mnt/models/data
    return 0
  fi
  gcloud run revisions describe "$1" --region "$REGION" --project "$PROJECT" \
    --flatten='spec.containers[].env[]' --format='value(spec.containers.env.name,spec.containers.env.value)' |
    while IFS=$'\t' read -r name value; do
      if [ -n "$name" ]; then
        printf '%s=%s\n' "$name" "$value"
      fi
    done
}

revision_image() {
  if dry; then
    echo "europe-west1-docker.pkg.dev/advanced-cloud-ai/cloud-ai/ref-fraud-api:td6"
    return 0
  fi
  gcloud run revisions describe "$1" --region "$REGION" --project "$PROJECT" \
    --format='value(spec.containers[0].image)'
}

service_url() {
  if dry; then
    echo "https://${1}-scorer-fake-ew.a.run.app"
    return 0
  fi
  gcloud run services describe "${1}-scorer" --region "$REGION" --project "$PROJECT" --format='value(status.url)'
}

tag_info() {
  if dry; then
    printf '%s-scorer-%s-fake\thttps://%s---%s-scorer-fake-ew.a.run.app\n' "$1" "$2" "$2" "$1"
    return 0
  fi
  gcloud run services describe "${1}-scorer" --region "$REGION" --project "$PROJECT" \
    --flatten='status.traffic[]' \
    --format='value(status.traffic.tag,status.traffic.revisionName,status.traffic.url)' |
    awk -F'\t' -v t="$2" '$1==t{print $2 "\t" $3; exit}'
}

env_set() {
  local out="" line
  while IFS= read -r line; do
    case "$line" in
      "") ;;
      "$2="*) ;;
      *) out="${out}${line}"$'\n' ;;
    esac
  done <<EOF_ENV
$1
EOF_ENV
  printf '%s%s=%s\n' "$out" "$2" "$3"
}

env_flag() {
  printf '^;^%s' "$(printf '%s' "$1" | grep -v '^$' | tr '\n' ';' | sed 's/;$//')"
}

identity_token() {
  if dry; then
    echo "FAKE_TOKEN"
    return 0
  fi
  gcloud auth print-identity-token
}
