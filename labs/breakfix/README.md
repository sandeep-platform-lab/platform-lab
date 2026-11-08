# Break-fix dojo

19 production-style faults for the local k3d cluster. Each one arrives as a "ticket" from an app team or
an alert. You diagnose with `kubectl`, fix it the way you would in production, and a check script tells
you whether the fix is real (for example, deleting the PDB or relaxing Pod Security doesn't count).

```bash
scripts/breakfix.sh list
scripts/breakfix.sh break 07     # inject the fault, print the ticket
scripts/breakfix.sh hint 07      # after 10 minutes, not before
scripts/breakfix.sh check 07
scripts/breakfix.sh reset 07     # or: reset all
scripts/breakfix.sh random       # mock-interview mode
```

| ID | Fault | Area | Interview topic |
|---|---|---|---|
| 01 | Pending: impossible CPU request | scheduling | requests vs allocatable |
| 02 | Pending: labelled + tainted pool, no toleration | scheduling | taints, affinity, dedicated pools |
| 03 | CrashLoopBackOff: ConfigMap key renamed | workloads | `logs --previous`, config projection |
| 04 | CreateContainerConfigError: wrong Secret key | workloads | why there are no logs |
| 05 | OOMKilled | workloads | cgroup limits, exit 137, leak vs undersized |
| 06 | Rollout stuck on a bad tag | releases | impact analysis, `rollout undo`, progress deadline |
| 07 | 503: readiness probe path wrong | networking | Running ≠ Ready, EndpointSlices |
| 08 | 502: Service targetPort wrong | networking | 502 vs 503 |
| 09 | 503: Service selector mismatch | networking | labels, empty endpoints |
| 10 | Default-deny egress breaks DNS | security | NetworkPolicy, CoreDNS |
| 11 | PVC Pending: StorageClass from AKS | storage | CSI, immutable fields, StatefulSets |
| 12 | Pod stuck Terminating | workloads | finalizers, safe force-delete |
| 13 | Drain blocked by PDB | upgrades | node upgrades, PDB design |
| 14 | Node NotReady | nodes | node lifecycle, taints, eviction timing |
| 15 | Pod Security restricted: no pods at all | security | PSA ≈ OpenShift SCC |
| 16 | CI service account forbidden | security | least-privilege RBAC |
| 17 | ResourceQuota blocks a scale-up | capacity | quota counts requests, rollout deadlock |
| 18 | Kyverno denies a deployment | policy | policy-as-code, audit → enforce |
| 19 | Ingress class nobody serves | networking | IngressClass, catch-all routes, ingress-nginx retirement |

Each scenario runs in its own namespace `bf-<id>`. Run **13** and **14** on their own: they drain and stop
nodes. 02 taints `k3d-lab-agent-1` until you reset it.

Answers with tested commands: [SOLUTIONS.md](SOLUTIONS.md). Use the method from the field guide while you
work, and say it out loud: **Impact → Evidence → Hypothesis → Validation → Recovery → Prevention**.

## Your first five commands for any ticket

```bash
kubectl -n NS get all,events --sort-by=.lastTimestamp | tail -20
kubectl -n NS describe pod POD | sed -n '/State/,/Ready/p;/Events/,$p'
kubectl -n NS logs POD --previous --tail=50
kubectl -n NS get endpointslices,ingress,networkpolicy,resourcequota,pdb
kubectl get nodes -o wide; kubectl describe node NODE | sed -n '/Conditions/,/Allocated/p'
```
