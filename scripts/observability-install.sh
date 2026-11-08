#!/usr/bin/env bash
# Installs kube-prometheus-stack (Prometheus, Alertmanager, Grafana, kube-state-metrics, node-exporter)
# on the local k3d cluster, plus the lab's own alert rules. Version pinned; re-run to upgrade in place.
set -euo pipefail
KPS_CHART_VERSION=92.21.2   # operator v0.94.2
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

kubectl config current-context | grep -q '^k3d-lab$' || { echo "Not on the k3d-lab context"; exit 1; }
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community >/dev/null

helm upgrade --install kps prometheus-community/kube-prometheus-stack --version "$KPS_CHART_VERSION" \
  --namespace monitoring --create-namespace --wait --timeout 10m \
  -f "$ROOT/labs/observability/values-k3d.yaml"
kubectl apply -f "$ROOT/labs/observability/platform-alerts.yaml"

echo
echo "Prometheus:   http://prometheus.localhost:8080"
echo "Alertmanager: http://alertmanager.localhost:8080"
echo "Grafana:      http://grafana.localhost:8080   (admin / admin)"
echo "Remove:       helm -n monitoring uninstall kps && kubectl delete ns monitoring"
