source "$BF_DIR/../lib.sh"
kubectl -n kyverno get deploy -l app.kubernetes.io/component=admission-controller >/dev/null 2>&1 \
  || { echo "Kyverno not installed: run scripts/k8s-bootstrap.sh first"; exit 1; }
mkns
kubectl apply -f - >/dev/null <<'Y'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: bf18-workload-standards
  annotations:
    policies.kyverno.io/title: Workload standards for bf-18 (team label, limits, no latest tag)
spec:
  background: true
  rules:
    - name: require-team-label
      match: { any: [{ resources: { kinds: [Pod], namespaces: [bf-18] } }] }
      validate:
        failureAction: Enforce
        message: "Pods need a 'team' label for cost allocation and on-call routing."
        pattern: { metadata: { labels: { team: "?*" } } }
    - name: require-memory-limit
      match: { any: [{ resources: { kinds: [Pod], namespaces: [bf-18] } }] }
      validate:
        failureAction: Enforce
        message: "Every container needs resources.requests.cpu, requests.memory and limits.memory."
        pattern:
          spec:
            containers:
              - resources: { requests: { cpu: "?*", memory: "?*" }, limits: { memory: "?*" } }
    - name: disallow-latest-tag
      match: { any: [{ resources: { kinds: [Pod], namespaces: [bf-18] } }] }
      validate:
        failureAction: Enforce
        message: "Use a pinned image tag, not ':latest' or no tag."
        pattern: { spec: { containers: [{ image: "*:* & !*:latest" }] } }
Y
kubectl wait --for=condition=Ready clusterpolicy/bf18-workload-standards --timeout=60s >/dev/null
# The team's manifest, written to /tmp so you can edit it (kept out of the repo: it fails the Trivy gate).
cat > /tmp/bf18.yaml <<'M'
apiVersion: apps/v1
kind: Deployment
metadata: { name: reporting, namespace: bf-18 }
spec:
  replicas: 1
  selector: { matchLabels: { app: reporting } }
  template:
    metadata: { labels: { app: reporting } }
    spec:
      containers:
        - name: reporting
          image: nginx:latest
M
echo "Trying the team's manifest (/tmp/bf18.yaml):"; kubectl apply -f /tmp/bf18.yaml 2>&1 | sed 's/^/  /' || true
