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
| `k8s/azure/` | lab-api on AKS with workload identity and the Key Vault CSI driver |
| `k8s/` | Local cluster config, Argo CD apps, Kyverno policies |
| `scripts/` | Helper scripts |
| `docs/` | Daily runbooks, decisions, interview notes |

## Roadmap

- [x] Local tooling and Kubernetes (k3d)
- [x] GitHub org governance: teams, rulesets, CODEOWNERS
- [x] JFrog Artifactory administration as code (repos, permissions, Projects)
- [x] Supply-chain pipeline: scans → push → build-info → SBOM → signing
- [x] Xray policies, watches and Curation
- [x] Artifactory housekeeping: cleanup policies, AQL, retention
- [x] Promotion gates, Argo CD, Kyverno signature verification
- [ ] GitHub Enterprise: policies, audit log streaming, Entra SSO
- [ ] Copilot administration and GitHub Advanced Security
- [x] Azure landing zone with Terraform: AKS, Key Vault, workload identity, Azure Policy
- [ ] Developer workplace: Dev Box / Windows 365 images and pools
- [ ] DAST with OWASP ZAP

## Secrets

Never commit tokens. Put them in `.env` (git-ignored); see `.env.example`.
