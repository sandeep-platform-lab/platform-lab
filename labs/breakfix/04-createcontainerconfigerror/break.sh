source "$BF_DIR/../lib.sh"; mkns
k create secret generic db-credentials --from-literal=username=orders --from-literal=passwd=rotated-2026 \
  --dry-run=client -o yaml | apply
apply <<'Y'
apiVersion: apps/v1
kind: Deployment
metadata: { name: orders-api }
spec:
  replicas: 1
  selector: { matchLabels: { app: orders-api } }
  template:
    metadata: { labels: { app: orders-api } }
    spec:
      containers:
        - name: app
          image: busybox:1.37
          command: ["sh", "-c", "echo connecting as $DB_USER; sleep 3600"]
          env:
            - name: DB_USER
              valueFrom: { secretKeyRef: { name: db-credentials, key: username } }
            - name: DB_PASSWORD
              valueFrom: { secretKeyRef: { name: db-credentials, key: password } }
          resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { memory: 32Mi } }
Y
