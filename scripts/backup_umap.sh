#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# Optional local configuration, excluded from Git.
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
BACKUP_ROOT="${BACKUP_ROOT:-/opt/cfdt/backups/umap}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
DATA_PATHS="${DATA_PATHS:-config custom}"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
BACKUP_NAME="umap_${TIMESTAMP}"
WORK_DIR="${BACKUP_ROOT}/.${BACKUP_NAME}.tmp"
FINAL_DIR="${BACKUP_ROOT}/${BACKUP_NAME}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
die() { log "ERREUR: $*" >&2; exit 1; }
cleanup() { [[ -d "${WORK_DIR}" ]] && rm -rf -- "${WORK_DIR}"; }
trap cleanup ERR INT TERM

compose() {
  local args=(-f "${COMPOSE_FILE}")
  [[ -f "${ENV_FILE}" ]] && args+=(--env-file "${ENV_FILE}")
  docker compose "${args[@]}" "$@"
}

command -v docker >/dev/null 2>&1 || die "Docker est introuvable."
docker compose version >/dev/null 2>&1 || die "Le plugin Docker Compose est introuvable."
[[ -f "${COMPOSE_FILE}" ]] || die "Fichier Compose absent: ${COMPOSE_FILE}"
mkdir -p -- "${BACKUP_ROOT}"
[[ ! -e "${FINAL_DIR}" ]] || die "La destination existe deja: ${FINAL_DIR}"
mkdir -p -- "${WORK_DIR}/files"

compose ps --status running "${POSTGRES_SERVICE}" --quiet | grep -q . \
  || die "Le service PostgreSQL '${POSTGRES_SERVICE}' n'est pas demarre."

log "Sauvegarde PostgreSQL de ${POSTGRES_DB}..."
compose exec -T "${POSTGRES_SERVICE}" pg_dump \
  --username="${POSTGRES_USER}" \
  --dbname="${POSTGRES_DB}" \
  --format=custom \
  --compress=9 \
  --no-owner \
  --no-acl > "${WORK_DIR}/database.dump"
[[ -s "${WORK_DIR}/database.dump" ]] || die "Le dump PostgreSQL est vide."

log "Verification du dump PostgreSQL..."
compose exec -T "${POSTGRES_SERVICE}" pg_restore --list < "${WORK_DIR}/database.dump" >/dev/null

log "Sauvegarde des fichiers versionnes/configures..."
read -r -a paths <<< "${DATA_PATHS}"
for rel in "${paths[@]}"; do
  [[ -e "${PROJECT_DIR}/${rel}" ]] || { log "Ignore (absent): ${rel}"; continue; }
  mkdir -p -- "${WORK_DIR}/files/$(dirname -- "${rel}")"
  cp -a -- "${PROJECT_DIR}/${rel}" "${WORK_DIR}/files/${rel}"
done

# Sauvegarde optionnelle de .env, chiffrement externe recommande.
if [[ "${BACKUP_ENV_FILE:-0}" == "1" && -f "${ENV_FILE}" ]]; then
  cp -a -- "${ENV_FILE}" "${WORK_DIR}/files/.env"
fi

compose config > "${WORK_DIR}/compose.resolved.yaml"
compose images --format json > "${WORK_DIR}/images.json" 2>/dev/null || true
if command -v git >/dev/null 2>&1 && git -C "${PROJECT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "${PROJECT_DIR}" rev-parse HEAD > "${WORK_DIR}/git_commit.txt"
  git -C "${PROJECT_DIR}" status --short > "${WORK_DIR}/git_status.txt"
fi

cat > "${WORK_DIR}/metadata.txt" <<EOF
backup_name=${BACKUP_NAME}
created_at=$(date --iso-8601=seconds)
host=$(hostname -f 2>/dev/null || hostname)
project_dir=${PROJECT_DIR}
compose_file=${COMPOSE_FILE}
postgres_service=${POSTGRES_SERVICE}
postgres_database=${POSTGRES_DB}
umap_service=${UMAP_SERVICE}
EOF

(
  cd "${WORK_DIR}"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)

mv -- "${WORK_DIR}" "${FINAL_DIR}"
trap - ERR INT TERM

log "Nettoyage des sauvegardes de plus de ${RETENTION_DAYS} jours..."
find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d -name 'umap_*' \
  -mtime "+${RETENTION_DAYS}" -print -exec rm -rf -- {} +

log "Sauvegarde terminee: ${FINAL_DIR}"
log "Controle: cd '${FINAL_DIR}' && sha256sum -c SHA256SUMS"
