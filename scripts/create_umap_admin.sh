#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

echo "========================================"
echo " Création administrateur uMap"
echo "========================================"
echo

# Vérification Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "ERREUR : Docker n'est pas installé ou accessible."
    exit 1
fi

# Vérification Docker Compose
if ! docker compose version >/dev/null 2>&1; then
    echo "ERREUR : Docker Compose n'est pas disponible."
    exit 1
fi

cd "${PROJECT_DIR}"

if [[ ! -f "compose.yaml" ]]; then
    echo "ERREUR : compose.yaml introuvable dans :"
    echo "${PROJECT_DIR}"
    exit 1
fi

if [[ ! -f ".env" ]]; then
    echo "ERREUR : fichier .env introuvable."
    exit 1
fi

# Vérification du service uMap
if ! docker compose ps --status running app --quiet | grep -q .; then
    echo "ERREUR : le service uMap 'app' n'est pas démarré."
    echo
    docker compose ps
    exit 1
fi

echo "Instance uMap : ${PROJECT_DIR}"
echo "Service Docker : app"
echo

echo "Lancement de la création du superutilisateur..."
echo
echo "Saisissez maintenant les informations du compte administrateur."
echo

docker compose exec app umap createsuperuser

echo
echo "========================================"
echo " Superutilisateur créé"
echo "========================================"
echo
echo "Administration :"
echo "https://carto.cfdt.bzh/admin/"
echo