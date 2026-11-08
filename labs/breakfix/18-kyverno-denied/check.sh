source "$BF_DIR/../lib.sh"
kubectl get clusterpolicy bf18-workload-standards -o jsonpath='{.spec.rules[*].validate.failureAction}' | grep -q Audit \
  && fail "policy switched to Audit"
[[ "$(kubectl get clusterpolicy bf18-workload-standards -o jsonpath='{.spec.rules[*].name}' | wc -w)" -eq 3 ]] || fail "policy rules removed"
ok "policy unchanged"
deploy_ok reporting 1
