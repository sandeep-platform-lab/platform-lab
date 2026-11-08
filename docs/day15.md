# Day 15 – Troubleshooting dojo 2: connectivity, security, policy, storage

**Goal:** trace a request hop by hop and name the failing layer from the status code and the evidence; fix
security problems without weakening the control; roll out policy without breaking teams.

Time: about 4–5h. Field guide sections: *Networking & ingress*, *Security, Kyverno & Azure Policy*,
*Storage & recovery*.

```
client ─▶ DNS ─▶ LB ─▶ ingress controller (rule, class) ─▶ Service (selector, targetPort) ─▶ EndpointSlice (ready?) ─▶ pod ─▶ NetworkPolicy ─▶ app
   404 = no rule matched        503 = no ready backend        502 = backend reached but answered badly        timeout = network/policy
```

---

## Part A – Connectivity (about 1.5h)

```bash
scripts/breakfix.sh break 07    # 503
scripts/breakfix.sh break 08    # 502
scripts/breakfix.sh break 09    # 503, different cause
scripts/breakfix.sh break 19    # wrong app answers
scripts/breakfix.sh break 10    # default-deny vs DNS
```

Before you fix 07/08/09, write down your guess from the status code alone, then prove it. For 10, prove
the DNS theory first (test by pod IP) before you write a policy.

Extra checks to practise (no scenario needed):
```bash
kubectl run -it --rm dbg --image=busybox:1.37 --restart=Never -- sh
  nslookup kubernetes.default.svc.cluster.local
  cat /etc/resolv.conf          # ndots:5: why does "api.example.com" cause 5 lookups first?
  wget -qO- -T2 http://shop.bf-07.svc.cluster.local
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=20
```

---

## Part B – Security (about 1.5h)

```bash
scripts/breakfix.sh break 15    # Pod Security restricted (≈ OpenShift restricted-v2 SCC)
scripts/breakfix.sh break 16    # RBAC for a CI service account
scripts/breakfix.sh break 17    # ResourceQuota (two traps)
scripts/breakfix.sh break 18    # Kyverno denial
```

1. 15: what exactly does "restricted" require? Write the securityContext from memory.
2. 16: build the Role from the error message alone, then prove least privilege with `auth can-i --list`.
3. 18: after fixing it, copy the policy, set one rule to `Audit`, apply a bad Deployment and read
   `kubectl -n bf-18 get policyreport -o wide`. That's how you roll a policy out without breaking teams.

---

## Part C – Built-in admission policy vs Kyverno (about 40 min)

Kubernetes has its own CEL policy engine (ValidatingAdmissionPolicy, GA in 1.30). Kyverno 1.19 is moving
the same way: it prints `kyverno.io/v1 ClusterPolicy is deprecated … migrate to ValidatingPolicy`.

```bash
kubectl apply -f labs/policy/validating-admission-policy.yaml
kubectl create ns policy-lab && kubectl label ns policy-lab policy-lab=true
kubectl -n policy-lab create deploy bad --image=nginx:latest          # Warn: created, with warnings
kubectl patch validatingadmissionpolicybinding workload-standards --type=merge -p '{"spec":{"validationActions":["Deny"]}}'
kubectl -n policy-lab create deploy bad2 --image=nginx:latest         # Deny: rejected
kubectl get validatingadmissionpolicy workload-standards -o jsonpath='{.status.typeChecking}'; echo
kubectl delete ns policy-lab; kubectl delete -f labs/policy/validating-admission-policy.yaml
```
Note: the policy can take a few seconds to become active after `apply`.

Be ready to compare in two minutes: **VAP** (in the API server, no webhook to fail, CEL, validate only;
MutatingAdmissionPolicy is newer) vs **Kyverno** (validate + mutate + generate + image verification,
PolicyReports, exceptions) vs **Gatekeeper/Azure Policy** (Rego constraints; on AKS the Azure Policy add-on
runs Gatekeeper and reports compliance to Azure). And: what happens when a webhook is down
(`failurePolicy: Fail` vs `Ignore`)?

---

## Part D – Storage (about 45 min)

```bash
scripts/breakfix.sh break 11    # PVC Pending
```
After fixing it, explore StatefulSet behaviour:
```bash
kubectl -n bf-11 delete pod ledger-db-0        # comes back with the same name and the same PVC
kubectl -n bf-11 exec ledger-db-0 -- cat /data/started   # two start times: data survived
kubectl -n bf-11 scale sts ledger-db --replicas=0; kubectl -n bf-11 get pvc   # PVC is kept
kubectl get pv -o wide                         # local-path: the PV is tied to one node
```
Questions: what does `WaitForFirstConsumer` solve in multi-zone AKS? What happens to an RWO Azure Disk when
its node dies (attach/detach, 6-minute force-detach)? RWX options on AKS (Azure Files) and OpenShift (ODF)?

---

## Notes
