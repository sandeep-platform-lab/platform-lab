source "$BF_DIR/../lib.sh"
[[ "$(kubectl get ns "$BF_NS" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')" == restricted ]] \
  || fail "namespace no longer enforces restricted"
ok "namespace still enforces restricted"
deploy_ok web 1
k exec deploy/web -- sh -c 'id -u' | grep -qv '^0$' || fail "container runs as root"
ok "web runs as non-root (uid $(k exec deploy/web -- id -u))"
