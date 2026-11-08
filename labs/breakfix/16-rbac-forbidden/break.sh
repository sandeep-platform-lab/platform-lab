source "$BF_DIR/../lib.sh"; mkns
apply <<'Y'
apiVersion: v1
kind: ServiceAccount
metadata: { name: ci-deployer }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: ci-deployer }
rules:
  - apiGroups: [""]
    resources: [pods]
    verbs: [get, list]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: ci-deployer }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: Role, name: ci-deployer }
subjects: [{ kind: ServiceAccount, name: ci-deployer }]
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: api }
spec:
  replicas: 1
  selector: { matchLabels: { app: api } }
  template:
    metadata: { labels: { app: api } }
    spec:
      containers:
        - name: api
          image: nginx:1.28-alpine
          resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { memory: 64Mi } }
Y
