source "$BF_DIR/../lib.sh"; mkns
kubectl label node k3d-lab-agent-1 node.example.com/pool=edge --overwrite >/dev/null
kubectl taint node k3d-lab-agent-1 dedicated=edge:NoSchedule --overwrite >/dev/null
apply <<'Y'
apiVersion: apps/v1
kind: Deployment
metadata: { name: edge-proxy }
spec:
  replicas: 1
  selector: { matchLabels: { app: edge-proxy } }
  template:
    metadata: { labels: { app: edge-proxy } }
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - { key: node.example.com/pool, operator: In, values: [edge] }
      containers:
        - name: proxy
          image: nginx:1.29-alpine
          resources: { requests: { cpu: 50m, memory: 32Mi }, limits: { memory: 64Mi } }
Y
