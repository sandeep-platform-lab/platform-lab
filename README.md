# Platform Lab

A two-week hands-on lab: a secure software supply chain on GitHub, JFrog and Azure,
with Kubernetes and a developer-workplace (Dev Box) track.

```
GitHub repo (rulesets, CODEOWNERS, Copilot)
  → GitHub Actions (OIDC, no stored secrets)
  → Semgrep · Gitleaks · Trivy (code, secrets, IaC, image)
  → build → JFrog Artifactory (build-info, SBOM, Cosign signature)
  → Xray policy gate → promote dev → prod
  → Argo CD → Kubernetes (k3d locally, AKS in Azure) · Kyverno admits signed images only
  → OWASP ZAP (DAST)
Infra: Terraform · Azure Policy · Key Vault · workload identity
Workplace: Dev Box / Windows 365 · custom images · pools
```

## Status (Nov 2026)

The trials have ended. Their code stays in the repo as reference, and the pipelines still run and gate
every change.

| Part | State | What still runs | To switch it back on |
|---|---|---|---|
| JFrog Cloud (`terraform/jfrog`, push/build-info/Xray/sign in `supply-chain`, `promote`) | trial ended Oct 2026 | Build from Docker Hub, Gitleaks, Semgrep, Trivy, dependency review; `terraform validate` | New JFrog instance → `terraform apply` in `terraform/jfrog` → set repository variable `JFROG_URL` |
| GitHub Enterprise Cloud (`terraform/github-enterprise`, audit log streaming, Entra SSO, Copilot Business) | trial ended Nov 2026; org back on GitHub Free | Repository ruleset, CODEOWNERS, `production` environment, code/secret scanning (free for public repos); `terraform validate` | Buy or trial Enterprise Cloud again, `terraform apply` in `terraform/github-enterprise` |
| `terraform/azure-audit` (audit log WORM storage) | no new data after the trial | – | `terraform destroy` once the 30-day immutability period of the last blob has passed |

## Layout

| Path | Contents |
|---|---|
| `app/` | `lab-api`: sample FastAPI service with tests and a non-root Dockerfile |
| `.github/workflows/` | CI/CD pipelines |
| `terraform/github/` | Teams, repo permissions, the `main` ruleset and the production environment as code |
| `terraform/github-enterprise/` | Enterprise policies: allowed actions, default token permissions, secret scanning defaults |
| `terraform/jfrog/` | JFrog Project, repos, groups, permissions and GitHub OIDC trust as code |
| `jfrog-selfhosted/` | Artifactory OSS + PostgreSQL in Docker Compose for operations practice |
| `terraform/azure/` | Landing zone basics and AKS: Azure Policy, VNet, Log Analytics, Key Vault, AKS with Entra RBAC and workload identity |
| `terraform/azure-audit/` | Permanent, immutable (WORM) storage for the GitHub Enterprise audit log stream |
| `terraform/azure-images/` | Azure Compute Gallery and image definition for golden images |
| `images/` | Packer templates: the developer workstation golden image |
| `k8s/azure/` | lab-api on AKS with workload identity and the Key Vault CSI driver |
| `k8s/` | Local cluster config, Argo CD apps, Kyverno policies |
| `scripts/` | Helper scripts |
| `labs/breakfix/` | 19 break-fix scenarios for the local cluster (`scripts/breakfix.sh`) with tested solutions |
| `labs/policy/` | ValidatingAdmissionPolicy (CEL) to compare with Kyverno |
| `labs/observability/` | kube-prometheus-stack values, alert rules, Alertmanager routing |
| `labs/ansible/` | Team onboarding playbook (namespace, quota, network policies, RBAC), AAP-ready |
| `labs/operator/` | TeamSpace operator (kubebuilder, Go): guide and tested reference code |
| `labs/gitlab-ci/` | GitLab CI/CD reference pipeline for a GitOps deployment |
| `docs/` | Daily runbooks, decisions, interview notes |

## Roadmap

- [x] Local tooling and Kubernetes (k3d)
- [x] GitHub org governance: teams, rulesets, CODEOWNERS
- [x] JFrog Artifactory administration as code (repos, permissions, Projects)
- [x] Supply-chain pipeline: scans → push → build-info → SBOM → signing
- [x] Xray policies, watches and Curation
- [x] Artifactory housekeeping: cleanup policies, AQL, retention
- [x] Promotion gates, Argo CD, Kyverno signature verification
- [x] GitHub Enterprise: policies, audit log streaming, Entra SSO
- [x] Copilot administration and GitHub Advanced Security
- [x] Azure landing zone with Terraform: AKS, Key Vault, workload identity, Azure Policy
- [x] Developer workplace: golden image pipeline (Packer → Compute Gallery); Dev Box → Windows 365 concepts
- [ ] DAST with OWASP ZAP
- [ ] Troubleshooting dojo: pods, nodes, upgrades (day 14)
- [ ] Troubleshooting dojo: connectivity, security, policy, storage (day 15)
- [ ] Observability (Prometheus rules, Alertmanager) and Ansible automation (day 16)
- [ ] OpenShift hands-on and a Go Operator (day 17)
- [ ] Mock interview and whiteboard (day 18)

## Secrets

Never commit tokens. Put them in `.env` (git-ignored); see `.env.example`.
