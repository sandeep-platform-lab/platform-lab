source "$BF_DIR/../lib.sh"; mkns
apply <<'Y'
apiVersion: apps/v1
kind: Deployment
metadata: { name: matching-engine }
spec:
  replicas: 2
  selector: { matchLabels: { app: matching-engine } }
  template:
    metadata: { labels: { app: matching-engine } }
    spec:
      affinity:   # keep it on worker nodes
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms: [{ matchExpressions: [{ key: node-role.kubernetes.io/control-plane, operator: DoesNotExist }] }]
      topologySpreadConstraints:
        - { maxSkew: 1, topologyKey: kubernetes.io/hostname, whenUnsatisfiable: ScheduleAnyway,
            labelSelector: { matchLabels: { app: matching-engine } } }
      containers:
        - name: engine
          image: nginx:1.29-alpine
          readinessProbe: { httpGet: { path: /, port: 80 } }
          resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { memory: 64Mi } }
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: matching-engine }
spec:
  minAvailable: 2
  selector: { matchLabels: { app: matching-engine } }
Y
k rollout status deploy/matching-engine --timeout=120s >/dev/null
node=$(k get pod -l app=matching-engine -o jsonpath='{.items[0].spec.nodeName}')
kubectl annotate ns "$BF_NS" breakfix/drain-node="$node" --overwrite >/dev/null
echo "Node to drain: $node"
