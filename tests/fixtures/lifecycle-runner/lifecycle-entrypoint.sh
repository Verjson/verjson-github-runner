#!/bin/sh
set -eu

case "${RUNNER_NAME}" in
  crash-*)
    exit 17
    ;;
esac

if test -e /tmp/verjson-job-marker; then
  echo "writable-layer marker persisted" >&2
  exit 91
fi
touch /tmp/verjson-job-marker
cat /etc/hostname

case "${RUNNER_NAME}" in
  ephemeral-*)
    sleep 2
    ;;
  *)
    trap 'exit 0' TERM INT
    while :; do
      sleep 1
    done
    ;;
esac
