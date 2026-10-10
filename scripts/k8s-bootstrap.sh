#!/usr/bin/env bash
# Installs the cluster platform on the local k3d cluster: Argo CD (GitOps) and Kyverno (admission
# policies). Versions are pinned. Idempotent: re-running upgrades in place.
set -euo pipefail

ARGOCD_CHART_VERSION=10.10.2   # Argo CD v3.5.4
KYVERNO_CHART_VERSION=3.9.1    # Kyverno v1.19.1

kubectl config current-context | grep -q '^k3d-lab$' || { echo "Not on the k3d-lab context"; exit 1; }

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo add kyverno https://kyverno.github.io/kyverno >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "== Kyverno"
helm upgrade --install kyverno kyverno/kyverno --version "$KYVERNO_CHART_VERSION" \
  --namespace kyverno --create-namespace --wait --timeout 10m

echo "== Argo CD"
helm upgrade --install argocd argo/argo-cd --version "$ARGOCD_CHART_VERSION" \
  --namespace argocd --create-namespace --wait --timeout 10m \
  --set configs.params."server\.insecure"=true \
  --set dex.enabled=false --set notifications.enabled=false

echo "== Ready"
kubectl get pods -n kyverno -o wide --no-headers | awk '{print "kyverno/"$1, $3}'
kubectl get pods -n argocd --no-headers | awk '{print "argocd/"$1, $3}'
echo
echo "Argo CD admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo "Argo CD UI:             kubectl -n argocd port-forward svc/argocd-server 8090:80  ->  http://localhost:8090"
