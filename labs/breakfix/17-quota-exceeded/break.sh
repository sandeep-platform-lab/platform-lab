source "$BF_DIR/../lib.sh"; mkns
apply <<'Y'
apiVersion: v1
kind: ResourceQuota
metadata: { name: team-quota }
spec:
  hard: { requests.cpu: 500m, requests.memory: 512Mi, limits.cpu: "2", limits.memory: 1Gi, pods: "10" }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: worker }
spec:
  replicas: 3
  selector: { matchLabels: { app: worker } }
  template:
    metadata: { labels: { app: worker } }
    spec:
      containers:
        - name: worker
          image: busybox:1.37
          command: ["sh", "-c", "echo settling; sleep 3600"]
          resources:
            requests: { cpu: 250m, memory: 128Mi }
            limits:   { cpu: 500m, memory: 256Mi }
Y
