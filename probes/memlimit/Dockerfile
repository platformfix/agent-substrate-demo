# run.sh cross-compiles memhog on the host first, so no Go toolchain image
# is needed here.
FROM scratch
COPY memhog /memhog
ENTRYPOINT ["/memhog"]
