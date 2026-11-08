# Day 17 – OpenShift hands-on and writing an Operator

**Goal:** use `oc` on a real OpenShift cluster (projects, Routes, SCCs, builds); build and run a small
Operator in Go so you can explain reconciliation from your own code, not from slides.

Time: about 3h.

---

## Part A – OpenShift (about 1.5h)

**Cluster options** (pick one; both need a free Red Hat account, which you create yourself):
- **Developer Sandbox** (fastest): https://developers.redhat.com/developer-sandbox: a shared OpenShift
  cluster in the browser, no install. You get a couple of projects but no cluster-admin.
- **OpenShift Local** (`crc`, about 1h setup; Apple Silicon supported, needs ~11 GB RAM, ~35 GB disk):
  https://developers.redhat.com/products/openshift-local. You get `kubeadmin`, so you can also look at
  ClusterOperators, ClusterVersion, MachineConfigPools.

Log in: web console → your name → **Copy login command** → `oc login --token=... --server=...`
(`brew install openshift-cli` if `oc` is missing.)

**1. Projects, S2I, Routes**
```bash
oc project                                   # your sandbox project, e.g. <user>-dev
oc new-app nodejs~https://github.com/sclorg/nodejs-ex --name=hello    # Source-to-Image build
oc logs -f bc/hello                          # BuildConfig -> Build -> image in an ImageStream
oc get is,bc,build,deploy,svc
oc expose svc/hello                          # Route (HAProxy router), plain HTTP
oc create route edge hello-tls --service=hello   # TLS terminated at the router
oc get route; curl -s https://$(oc get route hello-tls -o jsonpath='{.spec.host}') | head -5
```
Know the three TLS modes: **edge**, **passthrough**, **re-encrypt**, and when you'd pick each.

**2. SCC: the same lesson as break-fix 15**
```bash
oc create deployment rootnginx --image=docker.io/library/nginx:1.29-alpine
oc get pods; oc logs deploy/rootnginx         # permission errors: nginx wants root and port 80
oc get pod -l app=rootnginx -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}'; echo   # restricted-v2
oc get pod -l app=rootnginx -o jsonpath='{.items[0].spec.containers[0].securityContext}'; echo      # random UID injected
oc get project $(oc project -q) -o yaml | grep sa.scc     # the UID range this project assigns
oc set image deploy/rootnginx nginx=docker.io/nginxinc/nginx-unprivileged:1.29-alpine   # fix the workload, not the SCC
oc auth can-i use scc/privileged              # no, and that's the point
```
Interview line: "Fix the image (arbitrary UID, group 0, port > 1024), don't grant `anyuid`. If a vendor
image truly needs it, a dedicated service account with the narrowest SCC, documented as an exception."

**3. Admin views** (OpenShift Local / any cluster where you're admin; otherwise know the commands):
```bash
oc get clusteroperators              # every component is an Operator; look for DEGRADED=True
oc get clusterversion; oc adm upgrade   # channel, available updates (Cluster Version Operator)
oc get mcp; oc get machineconfig | head   # Machine Config Operator: node OS config, rolls nodes one by one
oc get machinesets -n openshift-machine-api   # IPI clouds: nodes as API objects, MachineHealthCheck
oc adm top nodes; oc adm must-gather    # what support asks for first
```

---

## Part B – Build the TeamSpace operator (about 1.5h)

Go 1.27 and kubebuilder 4.16 are installed. Work outside the repo, in `~/teamspace-operator`:

```bash
mkdir -p ~/teamspace-operator && cd ~/teamspace-operator
kubebuilder init --domain example.com --repo example.com/teamspace-operator
kubebuilder create api --group platform --version v1alpha1 --kind TeamSpace --namespaced=false --resource --controller
```

1. **API** (`api/v1alpha1/teamspace_types.go`): add `CPU`, `Memory` (`resource.Quantity`), `AdminGroup`
   (string) to the spec, and `Namespace` to the status (the scaffold already has `Conditions`). Add a
   print column for Ready.
2. **Controller** (`internal/controller/teamspace_controller.go`): in `Reconcile`, get the TeamSpace (ignore
   NotFound), then `controllerutil.CreateOrUpdate` a Namespace (`team-<name>`, label
   `pod-security.kubernetes.io/enforce=restricted`), a ResourceQuota and a RoleBinding to ClusterRole
   `admin`, each with `SetControllerReference`. Set a `Ready` condition and update status. In
   `SetupWithManager` add `Owns(&corev1.ResourceQuota{})` etc. Add RBAC markers for what you touch.
3. Run it against k3d:
   ```bash
   make manifests generate && make install          # CRD into the cluster
   make run                                          # controller runs on your Mac, uses your kubeconfig
   # second terminal:
   kubectl apply -f config/samples/platform_v1alpha1_teamspace.yaml
   kubectl get ts; kubectl -n team-payments get quota,rolebinding
   ```
4. Prove the loop:
   - `kubectl -n team-payments delete resourcequota team-quota` → back within a second. Why? (`Owns()`)
   - `kubectl patch ts payments --type=merge -p '{"spec":{"cpu":"3"}}'` → quota changes.
   - `kubectl delete ts payments` → namespace deleted by the garbage collector. Good or dangerous?
   - Stop `make run`, delete the quota, start it again: the quota comes back. Level-triggered, not
     edge-triggered.
5. Stuck? Compare with `labs/operator/reference/` (tested). Clean up: `make uninstall`.

Questions to answer out loud: Why must Reconcile be idempotent? What's a finalizer for, and when would
TeamSpace need one (external resources like an Entra group or a Vault path)? What does leader election
protect against when you run 2 replicas? Status update conflict: what happens and why it's fine? How would
you test it (envtest is already scaffolded in `suite_test.go`)? Operator vs Ansible playbook vs GitOps for
this same request?

---

## Notes
