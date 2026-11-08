source "$BF_DIR/../lib.sh"
deploy_ok edge-proxy 1
node=$(k get pod -l app=edge-proxy -o jsonpath='{.items[0].spec.nodeName}')
[[ "$node" == k3d-lab-agent-1 ]] || fail "pod runs on $node, not on the edge pool node"
kubectl get node k3d-lab-agent-1 -o jsonpath='{.spec.taints}' | grep -q dedicated || fail "edge taint removed: other workloads can now land in the DMZ"
ok "runs on the edge node, taint still protects it"
