#!/usr/bin/env bash
# Summarises the GitHub Enterprise audit log events streamed to Azure Blob Storage
# (terraform/azure-audit). Read-only, uses your Entra login (no storage keys).
#
# Usage: scripts/audit-log-report.sh [number_of_newest_blobs]   (default 50)
set -euo pipefail
cd "$(dirname "$0")/.."

N=${1:-50}
TF="terraform -chdir=terraform/azure-audit"
SA=$($TF output -raw storage_account)
C=$($TF output -raw container)
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

echo "== $SA/$C"
az storage blob list --account-name "$SA" -c "$C" --auth-mode login --num-results "*" \
  --query "sort_by([], &properties.creationTime)[].{n:name,t:properties.creationTime}" -o json > "$WORK/blobs.json"
total=$(jq length "$WORK/blobs.json")
echo "$total blobs; reading the newest $N"
[ "$total" -eq 0 ] && { echo "Nothing streamed yet. Events arrive within a few minutes of happening."; exit 0; }

jq -r --argjson n "$N" '.[-$n:][] | .n' "$WORK/blobs.json" | while read -r blob; do
  f="$WORK/$(echo "$blob" | tr '/' '_')"
  az storage blob download --account-name "$SA" -c "$C" -n "$blob" -f "$f" --auth-mode login --no-progress -o none
  # Blobs may be gzipped and may hold JSON lines or a JSON array: normalise to one event per line.
  if gzip -t "$f" 2>/dev/null; then gunzip -c "$f"; else cat "$f"; fi \
    | jq -c 'if type == "array" then .[] else . end' >> "$WORK/events.jsonl"
done

ev="$WORK/events.jsonl"
echo "$(wc -l < "$ev" | tr -d ' ') events"
echo
echo "== Top actions"
jq -r '.action' "$ev" | sort | uniq -c | sort -rn | head -10
echo
echo "== Top actors"
jq -r '.actor // "(none)"' "$ev" | sort | uniq -c | sort -rn | head -5
echo
echo "== Policy, security and access changes"
jq -r 'select(.action | test("^(business|enterprise|org|repository_ruleset|protected_branch|team|saml|oauth|personal_access_token|secret_scanning|actions)\\."))
       | "\(((.["@timestamp"] // .created_at // 0) / 1000) | todate)  \(.actor // "-")  \(.action)  \(.org // .business // "")"' "$ev" \
  | sort | tail -15
