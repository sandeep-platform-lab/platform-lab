source "$BF_DIR/../lib.sh"; mkns
apply <<'Y'
apiVersion: apps/v1
kind: Deployment
metadata: { name: portal }
spec:
  replicas: 2
  selector: { matchLabels: { app: portal } }
  template:
    metadata: { labels: { app: portal } }
    spec:
      containers:
        - name: web
          image: nginx:1.29-alpine
          ports: [{ name: http, containerPort: 80 }]
          readinessProbe: { httpGet: { path: /, port: 80 }, periodSeconds: 5 }
          resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { memory: 64Mi } }
          volumeMounts: [{ name: html, mountPath: /usr/share/nginx/html }]
      volumes:
        - name: html
          configMap: { name: portal-html }
---
apiVersion: v1
kind: ConfigMap
metadata: { name: portal-html }
data:
  index.html: "<h1>Client Portal</h1>"
---
apiVersion: v1
kind: Service
metadata: { name: portal }
spec:
  selector: { app: portal }
  ports: [{ name: http, port: 80, targetPort: 80 }]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: portal }
spec:
  ingressClassName: webapprouting.kubernetes.azure.com
  rules:
    - host: bf19.localhost
      http:
        paths:
          - { path: /, pathType: Prefix, backend: { service: { name: portal, port: { number: 80 } } } }
Y
