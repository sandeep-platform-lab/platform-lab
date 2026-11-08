node=$(kubectl get ns "$BF_NS" -o jsonpath='{.metadata.annotations.breakfix/drain-node}' 2>/dev/null || true)
[[ -n "$node" ]] && kubectl uncordon "$node" >/dev/null 2>&1 || true
