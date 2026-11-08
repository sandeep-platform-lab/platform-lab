source "$BF_DIR/../lib.sh"; mkns
apply <<'Y'
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: ledger-db }
spec:
  serviceName: ledger-db
  replicas: 1
  selector: { matchLabels: { app: ledger-db } }
  template:
    metadata: { labels: { app: ledger-db } }
    spec:
      containers:
        - name: db
          image: busybox:1.37
          command: ["sh", "-c", "date >> /data/started; cat /data/started; sleep 3600"]
          volumeMounts: [{ name: data, mountPath: /data }]
          resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { memory: 32Mi } }
  volumeClaimTemplates:
    - metadata: { name: data }
      spec:
        storageClassName: managed-csi     # AKS default class
        accessModes: [ReadWriteOnce]
        resources: { requests: { storage: 1Gi } }
Y
