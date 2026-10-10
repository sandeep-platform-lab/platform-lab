# Day 6 – Artifactory housekeeping

**Goal:** storage and cost stay under control automatically, without ever deleting a release or
audit evidence, and every deletion is previewed, recoverable and explainable.

Time: 3–4h. Code: `terraform/jfrog/housekeeping.tf`, `scripts/housekeeping-report.sh`.

| Content | Rule | Why |
|---|---|---|
| Dev images | keep newest 10 versions per image | untested builds pile up fast |
| Remote caches | drop if not downloaded for 60 days (remote repo setting, not a policy) | can always be fetched again |
| Internal PyPI | keep newest 5 versions per package | |
| Prod images, evidence | **never** cleaned automatically | releases and audit evidence |
| Anything with `retention.keep=true` | never deleted | how a release is pinned |

---

## Part A – Preview before you delete (about 45 min)

```bash
cd ~/workspace && set -a; source ~/workspace/.env; set +a
scripts/housekeeping-report.sh
```

Read the output and `housekeeping.tf`, then answer:
1. Why are cleanup policies **created disabled**, and why does Terraform `ignore_changes = [enabled]`?
2. Remote caches aren't in a cleanup policy: policies only accept **local** repos (we found out
   when `terraform apply` failed with "Specified repo does not exist: lab-docker-remote"). How are
   they cleaned instead? (Look for `unused_artifacts_cleanup_period_hours` in `repositories.tf`.)
3. The report shows `.sig` and `.att` tags. What happens to an image's signature if a "keep newest
   10" rule counts signature tags as versions? (Real gotcha: signatures stored as tags compete with
   images for retention slots. OCI 1.1 *referrers* fix this by attaching them to the image instead.)
4. Some dev "tags" are `sha256:…` digests, not version tags. Where do they come from?
   (Hint: what does `cosign` push, and what does a manifest list contain?)

The report is built on **AQL**, the same query language the cleanup engine uses. Try a query, and
notice what it actually measures:
```bash
jf rt curl -s -XPOST /api/search/aql -H "Content-Type: text/plain" \
  -d 'items.find({"repo":"lab-docker-dev-local","size":{"$gt":50000000}}).include("path","name","size")' \
  | jq '.range.total'
```
**0 results**, even though some images are over 50 MB. AQL returns *items* (files), and a Docker tag
is a folder of layer files plus `manifest.json`; no single layer is over 50 MB. To size an image,
sum its files per folder, which is what the report's "larger than N MB" section does:
```bash
scripts/housekeeping-report.sh 10 60 40     # keep 10, unused 60 days, images over 40 MB
```
Two more things the report surfaces:
- **`_uploads`**: leftovers from interrupted pushes. Pure clutter, and a good cleanup candidate.
- Per-image sizes **overstate disk use**: layers shared between tags are stored once (Day 3).

---

## Part B – Apply and pin a release (about 45 min)

```bash
cd ~/workspace/terraform/jfrog
terraform plan     # 2 cleanup policies + the remote repos' cleanup period
terraform apply
```

Pin the newest image so no policy can ever remove it:
```bash
RUN=$(gh run list -R sandeep-platform-lab/platform-lab --workflow supply-chain.yml --branch main \
      --status success --limit 1 --json number --jq '.[0].number')
jf rt set-props "lab-docker-dev-local/lab-api/1.0.$RUN/" "retention.keep=true"
~/workspace/scripts/housekeeping-report.sh | sed -n '/Pinned/,/^$/p'
```

---

## Part C – Run a policy (about 45 min)

1. In the JFrog UI, find **Cleanup Policies** (use the Administration search box; menu names vary
   between versions). You'll see the two `lab-*` policies, both inactive.
2. Open `lab-dev-docker-keep-10` and use **Run Now** (or activate it and wait for Saturday).
3. Run the report again: `lab-api` should be down to 10 tags, and the pinned tag still there.
4. Look in the **Trash Can** (Artifactory → Artifacts → Trash Can): the deleted tags are there.
   Restore one. That's why `skip_trashcan = false` for anything you might need back.
5. `terraform plan`: still **No changes**, even if you activated the policy. That's the
   `ignore_changes` at work.

---

## Part D – Build-info retention (about 30 min)

Build-info records are small, but they hold references, and every build keeps its artifacts
"interesting". Keep the last few, plus anything released:
```bash
jf rt build-discard lab-api --max-builds=5 --async=false
curl -s -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" "$JFROG_URL/artifactory/api/build/lab-api" \
  | jq '[.buildsNumbers[].uri] | length'
```
In a real pipeline this runs in CI right after `build-publish`, with `--exclude-builds` for released
builds, using a dedicated group that has DELETE on builds (`lab-ci` deliberately doesn't).

---

## Part E – Disk space comes back later (self-hosted, optional, about 30 min)

Deleting doesn't free disk immediately (Day 3: checksum-based storage). On your self-hosted instance:
```bash
cd ~/workspace/jfrog-selfhosted && docker compose start
# wait until healthy, then:
curl -u admin -X POST http://localhost:8082/artifactory/api/system/storage/gc
docker compose exec artifactory grep -i "garbage" /opt/jfrog/artifactory/var/log/artifactory-service.log | tail -3
docker compose stop
```
Order of events: delete → trash can (retention period) → emptied → binary unreferenced →
**garbage collection** removes it from the filestore. In JFrog Cloud, GC is run for you.

---

## Interview notes

- **Retention is a policy decision, not a script:** agree rules per maturity (dev short, prod and
  evidence long, regulated retention for audit), write them as code, review them in PRs.
- **Preview, then enforce:** AQL report or dry run first, disabled by default, trash can as a
  safety net. Same pattern as Curation's dry-run mode.
- **Pin releases** with a property (`retention.keep=true`) rather than excluding repos by hand.
- **What housekeeping covers:** cleanup policies, Docker tag limits (`max_unique_tags`), remote
  cache expiry, build-info retention, trash can, garbage collection, storage reports. Monitor the
  storage trend so cleanup is planned, not an emergency.
- **Gotchas:** signatures and attestations stored as tags; digest-only manifests; deleting
  doesn't free disk until GC; a build-info can keep artifacts "referenced".

## Notes

_Your observations here._
