from django.http import HttpResponseForbidden


READONLY_GROUP = "syndicat_readonly"

# Noms des routes uMap 3.6.3 à interdire.
BLOCKED_URL_NAMES = {
    "map_new",
    "map_create",
}


class SyndicatReadOnlyMiddleware:
    """
    Empêche les comptes membres du groupe syndicat_readonly
    de créer de nouvelles cartes uMap.

    Les superutilisateurs ne sont jamais bloqués.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        return self.get_response(request)

    def process_view(self, request, view_func, view_args, view_kwargs):
        user = request.user

        if not user.is_authenticated:
            return None

        if user.is_superuser:
            return None

        if not user.groups.filter(name=READONLY_GROUP).exists():
            return None

        resolver_match = request.resolver_match
        if resolver_match is None:
            return None

        if resolver_match.url_name in BLOCKED_URL_NAMES:

            # Aucun visiteur anonyme ne peut créer une carte.
            if not user.is_authenticated:
                return HttpResponseForbidden(
                    "Vous devez être connecté pour créer une carte.",
                    content_type="text/plain; charset=utf-8",
                )

            # Les superadmins restent autorisés.
            if user.is_superuser:
                return None

            # Les comptes syndicats sont en lecture seule.
            if user.groups.filter(name=READONLY_GROUP).exists():
                return HttpResponseForbidden(
                    "Votre compte est configuré en lecture seule. "
                    "Vous pouvez consulter les cartes qui vous sont attribuées, "
                    "mais vous ne pouvez pas créer de nouvelle carte.",
                    content_type="text/plain; charset=utf-8",
                )

        return None