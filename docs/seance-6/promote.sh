#!/usr/bin/env bash
# Déplace l'alias champion du registre sur une version du modèle de l'équipe.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage : ./promote.sh <équipe> <version>

  ./promote.sh team1 3

Retire l'alias `champion` de la version qui le porte et le pose sur <version> (API Vertex AI mergeVersionAliases).
Ne touche ni au service ni à son trafic.

DRY_RUN=1 imprime les appels qui écrivent au lieu de les exécuter.
USAGE
}

case "${1:-}" in
  -h | --help) usage; exit 0 ;;
esac
[ $# -eq 2 ] || { usage >&2; exit 1; }

. "$(dirname "$0")/lib.sh"

TEAM=$1
VERSION=$2
check_team "$TEAM"
case "$VERSION" in
  '' | *[!0-9]*) die "numéro de version attendu, reçu : '${VERSION}'" ;;
esac

dry_notice
ID=$(model_id "$TEAM")
CURRENT=$(model_info "$TEAM" champion)
CURRENT=${CURRENT%%$'\t'*}
API="https://${REGION}-aiplatform.googleapis.com/v1/projects/${PROJECT}/locations/${REGION}/models"

merge_aliases() {
  local version=$1 aliases=$2 out code
  if dry; then
    echo "+ curl -sS -X POST -H 'Authorization: Bearer \$(gcloud auth print-access-token)' -H 'Content-Type: application/json' -d '{\"versionAliases\": [\"${aliases}\"]}' ${API}/${ID}@${version}:mergeVersionAliases"
    return 0
  fi
  out=$(curl -sS -w '\n%{http_code}' -X POST \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H 'Content-Type: application/json' \
    -d "{\"versionAliases\": [\"${aliases}\"]}" \
    "${API}/${ID}@${version}:mergeVersionAliases") || true
  code=${out##*$'\n'}
  if [ "$code" != 200 ]; then
    echo "mergeVersionAliases (${aliases} sur la version ${version}) a répondu '${code}' : ${out%$'\n'*}" >&2
    return 1
  fi
}

if [ "$CURRENT" = "$VERSION" ]; then
  echo "La version ${VERSION} porte déjà l'alias champion."
  exit 0
fi

echo "champion : version ${CURRENT} -> version ${VERSION}"
merge_aliases "$CURRENT" "-champion" || die "Échec avant tout changement : champion reste sur la version ${CURRENT}."
if ! merge_aliases "$VERSION" "champion"; then
  if merge_aliases "$CURRENT" "champion"; then
    die "Échec de la promotion : champion a été remis sur la version ${CURRENT}, état final inchangé."
  fi
  die "Échec de la promotion et de la remise en état : aucune version ne porte champion. Relancer ./promote.sh ${TEAM} ${CURRENT}."
fi
