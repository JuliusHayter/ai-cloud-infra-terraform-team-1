#!/usr/bin/env bash
# Déploie une révision du service de scoring sans trafic, avec un tag, puis appelle son /health.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage : ./release.sh <équipe> <tag> <alias|version|-> [CLÉ=VALEUR...]

  ./release.sh team1 candidate challenger
  ./release.sh team1 candidate 3 ALERT_THRESHOLD=0.0012

<tag>              nom de l'adresse de la révision (candidate, par exemple) ; `champion` est réservé
<alias|version|->  modèle du registre à charger (alias ou numéro de version), ou `-` pour garder le modèle
                   de la révision de base ; seules les variables passées changent
CLÉ=VALEUR         variables d'environnement à fixer sur la nouvelle révision

La révision ne reçoit aucun trafic. Toutes les variables d'une révision de base sont reprises, puis les
CLÉ=VALEUR et le modèle choisi les remplacent. La base est la révision qui a le plus fort pourcentage de trafic ;
avec `-`, c'est la révision qui porte le tag `candidate` si ce tag existe. Le script affiche la base (tag et
trafic), l'adresse du tag et la réponse de /health.

DRY_RUN=1 imprime les commandes qui écrivent au lieu de les exécuter.
USAGE
}

case "${1:-}" in
  -h | --help) usage; exit 0 ;;
esac
[ $# -ge 3 ] || { usage >&2; exit 1; }

. "$(dirname "$0")/lib.sh"

TEAM=$1
TAG=$2
MODEL=$3
shift 3

check_team "$TEAM"
case "$TAG" in
  champion) die "le tag champion est réservé à la révision de référence" ;;
  [a-z]*) ;;
  *) die "tag invalide : '$TAG' (minuscules, chiffres et tirets)" ;;
esac
case "$TAG" in
  *[!a-z0-9-]*) die "tag invalide : '$TAG' (minuscules, chiffres et tirets)" ;;
esac
for pair in "$@"; do
  case "$pair" in
    [A-Z_]*=*) ;;
    *) die "variable attendue sous la forme CLÉ=VALEUR en majuscules, reçu : '$pair'" ;;
  esac
  case "$pair" in
    *\;*) die "le caractère ; est interdit dans '$pair'" ;;
  esac
done

dry_notice
SERVICE="${TEAM}-scorer"
if [ "$MODEL" = "-" ]; then
  BASE_INFO=$(base_revision "$TEAM" candidate)
else
  BASE_INFO=$(base_revision "$TEAM")
fi
BASE=${BASE_INFO%% *}
BASE_REST=${BASE_INFO#* }
IMAGE=$(revision_image "$BASE")
ENV_LIST=$(revision_env "$BASE")

if [ "$MODEL" != "-" ]; then
  INFO=$(model_info "$TEAM" "$MODEL")
  VERSION=${INFO%%$'\t'*}
  ENV_LIST=$(env_set "$ENV_LIST" MODELS_DIR "$(uri_to_mount "${INFO#*$'\t'}" /mnt/models)")
  ENV_LIST=$(env_set "$ENV_LIST" MODEL_VERSION "$VERSION")
fi
for pair in "$@"; do
  ENV_LIST=$(env_set "$ENV_LIST" "${pair%%=*}" "${pair#*=}")
done

echo "Base : ${BASE} (tag : ${BASE_REST% *}, trafic : ${BASE_REST#* } %)"
echo "Variables de la nouvelle révision :"
printf '%s\n' "$ENV_LIST" | sed 's/^/  /'

run gcloud run deploy "$SERVICE" --region "$REGION" --project "$PROJECT" --quiet \
  --image "$IMAGE" --no-traffic --tag "$TAG" \
  --revision-suffix "${TAG}-$(date +%m%d%H%M%S)" \
  --set-env-vars "$(env_flag "$ENV_LIST")"

INFO=$(tag_info "$TEAM" "$TAG")
[ -n "$INFO" ] || die "le tag ${TAG} n'existe pas sur ${SERVICE}"
REVISION=${INFO%%$'\t'*}
URL=${INFO#*$'\t'}
echo "Révision : ${REVISION}"
echo "Adresse du tag : ${URL}"

if dry; then
  echo "+ curl -sS --max-time 30 -H 'Authorization: Bearer \$(gcloud auth print-identity-token)' ${URL}/health"
else
  curl -sS --max-time 30 -H "Authorization: Bearer $(identity_token)" "${URL}/health" && echo
fi
