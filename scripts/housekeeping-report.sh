#!/usr/bin/env bash
# Read-only housekeeping report for the lab JFrog instance: storage per repo, and what the cleanup
# policies in terraform/jfrog/housekeeping.tf WOULD delete. Deletes nothing.
#
# Usage: scripts/housekeeping-report.sh [keep_n_images] [remote_unused_days]
# Needs JFROG_URL and JFROG_ACCESS_TOKEN (source ~/workspace/.env).
set -euo pipefail

KEEP_N=${1:-10}
UNUSED_DAYS=${2:-60}
: "${JFROG_URL:?source ~/workspace/.env first}" "${JFROG_ACCESS_TOKEN:?}"
H="Authorization: Bearer $JFROG_ACCESS_TOKEN"
api() { curl -sf -H "$H" "$JFROG_URL/artifactory/api/$1"; }
aql() { curl -sf -H "$H" -H "Content-Type: text/plain" -X POST "$JFROG_URL/artifactory/api/search/aql" -d "$1"; }

echo "== Storage per lab repo"
api storageinfo | jq -r '.repositoriesSummaryList[] | select(.repoKey|startswith("lab-"))
  | "\(.repoKey)\t\(.filesCount) files\t\(.usedSpace)"' | column -t -s $'\t'

echo
echo "== Dev images: tags beyond the newest $KEEP_N per image (lab-dev-docker-keep-10 would delete)"
aql 'items.find({"repo":"lab-docker-dev-local","name":"manifest.json"}).include("path","created")' \
  | jq -r --argjson keep "$KEEP_N" '
      [.results[] | {image: (.path|split("/")[:-1]|join("/")), tag: (.path|split("/")|last), created}]
      | group_by(.image)[]
      | sort_by(.created) | reverse
      | "\(.[0].image): \(length) tags, \([.[$keep:][]] | length) to delete"
        + (if length > $keep then "  e.g. \([.[$keep:][] | .tag][:5] | join(", "))" else "" end)'

echo
echo "== Signature and attestation tags in dev (they count as tags too)"
aql 'items.find({"repo":"lab-docker-dev-local","name":"manifest.json","path":{"$match":"*sha256-*"}}).include("path")' \
  | jq -r '[.results[].path | split("/")|last] | "\(length) tags: \(map(select(endswith(".sig")))|length) .sig, \(map(select(endswith(".att")))|length) .att"'

echo
echo "== Remote caches: items not downloaded for $UNUSED_DAYS days (lab-remote-cache-unused-60d would delete)"
since=$(date -u -v-"${UNUSED_DAYS}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "-${UNUSED_DAYS} days" +%Y-%m-%dT%H:%M:%SZ)
for repo in lab-docker-remote-cache lab-pypi-remote-cache; do
  aql "items.find({\"repo\":\"$repo\",\"\$or\":[{\"stat.downloaded\":{\"\$lt\":\"$since\"}},{\"stat.downloads\":{\"\$eq\":null}}]}).include(\"name\",\"size\")" \
    | jq -r --arg r "$repo" '"\($r): \(.results|length) items, \(([.results[].size]|add // 0)/1048576|floor) MB"'
done

echo
echo "== Pinned (retention.keep=true): never deleted"
aql 'items.find({"repo":{"$match":"lab-*"},"@retention.keep":"true"}).include("repo","path","name")' \
  | jq -r 'if (.results|length)==0 then "none yet" else .results[] | "\(.repo)/\(.path)/\(.name)" end'

echo
echo "== Build-info: lab-api"
api build/lab-api | jq -r '"\(.buildsNumbers|length) builds stored (oldest: #\([.buildsNumbers[].uri|ltrimstr("/")|tonumber]|min), newest: #\([.buildsNumbers[].uri|ltrimstr("/")|tonumber]|max))"'
