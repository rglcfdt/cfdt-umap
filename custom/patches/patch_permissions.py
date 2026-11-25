#!/usr/bin/env python3

"""
Patch des permissions uMap pour l'instance CFDT.

Base supportée :
    umap/umap:3.6.3

Objectif :

    OWNER
        consultation : oui
        modification : oui

    EDITORS
        consultation : oui
        modification : oui

    TEAM
        consultation : oui
        modification : non

Le comportement standard de uMap 3.6.3 autorise les membres de la Team
à modifier une Map ou une DataLayer lorsque edit_status == COLLABORATORS.

Ce patch supprime uniquement le droit d'édition hérité de la Team.

IMPORTANT :
    Map.can_view() n'est volontairement PAS modifié.

Cela permet aux membres d'une Team de continuer à consulter les cartes
privées qui leur sont affectées.
"""

from pathlib import Path
import sys


MODELS_FILE = Path(
    "/venv/lib/python3.12/site-packages/umap/models.py"
)


MAP_OLD = """        elif self.edit_status == self.COLLABORATORS:
            if user in self.editors.all() or self.team in user.teams.all():
                can = True
"""

MAP_NEW = """        elif self.edit_status == self.COLLABORATORS:
            if user in self.editors.all():
                can = True
"""


DATALAYER_OLD = """        elif user.is_authenticated and self.edit_status == self.COLLABORATORS:
            if user in self.map.editors.all() or self.map.team in user.teams.all():
                can = True
"""

DATALAYER_NEW = """        elif user.is_authenticated and self.edit_status == self.COLLABORATORS:
            if user in self.map.editors.all():
                can = True
"""


def fail(message: str) -> None:
    print()
    print("ERREUR PATCH UMAP")
    print("==================")
    print(message)
    print()
    sys.exit(1)


def main() -> None:
    print("============================================================")
    print("Patch des permissions uMap CFDT")
    print("============================================================")
    print()
    print(f"Fichier : {MODELS_FILE}")
    print()

    # --------------------------------------------------------
    # Vérifications fichier
    # --------------------------------------------------------

    if not MODELS_FILE.exists():
        fail(
            f"Le fichier uMap est introuvable : {MODELS_FILE}"
        )

    if not MODELS_FILE.is_file():
        fail(
            f"Le chemin n'est pas un fichier : {MODELS_FILE}"
        )

    original = MODELS_FILE.read_text(encoding="utf-8")

    # --------------------------------------------------------
    # Vérification Map.can_edit()
    # --------------------------------------------------------

    map_old_count = original.count(MAP_OLD)
    map_new_count = original.count(MAP_NEW)

    print("Map.can_edit()")
    print(f"  bloc original : {map_old_count}")
    print(f"  bloc patché   : {map_new_count}")

    if map_old_count != 1:
        fail(
            "Le bloc attendu dans Map.can_edit() n'a pas été "
            "trouvé exactement une fois.\n"
            f"Occurrences trouvées : {map_old_count}\n\n"
            "Le code source uMap a probablement changé. "
            "Le patch n'est pas appliqué."
        )

    # --------------------------------------------------------
    # Vérification DataLayer.can_edit()
    # --------------------------------------------------------

    datalayer_old_count = original.count(DATALAYER_OLD)
    datalayer_new_count = original.count(DATALAYER_NEW)

    print()
    print("DataLayer.can_edit()")
    print(f"  bloc original : {datalayer_old_count}")
    print(f"  bloc patché   : {datalayer_new_count}")

    if datalayer_old_count != 1:
        fail(
            "Le bloc attendu dans DataLayer.can_edit() n'a pas "
            "été trouvé exactement une fois.\n"
            f"Occurrences trouvées : {datalayer_old_count}\n\n"
            "Le code source uMap a probablement changé. "
            "Le patch n'est pas appliqué."
        )

    # --------------------------------------------------------
    # Application
    # --------------------------------------------------------

    patched = original.replace(
        MAP_OLD,
        MAP_NEW,
        1,
    )

    patched = patched.replace(
        DATALAYER_OLD,
        DATALAYER_NEW,
        1,
    )

    # --------------------------------------------------------
    # Contrôles mémoire avant écriture
    # --------------------------------------------------------

    if MAP_OLD in patched:
        fail(
            "L'ancien contrôle Map.can_edit() est encore présent "
            "après substitution."
        )

    if DATALAYER_OLD in patched:
        fail(
            "L'ancien contrôle DataLayer.can_edit() est encore "
            "présent après substitution."
        )

    if patched.count(MAP_NEW) != 1:
        fail(
            "Le nouveau contrôle Map.can_edit() n'est pas présent "
            "exactement une fois après patch."
        )

    if patched.count(DATALAYER_NEW) != 1:
        fail(
            "Le nouveau contrôle DataLayer.can_edit() n'est pas "
            "présent exactement une fois après patch."
        )

    # --------------------------------------------------------
    # Sécurité supplémentaire :
    #
    # on vérifie que can_view conserve bien la logique Team.
    # --------------------------------------------------------

    CAN_VIEW_TEAM_CHECK = (
        "self.team not in request.user.teams.all()"
    )

    if CAN_VIEW_TEAM_CHECK not in patched:
        fail(
            "La logique Team attendue dans Map.can_view() "
            "n'a pas été trouvée.\n\n"
            "Le patch refuse de continuer car la consultation "
            "des cartes privées par les Teams doit être conservée."
        )

    # --------------------------------------------------------
    # Écriture
    # --------------------------------------------------------

    MODELS_FILE.write_text(
        patched,
        encoding="utf-8",
    )

    # --------------------------------------------------------
    # Relecture du fichier réellement écrit
    # --------------------------------------------------------

    written = MODELS_FILE.read_text(
        encoding="utf-8"
    )

    if MAP_OLD in written:
        fail(
            "L'ancien contrôle Map.can_edit() est toujours "
            "présent dans le fichier écrit."
        )

    if DATALAYER_OLD in written:
        fail(
            "L'ancien contrôle DataLayer.can_edit() est toujours "
            "présent dans le fichier écrit."
        )

    if written.count(MAP_NEW) != 1:
        fail(
            "Le contrôle Map.can_edit() patché est incorrect "
            "après écriture."
        )

    if written.count(DATALAYER_NEW) != 1:
        fail(
            "Le contrôle DataLayer.can_edit() patché est incorrect "
            "après écriture."
        )

    if CAN_VIEW_TEAM_CHECK not in written:
        fail(
            "La logique Team de Map.can_view() a disparu."
        )

    print()
    print("============================================================")
    print("Patch appliqué avec succès")
    print("============================================================")
    print()
    print("Résultat :")
    print("  owner       : modification autorisée")
    print("  editors     : modification autorisée")
    print("  team        : modification interdite")
    print("  team        : consultation conservée")
    print()


if __name__ == "__main__":
    main()