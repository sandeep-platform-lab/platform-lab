#!/usr/bin/env bash
# Deploys lab-api to the AKS lab cluster with workload identity + Key Vault CSI, then proves the
# pod can read the Key Vault secret. Values come from terraform/azure outputs.
# Usage: scripts/aks-deploy.sh [image tag]   (default: newTag in k8s/apps/lab-api/kustomization.yaml)
set -euo pipefail
cd "$(dirname "$0")/.."

set -a; source ./.env; set +a
TF="terraform -chdir=terraform/azure"
export REGISTRY=${JFROG_URL#https://}
export TAG=${1:-$(yq '.images[0].newTag' k8s/apps/lab-api/kustomization.yaml)}
export LAB_API_CLIENT_ID=$($TF output -raw lab_api_client_id)
export KEY_VAULT_NAME=$($TF output -raw key_vault_name)
export TENANT_ID=$($TF output -raw tenant_id)
CLUSTER=$($TF output -raw cluster_name)

ctx=$(kubectl config current-context)
[ "$ctx" = "$CLUSTER" ] || { echo "kubectl context is '$ctx', expected '$CLUSTER'. Run: $($TF output -raw kubeconfig_command)"; exit 1; }

echo "== Deploying lab-api:$TAG to $CLUSTER"
envsubst '${LAB_API_CLIENT_ID} ${KEY_VAULT_NAME} ${TENANT_ID} ${REGISTRY} ${TAG}' \
  < k8s/azure/lab-api.yaml.tmpl > /tmp/lab-api-aks.yaml
# The namespace must exist before a server-side dry run can check the objects inside it.
yq 'select(.kind == "Namespace")' /tmp/lab-api-aks.yaml | kubectl apply -f -
kubectl apply -f /tmp/lab-api-aks.yaml --dry-run=server >/dev/null   # fail early, before changing anything
# Pull secret for JFrog: read-only developer token, 7 days, never in git.
TOKEN=$(jf atc --groups lab-developers --expiry 604800 | jq -r .access_token)
kubectl -n lab create secret docker-registry jfrog-pull --docker-server="$REGISTRY" \
  --docker-username="$JFROG_USER" --docker-password="$TOKEN" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
unset TOKEN
kubectl apply -f /tmp/lab-api-aks.yaml >/dev/null
rm -f /tmp/lab-api-aks.yaml
kubectl -n lab rollout status deployment/lab-api --timeout=5m

echo
echo "== Secret read through workload identity (no secret in the cluster's config):"
kubectl -n lab exec deploy/lab-api -- cat /mnt/secrets/lab-api-greeting; echo
echo
echo "== Injected by the workload identity webhook:"
kubectl -n lab get pod -l app=lab-api -o jsonpath='{.items[0].spec.containers[0].env[*].name}' | tr ' ' '\n' | grep AZURE_
echo
echo "Try the app:  kubectl -n lab port-forward svc/lab-api 8085:80   then   curl -s localhost:8085/api/info"
