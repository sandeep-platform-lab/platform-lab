#!/usr/bin/env bash
# Checks that every lab tool is installed and Docker is running.
set -u

ok=0
for t in docker kubectl k3d helm terraform az gh jf trivy cosign syft argocd jq yq; do
  if command -v "$t" >/dev/null 2>&1; then
    printf "  ✅ %s\n" "$t"
  else
    printf "  ❌ %s (missing)\n" "$t"; ok=1
  fi
done

if docker info >/dev/null 2>&1; then
  echo "  ✅ Docker daemon running"
else
  echo "  ❌ Docker daemon not running (start Docker Desktop)"; ok=1
fi

exit $ok
