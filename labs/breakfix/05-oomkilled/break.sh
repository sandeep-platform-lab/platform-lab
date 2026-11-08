source "$BF_DIR/../lib.sh"; mkns
apply <<'Y'
apiVersion: apps/v1
kind: Deployment
metadata: { name: cache-warmer }
spec:
  replicas: 1
  minReadySeconds: 10
  selector: { matchLabels: { app: cache-warmer } }
  template:
    metadata: { labels: { app: cache-warmer } }
    spec:
      containers:
        - name: app
          image: busybox:1.37
          # tail buffers the whole newline-free stream in memory: ~150 MB resident
          command: ["sh", "-c", "head -c 150m /dev/zero | tail > /dev/null; echo warmed; sleep 3600"]
          resources:
            requests: { cpu: 10m, memory: 64Mi }
            limits:   { memory: 64Mi }
Y
