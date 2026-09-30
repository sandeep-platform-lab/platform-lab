# Day 1 – Tooling and local Kubernetes

## Steps

1. Install Docker Desktop (needs your Mac password):
   `brew install --cask docker-desktop`, then open Docker Desktop and finish its first-run setup.
   Settings → Resources: give it **8 CPUs / 16 GB RAM**.
2. `./scripts/check-prereqs.sh` – everything should be ✅.
3. `k3d cluster create --config k8s/k3d/lab-cluster.yaml`
4. Explore:
   - `kubectl get nodes -o wide` – 3 nodes
   - `docker ps` – each node is a container
   - `kubectl get pods -A` – what k3s runs by default (CoreDNS, Traefik, local-path storage)
5. Sign-ups (browser):
   - Azure free account
   - GitHub: a free organisation for the lab (e.g. `<you>-platform-lab`)
6. Logins (these open your browser):
   - `gh auth login`
   - `az login`

## Understand (interview notes)

- **k3s vs full Kubernetes:** same API, single binary, SQLite instead of etcd by default, bundled Traefik and local-path storage.
- **k3d vs kind vs Docker Desktop Kubernetes:** all run Kubernetes nodes as containers. k3d is fast, supports many named clusters and a built-in registry.
- **Where does AKS differ?** Managed control plane, Azure CNI, managed identities, node pools on VM scale sets.

## Notes

_Write what surprised you here._
