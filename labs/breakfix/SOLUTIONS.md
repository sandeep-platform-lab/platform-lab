# Break-fix solutions (spoilers)

Try each scenario for at least 10 minutes and use `hint` first. For every scenario, finish by saying
out loud, in under 2 minutes: **impact → evidence → root cause → fix → prevention**.

All fixes below were tested on the k3d `lab` cluster (k3s v1.36, Traefik, local-path, Kyverno 1.19).

---

## 01 · Pending: impossible CPU request
- **Evidence:** `FailedScheduling: 0/3 nodes are available: 3 Insufficient cpu.`
- **Root cause:** `requests.cpu: "100"` (100 cores) instead of `100m`.
- **Fix:** `kubectl -n bf-01 set resources deploy report-generator --requests=cpu=100m`
- **Prevention:** LimitRange max per container, a policy that rejects absurd requests, a review checklist.
- **Say:** "Pending is a scheduler decision, so I read the scheduler's reason first instead of guessing."

## 02 · Pending: label without toleration
- **Evidence:** `1 node(s) had untolerated taint(s), 2 node(s) didn't match Pod's node affinity/selector`.
- **Root cause:** the edge pool is labelled *and* tainted; the pod asks for the label (affinity) but doesn't tolerate the taint.
- **Fix:** add `tolerations: [{key: dedicated, operator: Equal, value: edge, effect: NoSchedule}]`.
- **Not a fix:** removing the taint (every workload can now land in the DMZ) or the affinity.
- **Say:** "Taints keep others *out*, affinity pulls me *in*. Dedicated pools need both."
- **AKS/OpenShift:** AKS node pool `--node-taints`/labels; OpenShift MachineSet labels + taints for infra nodes.

## 03 · CrashLoopBackOff: config key renamed
- **Evidence:** `kubectl logs --previous` → `FATAL: /etc/app/app.conf not found`.
- **Root cause:** ConfigMap key renamed to `application.conf`; the volume projects keys as file names.
- **Fix:** rename the key back, or project it: `configMap: {name: payments-config, items: [{key: application.conf, path: app.conf}]}`.
- **Prevention:** config in the same Helm chart/Kustomize as the app, hash annotation to roll on change, a start-up config check in CI.

## 04 · CreateContainerConfigError: wrong Secret key
- **Evidence:** status `CreateContainerConfigError`; event `couldn't find key password in Secret bf-04/db-credentials`. No logs because the container never started.
- **Fix:** point `secretKeyRef.key` at `passwd` (or fix the Secret). Then the pod starts.
- **Prevention:** External Secrets / CSI driver with a fixed contract, rotation runbook that checks consumers.

## 05 · OOMKilled
- **Evidence:** `lastState.terminated.reason: OOMKilled`, exit code 137; limit 64Mi vs ~150 MB working set.
- **Fix:** `kubectl -n bf-05 set resources deploy cache-warmer --requests=memory=192Mi --limits=memory=256Mi`.
- **Say:** the kernel OOM killer acts on the cgroup limit; the app gets no chance to log. Separate "limit too
  small" (stable usage above limit) from "leak" (usage grows over time: look at the metric trend).
- **Prevention:** VPA in recommendation mode, memory alerts at 80–90 % of limit, load tests.

## 06 · Rollout stuck on ImagePullBackOff
- **Impact first:** none for users. `maxUnavailable: 0`, so the 3 old pods keep serving; 1 surge pod fails to pull.
- **Evidence:** condition `Progressing=False, reason ProgressDeadlineExceeded`; pod `ErrImagePull … nginx:1.299-alpine not found`.
- **Fix:** `kubectl -n bf-06 rollout undo deploy/catalog` (or set the correct tag), then `rollout status`.
- **Say:** "In GitOps I'd revert the commit instead; a manual undo is drift Argo CD will overwrite."
- **Prevention:** image existence/signature check in CI before deploy, `progressDeadlineSeconds`, pipeline auto-rollback.

## 07 · 503: readiness probe on a missing path
- **Evidence:** pods Running 0/1; EndpointSlice has no ready endpoints; probe gets 404 on `/healthz`.
- **Fix:** probe `/` (or add a real `/healthz` to the app).
- **Say:** "503 at the ingress usually means *no ready backend*. Running ≠ Ready."

## 08 · 502: Service targetPort wrong
- **Evidence:** pods Ready, endpoints exist but on port 8080; the container listens on 80 → connection refused → 502.
- **Fix:** `targetPort: http` (named port) or `80`.
- **Say:** "502 = the proxy reached a backend that answered badly; 503 = no backend at all. Named ports prevent this."

## 09 · 503: Service selector doesn't match
- **Evidence:** pods Ready, EndpointSlice empty; `svc.spec.selector app=inventory-api`, pods `app=inventory`.
- **Fix:** align labels (patch the Service selector, or the pod labels). Remember Deployment `selector` is immutable.
- **Prevention:** labels from one Helm helper; a test that every Service has endpoints after deploy.

## 10 · Default-deny broke DNS
- **Evidence:** `wget: bad address 'backend'` (name resolution); wget by pod IP works.
- **Root cause:** egress default-deny blocks UDP/TCP 53 to CoreDNS in `kube-system`.
- **Fix:**
  ```yaml
  apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata: { name: allow-dns-egress, namespace: bf-10 }
  spec:
    podSelector: {}
    policyTypes: [Egress]
    egress:
      - to:
          - namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: kube-system } }
            podSelector: { matchLabels: { k8s-app: kube-dns } }
        ports: [{ protocol: UDP, port: 53 }, { protocol: TCP, port: 53 }]
  ```
- **Note:** `namespaceSelector` and `podSelector` in the *same* list item = AND; separate items = OR.
- **OpenShift:** DNS pods are in `openshift-dns` on port **5353**; egress policies must allow that.

## 11 · PVC Pending: StorageClass from another cluster
- **Evidence:** PVC event `storageclass.storage.k8s.io "managed-csi" not found`.
- **Root cause:** `managed-csi` is AKS's class; here only `local-path` exists.
- **Fix:** `volumeClaimTemplates` is immutable, so recreate:
  ```bash
  kubectl -n bf-11 get sts ledger-db -o yaml > /tmp/sts.yaml   # edit: storageClassName: local-path, drop status/uid/resourceVersion
  kubectl -n bf-11 delete sts ledger-db          # (--cascade=orphan keeps pods when data matters)
  kubectl -n bf-11 delete pvc data-ledger-db-0   # PVC spec is immutable too
  kubectl apply -f /tmp/sts.yaml
  ```
- **Prevention:** make StorageClass a Helm value per platform, or name classes the same on all clusters.

## 12 · Stuck Terminating: orphaned finalizer
- **Evidence:** `deletionTimestamp` set, `finalizers: [batch.example.com/upload-results]`; no controller for it.
- **Fix (after confirming nothing needs the upload):**
  `kubectl -n bf-12 patch pod batch-runner --type=merge -p '{"metadata":{"finalizers":null}}'`
- **Say:** "A finalizer is a promise that a controller will clean up. Force-deleting skips the cleanup; I find
  out who owns it first. `--force --grace-period=0` on a StatefulSet pod can mean two writers."

## 13 · Drain blocked by PDB
- **Evidence:** `Cannot evict pod as it would violate the pod's disruption budget`; PDB `ALLOWED DISRUPTIONS 0`
  because `minAvailable: 2` = `replicas: 2`.
- **Safe fix:** add capacity first, then drain:
  ```bash
  kubectl -n bf-13 scale deploy matching-engine --replicas=3
  kubectl drain NODE --ignore-daemonsets --delete-emptydir-data
  kubectl uncordon NODE    # after patching
  ```
  Or change the PDB to `maxUnavailable: 1` with the app team's agreement.
- **Say:** "A PDB equal to replicas blocks every node upgrade. On AKS the upgrade fails or waits on it; I'd
  catch it before the window with a check across all namespaces."
  `kubectl get pdb -A -o json | jq -r '.items[] | select(.status.disruptionsAllowed==0) | .metadata.namespace+"/"+.metadata.name'`
- **Gotcha found while building this:** `topologySpreadConstraints … DoNotSchedule` can keep the evicted
  pod Pending, because the cordoned node still counts as a domain with 0 pods.

## 14 · Node NotReady
- **Evidence:** `Ready=Unknown, Kubelet stopped posting node status`; taints `node.kubernetes.io/unreachable`.
- **Impact:** pods on that node show Running in the API but serve nothing; after `tolerationSeconds: 300`
  (default) they're evicted and recreated elsewhere. Services drop them from endpoints once marked not ready.
- **Fix here:** `docker start k3d-lab-agent-0`. In real life: kubelet/runtime status, disk/memory/PID pressure,
  network to the API server, cloud VM state; then repair or replace (AKS: node auto-repair; OpenShift:
  `MachineHealthCheck` replaces the Machine).
- **Say:** "I don't delete a NotReady node first: stateful pods with RWO volumes may still be attached."

## 15 · Pod Security restricted: no pods at all
- **Evidence:** `kubectl get pods` empty; ReplicaSet `FailedCreate … violates PodSecurity "restricted:latest":
  allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile`.
- **Fix:** non-root image + securityContext:
  ```yaml
  spec:
    securityContext: { runAsNonRoot: true, seccompProfile: { type: RuntimeDefault } }
    containers:
      - name: web
        image: nginxinc/nginx-unprivileged:1.29-alpine   # listens on 8080, uid 101
        securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: [ALL] } }
  ```
- **OpenShift:** same idea, `restricted-v2` SCC assigns a random UID from the namespace range; images must
  work as an arbitrary UID with group 0 (`chgrp -R 0 && chmod -R g=u`).

## 16 · RBAC: CI service account forbidden
- **Fix (least privilege):**
  ```yaml
  rules:
    - { apiGroups: [""],   resources: [pods],        verbs: [get, list] }
    - { apiGroups: [apps], resources: [deployments], verbs: [get, list, watch, patch] }
    - { apiGroups: [apps], resources: [replicasets], verbs: [get, list, watch] }   # rollout status
  ```
  Test: `kubectl -n bf-16 auth can-i --list --as=system:serviceaccount:bf-16:ci-deployer`
- **Say:** "Error message → which verb, resource, API group → smallest Role that allows exactly that.
  Never a ClusterRoleBinding to cluster-admin for a pipeline." On AKS with Entra: Azure RBAC for
  Kubernetes or Entra groups in RoleBindings; workload identity for pipelines instead of long-lived tokens.

## 17 · ResourceQuota: replicas missing, nothing Pending
- **Evidence:** ReplicaSet `FailedCreate: exceeded quota: team-quota, requested: requests.cpu=250m, used: 500m, limited: 500m`.
- **Fix:** right-size requests (usage is ~20m), and get past the second trap: the rolling update needs quota
  for its surge pod, so it deadlocks. Tested way out:
  ```bash
  kubectl -n bf-17 set resources deploy worker --requests=cpu=100m,memory=64Mi --limits=cpu=200m,memory=128Mi
  kubectl -n bf-17 patch deploy worker -p '{"spec":{"strategy":{"rollingUpdate":{"maxSurge":0,"maxUnavailable":2}}}}'
  ```
  After many FailedCreate errors the ReplicaSet controller backs off for minutes; any update to the
  ReplicaSet (or `kubectl rollout restart`) makes it retry immediately.
- **Say:** "Quota counts requests, not usage. Right-sizing is in our hands today; a quota increase is a
  capacity decision with an approval."

## 18 · Kyverno denial
- **Evidence:** the denial lists three failed rules: `autogen-require-team-label`, `autogen-require-memory-limit`,
  `autogen-disallow-latest-tag` (autogen = Kyverno generated the Deployment rule from the Pod rule).
- **Fix:** label `team: analytics` on the pod template, requests/limits, a pinned tag like `nginx:1.29-alpine`.
- **Bonus:** Kyverno 1.19 warns `kyverno.io/v1 ClusterPolicy is deprecated … migrate to ValidatingPolicy`
  (CEL-based, `policies.kyverno.io`). Knowing this, and Kubernetes' own ValidatingAdmissionPolicy, is a strong
  interview point.
- **Rollout story:** Audit → read PolicyReports → talk to the owners → Enforce, per namespace/cluster wave.

## 19 · Ingress class nobody serves + catch-all route
- **Evidence:** `kubectl get ingress -A`: `portal` has class `webapprouting.kubernetes.azure.com` and **no ADDRESS**;
  `default/hello` with host `*` answers everything.
- **Fix:** `kubectl -n bf-19 patch ingress portal -p '{"spec":{"ingressClassName":"traefik"}}'`
- **Say:** "No controller owns that class, so the Ingress is silently ignored. Catch-all routes hide the 404."
- **AKS talking point:** the community ingress-nginx project was retired in March 2026. Options: AKS
  application routing add-on (class `webapprouting.kubernetes.azure.com`; check its current support
  timeline in the AKS docs), Application Gateway for Containers, or a Gateway API implementation.
  Start with an inventory: `kubectl get ingress -A -o wide` plus the `nginx.ingress.kubernetes.io/*`
  annotations in use, because those don't carry over.
