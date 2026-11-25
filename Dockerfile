FROM umap/umap:3.6.3

USER root

COPY custom/patches/patch_permissions.py /tmp/patch_permissions.py

RUN /venv/bin/python /tmp/patch_permissions.py \
    && rm -f /tmp/patch_permissions.py