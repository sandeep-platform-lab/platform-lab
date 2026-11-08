source "$BF_DIR/../lib.sh"; mkns
apply <<'Y'
apiVersion: v1
kind: ConfigMap
metadata: { name: payments-config }
data:
  application.conf: |        # renamed during "cleanup"; the app reads app.conf
    currency=CHF
    settlement=T+2
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: payments-api }
spec:
  replicas: 1
  minReadySeconds: 10
  selector: { matchLabels: { app: payments-api } }
  template:
    metadata: { labels: { app: payments-api } }
    spec:
      containers:
        - name: app
          image: busybox:1.37
          command: ["sh", "-c", "test -f /etc/app/app.conf || { echo 'FATAL: /etc/app/app.conf not found' >&2; exit 1; }; echo started; cat /etc/app/app.conf; sleep 3600"]
          volumeMounts: [{ name: config, mountPath: /etc/app }]
          resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { memory: 32Mi } }
      volumes:
        - name: config
          configMap: { name: payments-config }
Y
