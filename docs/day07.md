# Day 7 – Promotion, GitOps and admission control

**Goal:** an approved, signed, re-scanned build moves from dev to prod without being rebuilt; the
cluster runs exactly what git says; and the cluster refuses anything that isn't a signed release.

Time: 5–6h.

```
supply-chain (main)          promote.yml                                   Argo CD           Kyverno
build → Xray → sign  ──▶  approval (env "production") ──▶ JFrog dev → prod  ──▶ git → cluster ──▶ admit only
  lab-docker-dev-local      verify sig → Xray re-scan → copy + verify          (k8s/apps)        signed prod images
```

| Piece | Where |
|---|---|
| Promotion workflow | `.github/workflows/promote.yml` |
| GitHub `production` environment (approval, main only) | `terraform/github/environments.tf` |
| JFrog: OIDC mapping `environment=production` → `lab-release` | `terraform/jfrog/oidc.tf` |
| Argo CD + Kyverno install (pinned) | `scripts/k8s-bootstrap.sh` (already run on your cluster) |
| Admission policy | `k8s/platform/kyverno/require-signed-prod-images.yaml` |
| App manifests, Argo CD apps | `k8s/apps/lab-api/`, `k8s/argocd/applications.yaml` |

Already tested on your cluster: a signed build was admitted and pinned to its digest; an unsigned
image and a Docker Hub image were rejected.

---

## Part A – Read and apply (about 1h)

Read the code first:
1. In `oidc.tf`, why must the production mapping have priority 1? What would a promotion job get
   if it were checked after `platform-lab-main`?
2. `promote.yml` re-scans with Xray although the build passed Xray when it was built. Why?
3. Why does promotion **copy** the `.sig` and `.att` tags as well?
4. In the Kyverno policy, what does `pod-policies.kyverno.io/autogen-controllers: none` prevent?

Merge order (`promote.yml` must be on `main` before GitHub offers it):
1. Day 6 PR (`day06-housekeeping`), if not merged yet.
2. This PR (`day07-promotion-gitops`).

Then apply:
```bash
cd ~/workspace/terraform/github && export GITHUB_TOKEN=$(gh auth token)
terraform apply     # production environment + main-only deployment policy

cd ~/workspace/terraform/jfrog && set -a; source ~/workspace/.env; set +a
terraform apply     # production OIDC mapping (priority 1), release group can read dev + scan builds
```

---

## Part B – Promote the latest main build (about 45 min)

Promote the newest successful `supply-chain` build on `main` (at the time of writing: **22**), and
make sure `k8s/apps/lab-api/deployment.yaml` uses the same tag, because that's what Argo CD deploys.
```bash
cd ~/workspace
RUN=$(gh run list --workflow supply-chain.yml --branch main --status success --limit 1 --json number --jq '.[0].number')
echo "promoting 1.0.$RUN"; grep "lab-api:" k8s/apps/lab-api/deployment.yaml
gh workflow run promote.yml -f build_number="$RUN"
gh run list --workflow promote.yml --limit 1
```
1. The run **waits**: GitHub → Actions → the run → **Review deployments** → tick `production` →
   **Approve and deploy**. Nobody, not even an admin, gets past this without an approval.
2. Watch the gates: signature → Xray re-scan → promote → verify in prod.
3. In JFrog, `lab-docker-prod-local/lab-api/1.0.<n>` now exists, with properties
   `promoted.build`, `promoted.by`, `promoted.run`. Compare its digest with the dev copy.

---

## Part C – GitOps deploy (about 1h)

1. Namespace with Pod Security "restricted", and the pull secret (read-only, 7 days, never in git):
   ```bash
   set -a; source ~/workspace/.env; set +a; REG=${JFROG_URL#https://}
   kubectl create namespace lab
   kubectl label namespace lab pod-security.kubernetes.io/enforce=restricted
   TOKEN=$(jf atc --groups lab-developers --expiry 604800 | jq -r .access_token)
   kubectl -n lab create secret docker-registry jfrog-pull \
     --docker-server="$REG" --docker-username="$JFROG_USER" --docker-password="$TOKEN"
   unset TOKEN
   ```
   (Kyverno already has the same secret in the `kyverno` namespace to read signatures. If it's
   older than 7 days, recreate it the same way with `-n kyverno`.)
2. Hand the cluster to Argo CD:
   ```bash
   kubectl apply -f ~/workspace/k8s/argocd/applications.yaml
   ```
3. Argo CD UI:
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
   kubectl -n argocd port-forward svc/argocd-server 8090:80
   ```
   Open http://localhost:8090 (user `admin`). Both apps should become **Synced / Healthy**.
4. Test it:
   ```bash
   curl -s http://lab-api.localhost:8080/api/info
   kubectl -n lab get pods -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}'
   ```
   The running image ends in `@sha256:…`: Kyverno pinned it to the verified digest.

---

## Part D – Try to break it (about 1h)

1. **Unsigned image:**
   ```bash
   kubectl -n lab set image deployment/lab-api lab-api="$REG/lab-docker-dev-local/lab-api:devtest-1791050620"
   kubectl -n lab get events --sort-by=.lastTimestamp | tail -5
   ```
   Kyverno blocks the new pods. Then watch Argo CD **self-heal** the Deployment back to what's in git.
2. **Image from the internet:**
   ```bash
   kubectl -n lab run nginx --image=nginx:1.29
   ```
3. **Signed, but not a release:** set the image to a *dev* tag, e.g. `$REG/lab-docker-dev-local/lab-api:1.0.19`.
   It's signed, but it isn't in the prod repo, so it's rejected.
4. **Change by hand:** `kubectl -n lab scale deployment lab-api --replicas=5`. What does Argo CD do?

---

## Part E – Release a new version, the GitOps way (about 1h)

1. Make a small change to `app/src/main.py` (e.g. a new field in `/api/info`), PR, merge.
   `supply-chain` builds, scans and signs build N.
2. `gh workflow run promote.yml -f build_number=N`, approve.
3. PR: change the image tag **and** `APP_VERSION` in `k8s/apps/lab-api/deployment.yaml` to `1.0.N`.
   Merging the PR *is* the deployment: Argo CD rolls it out.
4. Rollback = revert that PR.

---

## Interview notes

- **Build once, promote many:** the bytes tested in dev are the bytes in prod. Promotion is a
  copy (cheap with checksum storage), never a rebuild.
- **Separation of duties:** CI can only push to dev; only a job in the approved `production`
  environment gets the release group; the cluster only admits signed prod images. Three
  independent controls, each with an audit trail (GitHub approvals, JFrog properties and logs,
  Kyverno policy reports).
- **Re-scan at promotion:** new CVEs are published every day; yesterday's clean build may not
  be clean today.
- **GitOps (pull model):** the cluster pulls desired state from git, so there are no cluster
  credentials in CI; drift is corrected automatically; deploy and rollback are PRs.
- **Admission control is the last gate:** even a cluster-admin's `kubectl` can't run an unsigned
  image. Pinning to a digest means a moved tag can't change what runs.
- **Gotchas met here:** OIDC mapping priorities (first match wins); Kyverno auto-generating
  Deployment rules that fight Argo CD; `ClusterPolicy` being deprecated in favour of CEL-based
  `ImageValidatingPolicy`; pull-secret tokens expiring (on AKS you'd use workload identity or a
  managed registry integration instead of a static token).

## Notes

_Your observations here._
