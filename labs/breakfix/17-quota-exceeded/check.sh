source "$BF_DIR/../lib.sh"
[[ "$(k get resourcequota team-quota -o jsonpath='{.spec.hard.requests\.cpu}')" == 500m ]] || fail "quota changed: it needs approval"
ok "quota unchanged"
deploy_ok worker 3
