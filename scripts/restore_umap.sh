#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${UMAP_BACKUP_CONFIG:-${PROJECT_DIR}/backup.env}"
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

COMPOSE_FILE="${COMPOSE_FILE:-${PROJECT_DIR}/compose.yml}"
ENV_FILE="${ENV_FILE:-${PROJECT_DIR}/.env}"
POSTGRES_SERVICE="${POSTGRES_SERVICE:-db}"
POSTGRES_DB="${POSTGRES_DB:-umap}"
POSTGRES_USER="${POSTGRES_USER:-umap}"
UMAP_SERVICE="${UMAP_SERVICE:-umap}"
RESTORE_FILES="${RESTORE_FILES:-1}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
die() { log "ERREUR: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $0 /chemin/vers/umap_AAAAMMJJ_HHMMSS [--yes]

Restaure la base PostgreSQL et, par defaut, les fichiers config/custom.
La restauration est destructive pour la base cible '${POSTGRES_DB}'.
EOF
}

[[ $# -ge 1 ]] || { usage; exit 2; }
BACKUP_DIR="$(realpath -e -- "$1")"
AUTO_YES=0
[[ "${2:-}" == "--yes" ]] && AUTO_YES=1

compose() {
  local args=(-f "${COMPOSE_FILE}")
  [[ -f "${ENV_FILE}" ]] && args+=(--env-file "${ENV_FILE}")
  docker compose "${args[@]}" "$@"
}

command -v docker >/dev/null 2>&1 || die "Docker est introuvable."
[[ -f "${COMPOSE_FILE}" ]] || die "Fichier Compose absent: ${COMPOSE_FILE}"
[[ -f "${BACKUP_DIR}/database.dump" ]] || die "Dump absent: ${BACKUP_DIR}/database.dump"
[[ -f "${BACKUP_DIR}/SHA256SUMS" ]] || die "Sommes de controle absentes."

log "Verification de l'integrite..."
(cd "${BACKUP_DIR}" && sha256sum -c SHA256SUMS)

log "Cible: base '${POSTGRES_DB}', service '${POSTGRES_SERVICE}'."
if [[ ${AUTO_YES} -ne 1 ]]; then
  printf "Tapez exactement RESTAURER pour continuer: "
  read -r confirmation
  [[ "${confirmation}" == "RESTAURER" ]] || die "Restauration annulee."
fi

compose ps --status running "${POSTGRES_SERVICE}" --quiet | grep -q . \
  || die "Le service PostgreSQL '${POSTGRES_SERVICE}' n'est pas demarre."

# Arret de l'application uniquement. PostgreSQL reste disponible pour la restauration.
log "Arret du service applicatif ${UMAP_SERVICE}..."
compose stop "${UMAP_SERVICE}" || true

restart_app() {
  log "Redemarrage du service ${UMAP_SERVICE}..."
  compose up -d "${UMAP_SERVICE}" || true
}
trap restart_app EXIT

log "Fermeture des connexions actives..."
compose exec -T "${POSTGRES_SERVICE}" psql \
  --username="${POSTGRES_USER}" --dbname=postgres \
  --set=ON_ERROR_STOP=1 \
  --command="SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${POSTGRES_DB}' AND pid <> pg_backend_pid();"

log "Recreation de la base ${POSTGRES_DB}..."
compose exec -T "${POSTGRES_SERVICE}" dropdb \
  --username="${POSTGRES_USER}" --if-exists "${POSTGRES_DB}"
compose exec -T "${POSTGRES_SERVICE}" createdb \
  --username="${POSTGRES_USER}" --owner="${POSTGRES_USER}" "${POSTGRES_DB}"

log "Restauration PostgreSQL..."
compose exec -T "${POSTGRES_SERVICE}" pg_restore \
  --username="${POSTGRES_USER}" \
  --dbname="${POSTGRES_DB}" \
  --exit-on-error \
  --no-owner \
  --no-acl < "${BACKUP_DIR}/database.dump"

if [[ "${RESTORE_FILES}" == "1" && -d "${BACKUP_DIR}/files" ]]; then
  log "Restauration des fichiers..."
  shopt -s dotglob nullglob
  for source in "${BACKUP_DIR}/files"/*; do
    name="$(basename -- "${source}")"
    if [[ "${name}" == ".env" && "${RESTORE_ENV_FILE:-0}" != "1" ]]; then
      log "Ignore par securite: .env"
      continue
    fi
    rm -rf -- "${PROJECT_DIR:?}/${name}"
    cp -a -- "${source}" "${PROJECT_DIR}/${name}"
  done
  shopt -u dotglob nullglob
fi

log "Restauration terminee."
trap - EXIT
restart_app
log "Controle recommande: docker compose -f '${COMPOSE_FILE}' ps"
log "Puis: docker compose -f '${COMPOSE_FILE}' logs --tail=200 '${UMAP_SERVICE}'"
