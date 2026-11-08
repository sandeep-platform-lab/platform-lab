source "$BF_DIR/../lib.sh"; mkns
kubectl label ns "$BF_NS" pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=latest --overwrite >/dev/null
apply 2>/dev/null <<'Y'
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: web
          image: nginx:1.29-alpine
          resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { memory: 64Mi } }
Y
