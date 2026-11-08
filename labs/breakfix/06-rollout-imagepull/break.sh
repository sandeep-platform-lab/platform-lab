source "$BF_DIR/../lib.sh"; mkns
apply <<'Y'
apiVersion: apps/v1
kind: Deployment
metadata: { name: catalog }
spec:
  replicas: 3
  progressDeadlineSeconds: 60
  strategy: { type: RollingUpdate, rollingUpdate: { maxSurge: 1, maxUnavailable: 0 } }
  selector: { matchLabels: { app: catalog } }
  template:
    metadata: { labels: { app: catalog } }
    spec:
      containers:
        - name: web
          image: nginx:1.29-alpine
          readinessProbe: { httpGet: { path: /, port: 80 } }
          resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { memory: 64Mi } }
Y
k rollout status deploy/catalog --timeout=120s >/dev/null
k annotate deploy/catalog kubernetes.io/change-cause="v1 nginx:1.29-alpine" --overwrite >/dev/null
k set image deploy/catalog web=nginx:1.299-alpine >/dev/null
k annotate deploy/catalog kubernetes.io/change-cause="v2 pipeline release" --overwrite >/dev/null
