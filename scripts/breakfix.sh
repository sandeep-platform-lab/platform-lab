#!/usr/bin/env bash
# Break-fix dojo: injects a realistic fault into the local k3d cluster, shows you the "ticket",
# and checks whether you fixed it. Each scenario lives in labs/breakfix/<id>-<slug>/ and runs in
# its own namespace bf-<id>, so scenarios never interfere with each other or with namespace lab.
#
#   scripts/breakfix.sh list             all scenarios
#   scripts/breakfix.sh break 07         inject fault 07 and print its ticket
#   scripts/breakfix.sh ticket 07        print the ticket again
#   scripts/breakfix.sh hint 07          one nudge (try for 10 minutes first)
#   scripts/breakfix.sh check 07         did you fix it?
#   scripts/breakfix.sh reset 07|all     remove the scenario
#   scripts/breakfix.sh random           break a random scenario you haven't solved (mock-interview mode)
#
# Solutions: labs/breakfix/SOLUTIONS.md (spoilers).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABS="$ROOT/labs/breakfix"
SOLVED="$LABS/.solved"          # git-ignored progress file
export BF_INGRESS="${BF_INGRESS:-http://localhost:8080}"   # k3d load balancer -> Traefik

kubectl config current-context | grep -q '^k3d-lab$' || { echo "Not on the k3d-lab context"; exit 1; }

dir_of() {
  local d; d=$(ls -d "$LABS/$1"-* 2>/dev/null | head -1)
  [[ -n "$d" ]] || { echo "No scenario $1 (try: $0 list)"; exit 1; }
  echo "$d"
}
id_ok() { [[ "${1:-}" =~ ^[0-9]{2}$ ]] || { echo "Give a two-digit scenario id, e.g. 07"; exit 1; }; }

case "${1:-list}" in
  list)
    printf "%-4s %-28s %-12s %s\n" ID SCENARIO AREA STATUS
    for d in "$LABS"/[0-9][0-9]-*/; do
      d=${d%/}; id=$(basename "$d" | cut -c1-2); slug=$(basename "$d" | cut -c4-)
      area=$(sed -n 's/^# area: //p' "$d/ticket.txt")
      st=""; grep -qx "$id" "$SOLVED" 2>/dev/null && st="solved"
      kubectl get ns "bf-$id" >/dev/null 2>&1 && st="${st:+$st, }active"
      printf "%-4s %-28s %-12s %s\n" "$id" "$slug" "$area" "$st"
    done ;;
  break)
    id_ok "${2:-}"; d=$(dir_of "$2")
    BF_NS="bf-$2" BF_DIR="$d" bash "$d/break.sh"
    echo; grep -v '^# area:' "$d/ticket.txt"
    echo; echo "When you think it's fixed: $0 check $2" ;;
  ticket)
    id_ok "${2:-}"; grep -v '^# area:' "$(dir_of "$2")/ticket.txt" ;;
  hint)
    id_ok "${2:-}"; cat "$(dir_of "$2")/hint.txt" ;;
  check)
    id_ok "${2:-}"; d=$(dir_of "$2")
    if BF_NS="bf-$2" BF_DIR="$d" bash "$d/check.sh"; then
      echo "PASS: scenario $2 fixed."
      grep -qx "$2" "$SOLVED" 2>/dev/null || echo "$2" >> "$SOLVED"
      echo "Before resetting, say out loud: impact, evidence, root cause, fix, prevention."
    else
      echo "NOT YET: scenario $2 is still broken. ($0 hint $2)"; exit 1
    fi ;;
  reset)
    ids=("${2:-}"); [[ "${2:-}" == all ]] && ids=($(ls "$LABS" | grep -E '^[0-9]{2}-' | cut -c1-2))
    for id in "${ids[@]}"; do
      id_ok "$id"; d=$(dir_of "$id")
      [[ -f "$d/reset.sh" ]] && BF_NS="bf-$id" BF_DIR="$d" bash "$d/reset.sh"
      kubectl delete ns "bf-$id" --ignore-not-found --wait=false >/dev/null
      echo "reset $id"
    done ;;
  random)
    todo=$(ls "$LABS" | grep -E '^[0-9]{2}-' | cut -c1-2 | grep -vxF -f "$SOLVED" 2>/dev/null || true)
    [[ -n "$todo" ]] || todo=$(ls "$LABS" | grep -E '^[0-9]{2}-' | cut -c1-2)
    id=$(echo "$todo" | sort -R | head -1)
    echo "Random scenario: $id  (timer: 15 minutes, think aloud)"; exec "$0" break "$id" ;;
  *) sed -n '2,15p' "$0"; exit 1 ;;
esac
