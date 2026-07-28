FROM busybox:1.36.1@sha256:73aaf090f3d85aa34ee199857f03fa3a95c8ede2ffd4cc2cdb5b94e566b11662

COPY lifecycle-entrypoint.sh /lifecycle-entrypoint.sh
RUN chmod 0555 /lifecycle-entrypoint.sh

ENTRYPOINT ["/lifecycle-entrypoint.sh"]
