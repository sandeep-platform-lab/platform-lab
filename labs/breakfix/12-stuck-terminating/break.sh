source "$BF_DIR/../lib.sh"; mkns
apply <<'Y'
apiVersion: v1
kind: Pod
metadata:
  name: batch-runner
  finalizers: [batch.example.com/upload-results]   # its controller was uninstalled last week
spec:
  terminationGracePeriodSeconds: 5
  containers:
    - name: job
      image: busybox:1.37
      command: ["sh", "-c", "echo processing; sleep 3600"]
      resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { memory: 32Mi } }
Y
k wait --for=condition=Ready pod/batch-runner --timeout=90s >/dev/null
k delete pod batch-runner --wait=false >/dev/null
