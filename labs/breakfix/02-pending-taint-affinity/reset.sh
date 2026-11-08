kubectl taint node k3d-lab-agent-1 dedicated- >/dev/null 2>&1 || true
kubectl label node k3d-lab-agent-1 node.example.com/pool- >/dev/null 2>&1 || true
