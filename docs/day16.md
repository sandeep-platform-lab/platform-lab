# Day 16 – Observability and automation

**Goal:** write and test an alert end to end (rule → Prometheus → Alertmanager route); automate a typical
app-team request with Ansible so it's ready for AAP; read a GitLab pipeline for a GitOps deployment.

Time: about 3h.

| Piece | Where |
|---|---|
| Stack install (pinned) | `scripts/observability-install.sh` |
| Values (k3d-specific, Alertmanager routing) | `labs/observability/values-k3d.yaml` |
| Your alert rules | `labs/observability/platform-alerts.yaml` |
| Team onboarding playbook | `labs/ansible/onboard-team.yml`, `templates/team-baseline.yaml.j2` |
| GitLab pipeline | `labs/gitlab-ci/.gitlab-ci.yml` |

---

## Part A – Prometheus and alerts (about 1.5h)

```bash
scripts/observability-install.sh       # ~3 min; already tested on your cluster
```
Prometheus http://prometheus.localhost:8080 · Alertmanager http://alertmanager.localhost:8080 ·
Grafana http://grafana.localhost:8080 (admin/admin).

**1. PromQL drills.** Type each into Prometheus → Graph, and explain what it means:
```promql
up == 0                                                             # which targets are down
sum by (namespace) (kube_pod_container_status_restarts_total)        # restarts per namespace
increase(kube_pod_container_status_restarts_total[15m]) > 0          # restarted recently
kube_pod_status_phase{phase="Pending"} == 1                          # Pending pods
sum by (namespace, pod) (container_memory_working_set_bytes{container!=""})
  / sum by (namespace, pod) (kube_pod_container_resource_limits{resource="memory"})   # memory vs limit
sum by (namespace) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))       # CPU cores used
kube_node_status_condition{condition="Ready",status="true"} == 0    # NotReady nodes
kube_deployment_spec_replicas != kube_deployment_status_replicas_available
```
Know why it's `rate()` for counters and never for gauges, and why `[5m]` must be at least 4× the scrape
interval.

**2. Fire your own alerts.**
```bash
scripts/breakfix.sh break 03     # -> LabPodCrashLooping
scripts/breakfix.sh break 05     # -> LabContainerOOMKilled
```
Watch Prometheus → Alerts go inactive → pending → firing (2–4 min), then find them in Alertmanager and
check which receiver they were routed to. Read `platform-alerts.yaml`: the CrashLoop rule uses
`max_over_time(...[5m])`. Delete that wrapper, re-apply, and watch the alert never leave *pending*: the
waiting reason flaps and resets `for:`. (We hit exactly this while building the lab.)

**3. Routing.** In `values-k3d.yaml`, read the Alertmanager `route` tree and the inhibit rule. Questions:
why is there a `Watchdog` alert that always fires? Why inhibit pod alerts while the node is NotReady? Where
do app-team alerts go vs platform alerts? What makes an alert *actionable* (runbook link, owner, severity)?

**4. Logs (talk, don't build).** Elastic/ECK or Loki: what you'd ship (container stdout via Fluent Bit,
Kubernetes events, audit logs), retention for a regulated company, and correlating a log line with a
metric spike and a deployment.

---

## Part B – Automate a customer request with Ansible (about 1h)

The most common ticket for a platform team: "we need a namespace". Today you did its pieces by hand in
break-fix 10, 15, 16 and 17. Now as code:

```bash
ansible-playbook labs/ansible/onboard-team.yml -e team=payments -e cpu=2 -e memory=4Gi
ansible-playbook labs/ansible/onboard-team.yml -e team=payments -e cpu=2 -e memory=4Gi   # again: changed=0
kubectl get ns team-payments --show-labels; kubectl -n team-payments get quota,limitrange,netpol,rolebinding
ansible-playbook labs/ansible/onboard-team.yml -e team=BAD_NAME                          # input validation
ansible-playbook labs/ansible/offboard-team.yml -e team=payments
```
(Ansible 2.21 and `kubernetes.core` 6.6 are installed; tested on your cluster.)

Map it to AAP on paper:

| Playbook piece | AAP object |
|---|---|
| `-e team=... cpu=...` | **Survey** on a **Job Template** (with validation) |
| kubeconfig / OpenShift token | **Credential** (custom credential type or OpenShift/K8s API bearer token) |
| `kubernetes.core` + Python `kubernetes` | **Execution Environment** image (built with `ansible-builder`) |
| repo with the playbook | **Project** (synced from GitLab) |
| dev → approval → prod | **Workflow Job Template** with an **Approval node** |
| who may launch it | AAP RBAC: team gets *execute* on the template only |
| self-service | ServiceNow/portal calls the AAP API |

Then the trade-off question you will get: *why not Argo CD for this?* (GitOps: a PR per team in a
"tenants" repo + an ApplicationSet → declarative, drift-corrected; Ansible/AAP: good for imperative steps
across systems such as AD groups, firewall, DNS, CMDB; an Operator: continuous reconciliation inside the
cluster, see Day 17). A good answer often combines them.

---

## Part C – GitLab CI/CD (about 30 min, reading)

Read `labs/gitlab-ci/.gitlab-ci.yml` and explain each stage. Be ready for: `rules` vs `only/except`,
`needs` (DAG), `id_tokens` (OIDC to Vault/Azure/Sigstore instead of stored secrets), protected branches and
protected variables, environments and deployment approvals, runners (shared vs group, Kubernetes executor),
why the pipeline doesn't `kubectl apply` (Argo CD pulls), and how promotion to prod works (a merge request
with approval in the GitOps repo).

---

## Notes
