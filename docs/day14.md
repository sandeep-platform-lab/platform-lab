# Day 14 – Troubleshooting dojo 1: pods, nodes and upgrades

**Goal:** diagnose the classic pod and node failures from evidence, out loud, without guessing; and be
able to run a node-pool upgrade that doesn't take an app down.

Time: about 4–5h. Cluster: local k3d (`k3d cluster start lab`). Field guide sections:
*Kubernetes troubleshooting*, *Upgrades, availability & scaling*.

```
ticket ─▶ impact ─▶ evidence (describe, events, logs --previous) ─▶ hypothesis ─▶ one change ─▶ check ─▶ prevention
```

| Piece | Where |
|---|---|
| Runner | `scripts/breakfix.sh` (list, break, hint, check, reset, random) |
| Scenarios | `labs/breakfix/NN-*/` (ticket, hint, break.sh, check.sh) |
| Answers | `labs/breakfix/SOLUTIONS.md`: open only after `check` passes, or after 20 minutes stuck |

Start the cluster. If `k3d cluster start lab` hangs on "waiting for log message", restart the server
container: `docker restart k3d-lab-server-0 && docker start k3d-lab-serverlb`.

---

## Part A – Warm-up on paper (about 20 min)

Without looking anything up, draw and explain in 2 minutes each:
1. What happens between `kubectl apply -f deployment.yaml` and a container running? (API server → etcd →
   Deployment controller → ReplicaSet → scheduler → kubelet → CRI → CNI → probes.)
2. The pod lifecycle states you'll see today: Pending, ContainerCreating, CreateContainerConfigError,
   ImagePullBackOff, Running-but-not-Ready, CrashLoopBackOff, OOMKilled, Terminating.

---

## Part B – Pod failures (about 2h)

For each one: `break`, read the ticket, set a 15-minute timer, solve it, `check`. Then say the
two-minute answer out loud (impact, evidence, root cause, fix, prevention), then `reset`.

```bash
cd ~/workspace
scripts/breakfix.sh break 01    # Pending: resources
scripts/breakfix.sh break 02    # Pending: taints + affinity
scripts/breakfix.sh break 03    # CrashLoopBackOff
scripts/breakfix.sh break 04    # CreateContainerConfigError
scripts/breakfix.sh break 05    # OOMKilled
scripts/breakfix.sh break 06    # rollout stuck: is there customer impact?
scripts/breakfix.sh break 12    # stuck Terminating
```

Questions to answer for yourself while you work:
1. 04 has no logs. Why, and where do you look instead?
2. 05: how do you tell "limit too small" from "memory leak"? Which metric, over what time range?
3. 06: was anyone affected? What protected users? What would you do differently in GitOps?
4. 12: what can go wrong with `kubectl delete pod --force --grace-period=0` on a StatefulSet pod?

---

## Part C – Nodes and maintenance (about 1h)

Run these **one at a time**, with no other scenarios active (`scripts/breakfix.sh reset all`).

```bash
scripts/breakfix.sh break 13    # drain blocked by a PodDisruptionBudget
scripts/breakfix.sh break 14    # node NotReady
```

For 14, start a watch in a second terminal *before* you fix anything and note the timeline:
```bash
kubectl get nodes -w
kubectl -n bf-14 get pods -o wide -w
```
How long until the node is NotReady (node-monitor grace period, about 40–50s)? When do the pods get evicted (`tolerationSeconds: 300`)? What
do Services do with those pods in between?

Then the cluster-wide check you'd run before every upgrade window:
```bash
# PDBs that would block a drain right now
kubectl get pdb -A -o json | jq -r '.items[] | select(.status.disruptionsAllowed==0) | "\(.metadata.namespace)/\(.metadata.name)"'
# Single-replica Deployments (they will have downtime during a drain, PDB or not)
kubectl get deploy -A -o json | jq -r '.items[] | select(.spec.replicas==1) | "\(.metadata.namespace)/\(.metadata.name)"'
# Deprecated APIs that clients still call
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis
```

---

## Part D – Upgrade runbook (about 45 min, on paper)

Write a one-page production AKS upgrade runbook, then compare with the field guide answer. Include:
- `az aks get-upgrades`, supported version skew, no control-plane downgrade
- order: control plane → system pool → user pools; node image upgrades vs Kubernetes version upgrades
- `--max-surge` (e.g. 33%) and its quota/IP cost (Azure CNI: each surge node needs IPs), `maxUnavailable`
- planned maintenance windows, auto-upgrade channels, `node-image` channel
- pre-checks from Part C, communication to app teams, validation and stop criteria
- OpenShift equivalent in one line each: update channel, `oc adm upgrade`, Cluster Version Operator,
  MachineConfigPools rolling nodes, `maxUnavailable` on the MCP

**Optional, real (about 1h, ~CHF 2):** with `terraform/azure`, create a 2-node AKS one minor version behind,
run `while true; do curl -s -o /dev/null -w '%{http_code}\n' http://<app>; sleep 0.5; done`, upgrade the
node pool with and without a PDB / 2 replicas, and count the non-200s. `terraform destroy` afterwards.

---

## Notes

_Your two-minute answers, written down in short form._
