source "$BF_DIR/../lib.sh"; mkns
apply <<'Y'
apiVersion: apps/v1
kind: Deployment
metadata: { name: inventory }
spec:
  replicas: 2
  selector: { matchLabels: { app: inventory } }
  template:
    metadata: { labels: { app: inventory } }
    spec:
      containers:
        - name: web
          image: nginx:1.29-alpine
          ports: [{ name: http, containerPort: 80 }]
          readinessProbe: { httpGet: { path: /, port: 80 }, periodSeconds: 5 }
          resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { memory: 64Mi } }
---
apiVersion: v1
kind: Service
metadata: { name: inventory }
spec:
  selector: { app: inventory-api }
  ports: [{ name: http, port: 80, targetPort: 80 }]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: inventory }
spec:
  ingressClassName: traefik
  rules:
    - host: bf09.localhost
      http:
        paths:
          - { path: /, pathType: Prefix, backend: { service: { name: inventory, port: { number: 80 } } } }
Y
