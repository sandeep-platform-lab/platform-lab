source "$BF_DIR/../lib.sh"
st=$(kubectl get node k3d-lab-agent-0 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
[[ "$st" == True ]] || fail "k3d-lab-agent-0 Ready=$st"
ok "k3d-lab-agent-0 Ready"
deploy_ok quotes 2
