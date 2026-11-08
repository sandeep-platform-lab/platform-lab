# TeamSpace operator (kubebuilder)

A small Operator you build yourself. One custom resource describes a team; the controller makes the
namespace, quota and admin RoleBinding, and keeps them that way. Same outcome as the Ansible playbook
(`labs/ansible/onboard-team.yml`), so you can compare the two models in the interview.

```yaml
apiVersion: platform.example.com/v1alpha1
kind: TeamSpace          # cluster-scoped
metadata: { name: payments }
spec: { cpu: "2", memory: 4Gi, adminGroup: payments-admins }
# -> Namespace team-payments (Pod Security restricted) + ResourceQuota team-quota + RoleBinding team-admins
```

`reference/` has a tested solution (kubebuilder v4.16, controller-runtime v0.25, Go 1.27). Try to write it
yourself first; copy only when stuck. Steps are in `docs/day17.md`.

| File | What's in it |
|---|---|
| `reference/teamspace_types.go` | Spec (cpu, memory, adminGroup), Status (namespace, conditions), markers for scope, print columns |
| `reference/teamspace_controller.go` | Reconcile with `CreateOrUpdate` + owner references, status conditions, `Owns()` watches, RBAC markers |
| `reference/platform_v1alpha1_teamspace.yaml` | Sample CR |

Tested behaviour: create → namespace/quota/RoleBinding appear, `READY=True`; delete the quota by hand → it's
back within a second; change `spec.cpu` → quota updated; delete the TeamSpace → garbage collector removes
the namespace (owner reference). That last one is a design question: do you *want* deleting a CR to delete
a namespace full of data? (Options: no owner reference on the Namespace + a finalizer that refuses while
workloads exist, or `deletionPolicy: Retain` in the spec.)
