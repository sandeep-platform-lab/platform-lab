source "$BF_DIR/../lib.sh"; mkns
apply <<'Y'
apiVersion: apps/v1
kind: Deployment
metadata: { name: report-generator, labels: { app: report-generator } }
spec:
  replicas: 1
  selector: { matchLabels: { app: report-generator } }
  template:
    metadata: { labels: { app: report-generator } }
    spec:
      containers:
        - name: app
          image: busybox:1.37
          command: ["sh", "-c", "echo generating reports; sleep 3600"]
          resources:
            requests: { cpu: "100", memory: 64Mi }   # someone meant 100m
            limits:   { memory: 128Mi }
Y
