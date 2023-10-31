#!/bin/bash
set -euxo pipefail

export PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}"

exec "$@"