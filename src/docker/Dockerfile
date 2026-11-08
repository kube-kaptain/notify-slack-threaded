FROM scratch
# Just a transport image, layer /scripts into /kd/bin alongside the deploy scripts.
# /fields documents the ConfigMap and Secret entries the scripts need.

COPY --chmod=755 scripts/ /scripts
COPY fields/ /fields
