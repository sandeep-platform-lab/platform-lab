#!/usr/bin/env bash
# Creates a git-ignored .env with a random database password (once).
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -f .env ]; then
  printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 24)" > .env
  echo "Created jfrog-selfhosted/.env"
else
  echo ".env already exists, keeping it"
fi
