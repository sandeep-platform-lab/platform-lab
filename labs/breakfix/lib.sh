# Shared helpers for break.sh / check.sh / reset.sh. Sourced, not executed.
# BF_NS (namespace) and BF_DIR (scenario folder) are set by scripts/breakfix.sh.
set -euo pipefail

k()    { kubectl -n "$BF_NS" "$@"; }
ok()   { echo "  ✓ $*"; }
fail() { echo "  ✗ $*"; exit 1; }

# Create the scenario namespace (idempotent) and label it so it's easy to find.
mkns() {
  if [[ "$(kubectl get ns "$BF_NS" -o jsonpath='{.status.phase}' 2>/dev/null)" == Terminating ]]; then
    echo "waiting for the previous $BF_NS to finish deleting..."
    kubectl wait --for=delete ns/"$BF_NS" --timeout=180s >/dev/null 2>&1 || true
  fi
  kubectl create ns "$BF_NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl label ns "$BF_NS" breakfix=true --overwrite >/dev/null
}

# Apply YAML from stdin into the scenario namespace.
apply() { kubectl -n "$BF_NS" apply -f - >/dev/null; }

# Deployment has at least N available replicas and no rollout in progress.
deploy_ok() {
  local name=$1 want=${2:-1} avail rolled=true
  k rollout status deploy/"$name" --timeout=30s >/dev/null 2>&1 || rolled=false
  avail=$(k get deploy "$name" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)
  [[ "${avail:-0}" -ge "$want" ]] || fail "deployment/$name has ${avail:-0} available replicas (want $want)"
  $rolled || fail "deployment/$name rollout not complete"
  ok "deployment/$name: $avail available, rollout complete"
}

# HTTP status through the k3d load balancer -> Traefik, using a Host header.
http_code() { curl -s -o /dev/null -m 5 -w '%{http_code}' -H "Host: $1" "$BF_INGRESS${2:-/}" || true; }
http_ok() {
  local code; code=$(http_code "$1" "${2:-/}")
  [[ "$code" == 200 ]] || fail "http://$1${2:-/} returns $code (want 200)"
  ok "http://$1${2:-/} returns 200"
}

# Wait up to N seconds for a condition command to succeed (used in break.sh to reach the broken state).
wait_for() { local t=$1; shift; for _ in $(seq "$t"); do "$@" >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }
