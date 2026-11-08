source "$BF_DIR/../lib.sh"
deploy_ok report-generator 1
cpu=$(k get deploy report-generator -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}')
[[ -n "$cpu" ]] || fail "requests removed: keep a realistic CPU request so the scheduler can plan capacity"
ok "CPU request is $cpu"
