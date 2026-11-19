#!/usr/bin/env bash
# Crée, déplace ou supprime l'abonnement d'ombre <équipe>-shadow du topic ff-td6.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage : ./shadow.sh <équipe> <tag>
        ./shadow.sh <équipe> --off

  ./shadow.sh team1 candidate
  ./shadow.sh team1 --off

L'abonnement <équipe>-shadow envoie une copie du flux ff-td6 à <adresse du tag>/pubsub/shadow : la révision du
tag calcule les scores, journalise `shadow` vrai et répond toujours 204. Le trafic des utilisateurs n'est pas touché.
Le jeton OIDC est signé par <équipe>-scorer-push avec l'audience de l'abonnement
<équipe>-live-push (l'adresse du service) ; l'adresse du tag, elle, est différente de celle du service.
`--off` supprime l'abonnement.

DRY_RUN=1 imprime les commandes qui écrivent au lieu de les exécuter.
USAGE
}

case "${1:-}" in
  -h | --help) usage; exit 0 ;;
esac
[ $# -eq 2 ] || { usage >&2; exit 1; }

. "$(dirname "$0")/lib.sh"

TEAM=$1
TAG=$2
check_team "$TEAM"
SUB="${TEAM}-shadow"

dry_notice
if [ "$TAG" = "--off" ]; then
  run gcloud pubsub subscriptions delete "$SUB" --project "$PROJECT" --quiet
  exit 0
fi

INFO=$(tag_info "$TEAM" "$TAG")
[ -n "$INFO" ] || die "le tag ${TAG} n'existe pas sur ${TEAM}-scorer"
TAG_URL=${INFO#*$'\t'}
if dry; then
  AUDIENCE=$(service_url "$TEAM")
else
  AUDIENCE=$(gcloud pubsub subscriptions describe "${TEAM}-live-push" --project "$PROJECT" \
    --format='value(pushConfig.oidcToken.audience)')
  [ -n "$AUDIENCE" ] || die "audience introuvable sur l'abonnement ${TEAM}-live-push"
fi
PUSH_ACCOUNT="${TEAM}-scorer-push@${PROJECT}.iam.gserviceaccount.com"

if ! dry && gcloud pubsub subscriptions describe "$SUB" --project "$PROJECT" >/dev/null 2>&1; then
  run gcloud pubsub subscriptions update "$SUB" --project "$PROJECT" \
    --push-endpoint "${TAG_URL}/pubsub/shadow" \
    --push-auth-service-account "$PUSH_ACCOUNT" --push-auth-token-audience "$AUDIENCE"
else
  run gcloud pubsub subscriptions create "$SUB" --project "$PROJECT" --topic ff-td6 \
    --push-endpoint "${TAG_URL}/pubsub/shadow" \
    --push-auth-service-account "$PUSH_ACCOUNT" --push-auth-token-audience "$AUDIENCE" \
    --ack-deadline 30 --message-retention-duration 3600s \
    --min-retry-delay 10s --max-retry-delay 60s \
    --labels "team=${TEAM}"
fi
