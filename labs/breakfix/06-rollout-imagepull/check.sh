source "$BF_DIR/../lib.sh"
deploy_ok catalog 3
k get pods -l app=catalog -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' | grep -q 1.299 \
  && fail "a pod still uses the broken image"
ok "no pods on the broken image"
