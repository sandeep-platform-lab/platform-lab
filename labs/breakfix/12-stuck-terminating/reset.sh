kubectl -n "$BF_NS" patch pod batch-runner --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
