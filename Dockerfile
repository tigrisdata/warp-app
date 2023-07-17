FROM minio/warp

EXPOSE 7761

ENTRYPOINT ["/warp", "client"]
