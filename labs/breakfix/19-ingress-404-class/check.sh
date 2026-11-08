source "$BF_DIR/../lib.sh"
http_ok bf19.localhost
curl -s -m 5 -H 'Host: bf19.localhost' "$BF_INGRESS/" | grep -q 'Client Portal' || fail "bf19.localhost answers, but not with the portal (a catch-all route?)"
ok "bf19.localhost serves the portal"
