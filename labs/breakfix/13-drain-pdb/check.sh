source "$BF_DIR/../lib.sh"
node=$(kubectl get ns "$BF_NS" -o jsonpath='{.metadata.annotations.breakfix/drain-node}')
[[ "$(kubectl get node "$node" -o jsonpath='{.spec.unschedulable}')" == true ]] || fail "$node is not cordoned"
k get pods -o wide --field-selector spec.nodeName="$node" --no-headers 2>/dev/null | grep -q . && fail "bf-13 pods still on $node"
ok "$node cordoned and empty of matching-engine pods"
deploy_ok matching-engine 2
k get pdb matching-engine >/dev/null 2>&1 || fail "PDB deleted: fix it, don't remove the protection"
ok "PDB still protects matching-engine"
echo "  (afterwards: kubectl uncordon $node)"
