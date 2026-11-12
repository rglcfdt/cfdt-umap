READONLY_GROUP = "syndicat_readonly"


def cfdt_permissions(request):
    user = request.user

    is_syndicat_readonly = (
        user.is_authenticated
        and not user.is_superuser
        and user.groups.filter(name=READONLY_GROUP).exists()
    )

    return {
        "CFDT_SYNDICAT_READONLY": is_syndicat_readonly,
    }