source "$BF_DIR/../lib.sh"
deploy_ok cache-warmer 1
k logs deploy/cache-warmer | grep -q warmed || fail "app has not finished warming"
ok "cache warmed without being killed"
