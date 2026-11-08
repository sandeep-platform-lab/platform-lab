source "$BF_DIR/../lib.sh"; mkns
apply <<'Y'
apiVersion: apps/v1
kind: Deployment
metadata: { name: quotes }
spec:
  replicas: 2
  selector: { matchLabels: { app: quotes } }
  template:
    metadata: { labels: { app: quotes } }
    spec:
      topologySpreadConstraints:
        - { maxSkew: 1, topologyKey: kubernetes.io/hostname, whenUnsatisfiable: ScheduleAnyway,
            labelSelector: { matchLabels: { app: quotes } } }
      containers:
        - name: web
          image: nginx:1.29-alpine
          resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { memory: 64Mi } }
Y
k rollout status deploy/quotes --timeout=120s >/dev/null
docker stop k3d-lab-agent-0 >/dev/null
echo "(started at $(date +%H:%M:%S): watch with kubectl get nodes -w)"
