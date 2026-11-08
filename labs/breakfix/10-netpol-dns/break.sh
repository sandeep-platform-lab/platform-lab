source "$BF_DIR/../lib.sh"; mkns
apply <<'Y'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny-all }
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: backend-allow-from-frontend }
spec:
  podSelector: { matchLabels: { app: backend } }
  policyTypes: [Ingress]
  ingress:
    - from: [{ podSelector: { matchLabels: { app: frontend } } }]
      ports: [{ protocol: TCP, port: 80 }]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: frontend-allow-to-backend }
spec:
  podSelector: { matchLabels: { app: frontend } }
  policyTypes: [Egress]
  egress:
    - to: [{ podSelector: { matchLabels: { app: backend } } }]
      ports: [{ protocol: TCP, port: 80 }]
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: backend }
spec:
  replicas: 1
  selector: { matchLabels: { app: backend } }
  template:
    metadata: { labels: { app: backend } }
    spec:
      containers:
        - name: web
          image: nginx:1.29-alpine
          resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { memory: 64Mi } }
---
apiVersion: v1
kind: Service
metadata: { name: backend }
spec:
  selector: { app: backend }
  ports: [{ port: 80, targetPort: 80 }]
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: frontend }
spec:
  replicas: 1
  selector: { matchLabels: { app: frontend } }
  template:
    metadata: { labels: { app: frontend } }
    spec:
      containers:
        - name: client
          image: busybox:1.37
          command: ["sh", "-c", "while true; do wget -qO- -T2 http://backend >/dev/null && echo OK || echo FAIL; sleep 5; done"]
          resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { memory: 32Mi } }
Y
