source "$BF_DIR/../lib.sh"
deploy_ok payments-api 1
k logs deploy/payments-api | grep -q currency=CHF || fail "app started but did not read its config"
ok "app reads /etc/app/app.conf"
