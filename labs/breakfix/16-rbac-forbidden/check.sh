source "$BF_DIR/../lib.sh"
SA=system:serviceaccount:bf-16:ci-deployer
can() { k auth can-i "$@" --as="$SA" >/dev/null 2>&1; }
for v in get patch watch; do can "$v" deployments.apps || fail "ci-deployer cannot $v deployments"; done
can list replicasets.apps || fail "ci-deployer cannot list replicasets (rollout status needs it)"
ok "ci-deployer can get/patch/watch deployments and list replicasets"
can get secrets && fail "ci-deployer can read secrets"
can delete deployments.apps && fail "ci-deployer can delete deployments"
kubectl auth can-i get pods -n default --as="$SA" >/dev/null 2>&1 && fail "ci-deployer has access outside bf-16"
ok "no secrets, no delete, nothing outside bf-16"
