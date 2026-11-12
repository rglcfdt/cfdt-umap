#!/usr/bin/env bash

set -euo pipefail

echo "========================================"
echo " Création administrateur uMap"
echo "========================================"
echo

# Vérification de Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "ERREUR : Docker n'est pas installé ou accessible."
    exit 1
fi

# Recherche d'un conteneur uMap actif
UMAP_CONTAINER=$(
    docker ps \
        --format '{{.Names}} {{.Image}}' |
    awk 'tolower($0) ~ /umap/ {print $1; exit}'
)

if [ -z "${UMAP_CONTAINER}" ]; then
    echo "ERREUR : aucun conteneur uMap actif détecté."
    echo
    echo "Conteneurs actuellement démarrés :"
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
    exit 1
fi

echo "Conteneur uMap détecté : ${UMAP_CONTAINER}"
echo

echo "Lancement de la création du superutilisateur..."
echo
echo "Vous allez maintenant saisir les informations"
echo "du compte administrateur."
echo

docker exec -it "${UMAP_CONTAINER}" umap createsuperuser

echo
echo "========================================"
echo " Création terminée"
echo "========================================"
echo
echo "Administration uMap :"
echo "https://carto.cfdt.bzh/admin/"
echo