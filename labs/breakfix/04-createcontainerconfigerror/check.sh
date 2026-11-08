source "$BF_DIR/../lib.sh"
deploy_ok orders-api 1
k exec deploy/orders-api -- sh -c 'test -n "$DB_PASSWORD"' || fail "DB_PASSWORD is empty in the container"
ok "DB_PASSWORD is set"
