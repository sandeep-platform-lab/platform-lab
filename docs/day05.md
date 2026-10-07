# Day 5 – Xray policies, watches and Curation

**Goal:** JFrog Xray continuously scans everything stored and built, decides what's a violation,
and acts: fail the build, block the download, or record it for triage. Curation (where licensed)
stops bad packages from entering Artifactory at all.

Time: 5–6h. Code: `terraform/jfrog/xray.tf`, `terraform/jfrog/curation.tf`, pipeline step
`Xray build scan` in `.github/workflows/supply-chain.yml`.

```
                    Policies (what + action)                       Watches (where)
 lab-sec-build-gate  HIGH+ with fix      → fail build     ┐
 lab-sec-runtime     malicious, CRIT+fix → block download ├──▶ lab-builds     (build lab-api)
 lab-sec-track       HIGH+ (any)         → violation only │    lab-prod-repo  (lab-docker-prod-local)
 lab-license         AGPL/GPL            → violation      ┘    lab-dev-repos  (dev, remote, evidence)
```

| Watch | Policies |
|---|---|
| `lab-builds` | build-gate, track, license |
| `lab-prod-repo` | runtime, track |
| `lab-dev-repos` | track, license |

---

## Part A – Apply and look around (about 45 min)

```bash
cd ~/workspace/terraform/jfrog
set -a; source ~/workspace/.env; set +a
terraform plan     # expect: 8 to add, 1 to change, 0 to destroy
terraform apply
```

Before applying, answer from the code:
1. Why is "block download" only on the **prod** watch, not on dev?
2. `lab-sec-track` has no action at all. What's the point of a policy that doesn't block?
3. Why does `lab-ci` now need `SCAN` on builds?

Check what's live (API, so it doesn't depend on menu names):
```bash
H="Authorization: Bearer $JFROG_ACCESS_TOKEN"
curl -s -H "$H" "$JFROG_URL/xray/api/v2/policies" | jq -r '.[].name'
curl -s -H "$H" "$JFROG_URL/xray/api/v2/watches" | jq -r '.[] | "\(.general_data.name): \([.assigned_policies[].name]|join(", "))"'
```
In the UI, find the same under the **Xray** part of the Platform (Watches & Policies). If the menu
differs, use the search box.

---

## Part B – Scan what already exists (about 45 min)

Watches act on *new* events. To evaluate content that was already there, apply them to history:
```bash
curl -s -X POST -H "$H" -H "Content-Type: application/json" "$JFROG_URL/xray/api/v1/applyWatch" \
  -d '{"watch_names":["lab-dev-repos","lab-builds"],"date_range":{"start_date":"2026-10-01T00:00:00Z","end_date":"2026-12-31T00:00:00Z"}}'
```

Scan the build from Day 4 (build 8) with your admin CLI config:
```bash
jf build-scan lab-api 8 --vuln
```
If it says the build isn't indexed: build 8 was published before `lab-api` was added to Xray's
indexed builds. Re-run the pipeline on `main` (`gh workflow run supply-chain.yml --ref main`) and use
that new build number instead.

- How many vulnerabilities does Xray report? Compare with Trivy's 44 HIGH from Day 4.
- Did it fail? It shouldn't: none of the HIGH issues have a fix, so `lab-sec-build-gate` doesn't
  match, but `lab-sec-track` records them.

List the violations:
```bash
curl -s -X POST -H "$H" -H "Content-Type: application/json" "$JFROG_URL/xray/api/v1/violations" \
  -d '{"filters":{"watch_name":"lab-builds"},"pagination":{"limit":100}}' \
  | jq -r '.violations[] | "\(.severity)\t\(.type)\t\(.issue_id)\t\(.impacted_artifacts[0])"' | sort | uniq | head -20
```

---

## Part C – The pipeline gate (about 45 min)

Push this branch and open the PR as usual. When it's merged, the `main` run now does:

```
push → build-info → SBOM → Xray build scan → (only if it passed) cosign sign + attest
```

1. Merge, then open the `main` run and read the `Xray build scan` step.
2. Why scan **before** signing? What would a signature on a failed image mean?

---

## Part D – Triage with an ignore rule (about 45 min)

Pick one HIGH CVE from Part B that has no fix (base image). Real teams don't just click "ignore":
an ignore rule is a **risk acceptance** with a justification, a scope and an expiry date, and it's
reviewed like code. Add to `terraform/jfrog/xray.tf`:

```hcl
resource "xray_ignore_rule" "base_image_cve" {
  notes           = "No fix in Debian yet; not reachable from lab-api. Re-check on expiry. Ticket: LAB-1"
  expiration_date = "2026-11-15"
  cves            = ["CVE-XXXX-XXXXX"] # from Part B
  watches         = [xray_watch.builds.name]
}
```
`terraform apply`, then rescan:
```bash
jf build-scan lab-api 8 --vuln --rescan
```
The violation is gone, and it comes back on 15 Nov unless someone renews it with a new justification.

---

## Part E – Block a download from prod (about 1h)

Put a deliberately old, vulnerable image into the prod repo (as admin) and try to pull it:
```bash
REG=${JFROG_URL#https://}
echo "$JFROG_ACCESS_TOKEN" | docker login "$REG" -u "$JFROG_USER" --password-stdin
docker pull python:3.9.0-slim
docker tag python:3.9.0-slim "$REG/lab-docker-prod-local/test/python:3.9.0-slim"
docker push "$REG/lab-docker-prod-local/test/python:3.9.0-slim"
docker rmi "$REG/lab-docker-prod-local/test/python:3.9.0-slim" python:3.9.0-slim
```
Wait 2–5 minutes for Xray to index it, then:
```bash
docker pull "$REG/lab-docker-prod-local/test/python:3.9.0-slim"
```
Expected: the pull is **rejected** with a message naming the Xray policy. That's what stops a
cluster from ever running it. Clean up afterwards:
```bash
jf rt del "lab-docker-prod-local/test/" --quiet
```

---

## Part F – Curation (concept; not licensed on this trial)

Curation decides at the door: when a developer or CI asks a **remote** repo for a package that
isn't cached yet, Curation checks it against policies first and refuses it (HTTP 403 with a reason)
if it's malicious, has a critical CVE with a fix, has a banned licence, and so on.

`terraform/jfrog/curation.tf` has four policies ready (block malicious, block CVSS 9+ with fix,
block PyPI CVSS 7+ with fix, dry-run for non-official images), switched off with
`enable_curation = false`. This trial reports:
```bash
curl -s -H "$H" "$JFROG_URL/catalog/api/v1/system/app_health" | jq .entitlements.entitled_for_catalog   # false
```
On an entitled instance: `terraform apply -var enable_curation=true`, then
`jf pip install urllib3==1.26.4` would be blocked by `lab-block-pypi-cvss7-with-fix`.

Know the difference for interviews:

| | Xray | Curation |
|---|---|---|
| When | after the artifact is stored or built | before a public package enters |
| Acts on | everything in Artifactory, builds, release bundles | remote repos only |
| Typical action | fail build, block download, violation | refuse the download |
| Rollout | policies + watches | **dry run first**, then block |

---

## Interview notes

- **Policies vs watches:** a policy is *what* and *which action*; a watch is *where*. Reuse
  policies across watches instead of copying rules.
- **Three intents:** gate (fail build), protect (block download in prod), track (violations for
  triage). Block only what's actionable.
- **Shift-left and shift-right:** Trivy in the PR is fast feedback; Xray keeps re-evaluating stored
  artifacts as new CVEs are published, so an image that was clean last month can raise a violation
  today, and the prod watch can block it.
- **Ignore rules are risk acceptances:** justification, owner, scope, expiry, reviewed in a PR.
- **Curation vs Xray:** Curation keeps bad packages out; Xray finds problems in what's already in.
  Roll out Curation in dry-run mode, measure, then block.
- **Licences:** licence policies route copyleft findings to legal review rather than blocking by
  default; the decision is legal's, not the pipeline's.

## Notes

_Your observations here._
