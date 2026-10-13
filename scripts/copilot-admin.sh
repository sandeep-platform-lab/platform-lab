#!/usr/bin/env bash
# Copilot Business administration for the lab organization, via the REST API.
#
#   scripts/copilot-admin.sh status              settings: seat management, features, public code
#   scripts/copilot-admin.sh seats               who has a seat, via which team, last activity
#   scripts/copilot-admin.sh inactive [days]     seats unused for N days (default 30): reclaim candidates
#   scripts/copilot-admin.sh assign-team TEAM    give every member of TEAM a seat (team-based licensing)
#   scripts/copilot-admin.sh remove-team TEAM    remove TEAM's seats (effective at the end of the cycle)
#   scripts/copilot-admin.sh metrics             latest 28-day usage report (needs the usage metrics policy)
#
# Needs the admin:org scope (and manage_billing:copilot for some calls). Read-only except assign/remove.
set -euo pipefail

ORG=${ORG:-sandeep-platform-lab}
PRICE_USD=${PRICE_USD:-19}   # Copilot Business, per seat per month
cmd=${1:-status}

case "$cmd" in
  status)
    gh api "orgs/$ORG/copilot/billing" --jq '
      "plan:                    \(.plan_type)",
      "seat management:         \(.seat_management_setting)",
      "suggestions matching public code: \(.public_code_suggestions)",
      "chat in IDE:             \(.ide_chat)",
      "chat on github.com:      \(.platform_chat)",
      "Copilot in the CLI:      \(.cli)",
      "seats: \(.seat_breakdown.total) total, \(.seat_breakdown.active_this_cycle) active this cycle, \(.seat_breakdown.inactive_this_cycle) inactive, \(.seat_breakdown.pending_cancellation) pending cancellation"'
    ;;

  seats)
    gh api --paginate "orgs/$ORG/copilot/billing/seats" --jq '.seats[] |
      [.assignee.login, (.assigning_team.slug // "direct"), (.created_at[:10]),
       (.last_activity_at // "never" | .[:10]), (.last_activity_editor // "-"),
       (.pending_cancellation_date // "-")] | @tsv' \
      | (printf 'USER\tVIA TEAM\tSINCE\tLAST ACTIVE\tEDITOR\tCANCELS ON\n'; cat) | column -t -s $'\t'
    ;;

  inactive)
    days=${2:-30}
    cutoff=$(date -u -v-"${days}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "-${days} days" +%Y-%m-%dT%H:%M:%SZ)
    gh api --paginate "orgs/$ORG/copilot/billing/seats" --jq ".seats[]
      | select(.pending_cancellation_date == null)
      | select(.last_activity_at == null or .last_activity_at < \"$cutoff\")
      | \"\(.assignee.login)\t\(.assigning_team.slug // \"direct\")\t\(.last_activity_at // \"never\")\"" > /tmp/copilot-inactive.tsv
    n=$(wc -l < /tmp/copilot-inactive.tsv | tr -d ' ')
    echo "Seats with no activity for $days days: $n (about \$$((n * PRICE_USD))/month)"
    [ "$n" -gt 0 ] && column -t -s $'\t' /tmp/copilot-inactive.tsv
    rm -f /tmp/copilot-inactive.tsv
    echo "Reclaim: remove the user from the licensed team, or: gh api -X DELETE orgs/$ORG/copilot/billing/selected_users -f 'selected_usernames[]=<login>'"
    ;;

  assign-team|remove-team)
    team=${2:?team slug required}
    method=$([ "$cmd" = assign-team ] && echo POST || echo DELETE)
    gh api -X "$method" "orgs/$ORG/copilot/billing/selected_teams" -f "selected_teams[]=$team" \
      --jq 'if .seats_created != null then "seats created: \(.seats_created)" else "seats cancelled: \(.seats_cancelled)" end'
    ;;

  metrics)
    # Usage metrics come as downloadable reports. Needs the enterprise policy
    # "Copilot usage metrics" = Enabled everywhere, and read:org.
    if ! out=$(gh api "orgs/$ORG/copilot/metrics/reports/organization-28-day/latest" 2>&1); then
      echo "No report: $(echo "$out" | jq -r '.message? // empty' 2>/dev/null | head -1)"
      echo "Check the enterprise policy 'Copilot usage metrics' (Enabled everywhere) and that seats have been used."
      exit 0
    fi
    echo "$out" | jq -r 'to_entries[] | select(.value|type != "array") | "\(.key): \(.value)"'
    echo "$out" | jq -r '.. | strings | select(startswith("https://"))' | head -3 | while read -r url; do
      echo "--- report $(echo "$url" | cut -d'?' -f1 | awk -F/ '{print $NF}')"
      f=$(mktemp); curl -sfL "$url" -o "$f"
      if gzip -t "$f" 2>/dev/null; then gunzip -c "$f"; else cat "$f"; fi | head -c 1500; echo
      rm -f "$f"
    done
    ;;

  *)
    sed -n '2,10p' "$0"; exit 1
    ;;
esac
