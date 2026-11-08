source "$BF_DIR/../lib.sh"
k get pod batch-runner >/dev/null 2>&1 && fail "pod batch-runner still exists"
ok "batch-runner is gone"
