# Day 9 – JFrog wrap-up, GitHub Enterprise trial and enterprise policies

**Goal:** finish JFrog before the trial ends (14 Oct), then move governance one level up: from one
organization to an **enterprise** whose policies every organization inherits and can't loosen.

Time: about 1.5h (Part D and E can move to tomorrow).

---

## Part A – JFrog wrap-up (about 25 min)

1. **One version, one place.** `k8s/apps/lab-api/kustomization.yaml` now holds the version
   (`newTag`); Kustomize sets the image and copies the tag into `APP_VERSION`, so they can't drift
   apart again (the 1.0.22 / 1.0.26 incident). Check the rendered result:
   ```bash
   cd ~/workspace
   kubectl kustomize k8s/apps/lab-api | yq 'select(.kind=="Deployment") | .spec.template.spec.containers[0] | [.image, (.env[]|select(.name=="APP_VERSION").value)]'
   ```
   After this PR is merged, Argo CD shows **Synced** with no rollout: nothing that runs changed.
2. **Screenshots for interviews** (the trial ends 14 Oct; the code stays, the UI doesn't):
   - Build-info of `lab-api`: the build's modules, environment, git commit and SBOM artifact
   - An Xray build scan: the URL is printed by `jf build-scan`, e.g.
     `$JFROG_URL/ui/scans-list/builds-scans/lab-api/scan-descendants/<build>?version=<build>&package_id=build%3A%2F%2Flab-api`
   - `lab-docker-prod-local/lab-api/1.0.26` with its `promoted.*` properties
   - Identity mappings: Administration → General Management → Manage Integrations → OpenID Connect
   - The two cleanup policies and the watches/policies list (use the admin search box)
3. After 14 Oct, `terraform plan` in `terraform/jfrog` will fail (the instance is gone). That's
   expected; the code and its history remain your evidence.

---

## Part B – Start the GitHub Enterprise Cloud trial (about 15 min)

GitHub's guide: https://docs.github.com/en/enterprise-cloud@latest/admin/overview/setting-up-a-trial-of-github-enterprise-cloud

- Use your **existing** account and choose an enterprise **with personal accounts** (Enterprise
  Managed Users needs GitHub sales and a separate setup).
- Pick a short enterprise slug (e.g. `sandeep-platform-lab-ent`); you'll need it below.
- Add the existing organization **sandeep-platform-lab** to the enterprise.
- The trial lasts 30 days. Note the end date in `PLAN.local.md`.

Check from the CLI:
```bash
gh auth refresh -s admin:enterprise,read:audit_log
SLUG=<your enterprise slug>
gh api "enterprises/$SLUG" --jq '{name, slug, html_url}' 2>/dev/null || gh api graphql -f query="{ enterprise(slug:\"$SLUG\") { name slug url organizations(first:5){ nodes { login } } } }"
```

---

## Part C – Enterprise policies as code (about 30 min)

`terraform/github-enterprise/policies.tf` (its own stack: needs an enterprise and `admin:enterprise`):

| Policy | Setting | Why |
|---|---|---|
| Allowed actions | GitHub-owned + `jfrog/setup-jfrog-cli`, `sigstore/cosign-installer` only | Third-party code in CI is supply-chain risk; allowlist what you've reviewed |
| Default `GITHUB_TOKEN` | read-only; workflows can't approve PRs | Least privilege; no bot self-approval |
| New repositories | secret scanning + push protection + validity checks on | Secure by default |

All actions our workflows use are covered (checked: `actions/*`, `github/codeql-action`, the two above).

```bash
cd ~/workspace/terraform/github-enterprise
export GITHUB_TOKEN=$(gh auth token)
terraform init -backend-config=../backend.hcl
terraform plan  -var enterprise_slug=$SLUG
terraform apply -var enterprise_slug=$SLUG
gh api "enterprises/$SLUG/actions/permissions" ; gh api "enterprises/$SLUG/actions/permissions/selected-actions"
```

**Prove it blocks:** on a throwaway branch, add a workflow that uses an action that isn't on the list:
```bash
cd ~/workspace && git switch main && git pull && git switch -c test-blocked-action
cat > .github/workflows/blocked.yml <<'EOF'
name: blocked
on: pull_request
permissions:
  contents: read
jobs:
  try:
    runs-on: ubuntu-latest
    steps:
      - uses: docker/setup-buildx-action@v3
EOF
git add .github/workflows/blocked.yml && git commit -m "test: action not on the allowlist"
git push -u origin test-blocked-action && gh pr create --base main --title "test: blocked action" --body "Day 9 exercise"
gh run list --branch test-blocked-action --limit 3
```
The `blocked` run fails immediately with "… is not allowed to be used in sandeep-platform-lab/platform-lab".
Clean up: `gh pr close test-blocked-action --delete-branch; git switch main; git branch -D test-blocked-action`.

---

## Part D – The policies that aren't code yet (about 20 min)

In the enterprise settings (**Policies** section), look at each area and note the options:
**Repositories** (base permissions, who may create, fork, change visibility, delete, transfer),
**Member privileges**, **Code security**, **Actions** (what Terraform just set: it shows as enforced).

For each, an enterprise policy is either **enforced** (organizations can't change it) or **"No
policy"** (each organization decides). Open the organization's settings: enforced settings are
greyed out with "managed by your enterprise".

---

## Part E – Audit log, first look (about 10 min)

Every policy change you just made is an audit event:
```bash
gh api "enterprises/$SLUG/audit-log?phrase=action:enterprise&per_page=10" \
  --jq '.[] | "\(.["@timestamp"]/1000|todate)  \(.actor)  \(.action)"'
```
Tomorrow these events stream to Azure, so they're kept and searchable outside GitHub.

---

## Interview notes

- **Enterprise vs organization:** the enterprise sets the guardrails (enforced policies, SSO,
  audit log, billing, Copilot), organizations group teams and repos within them. Enforce at the top
  what must be uniform; leave "No policy" where teams legitimately differ.
- **Actions allowlisting** is the GitHub-side answer to the tj-actions incident, alongside SHA
  pinning and Semgrep checks in CI (Day 4).
- **Secure by default:** turning features on for *new* repos at the enterprise level beats
  remembering to do it per repo.
- **As code where the API allows, documented where it doesn't:** not every enterprise policy has
  a Terraform resource yet; record the rest in a runbook and check them in the audit log.
- **Scan what you deploy:** Trivy flagged `image: lab-api` in the Kustomize base as `:latest`
  (MEDIUM); the rendered manifest has the real tag. Scan rendered output too
  (`kubectl kustomize k8s/apps/lab-api > /tmp/lab-api.yaml && trivy config /tmp/lab-api.yaml`).

## Notes

_Your observations here._
