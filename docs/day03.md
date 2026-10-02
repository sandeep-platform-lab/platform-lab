# Day 3 – JFrog Artifactory administration

**Goal:** the JFrog Cloud instance is organised like an enterprise setup: a Project, a repository
naming convention, local/remote/virtual repos, role-based groups and permissions, and OIDC trust for
GitHub Actions, all as Terraform. Plus one hour running Artifactory yourself.

Time: 5–6h. Part A setup, Part B Terraform, Part C using it, Part D self-hosted operations.

---

## Part A – Access and first look (about 30 min)

1. **Create an admin access token** in the JFrog UI:
   Administration → User Management → Access Tokens → **Generate token**
   - Token scope: **Admin**, Expiration: **30 days**, Description: `terraform-lab`
   - Copy it once. Don't paste it into the chat.
2. Put it in the git-ignored `.env` at the repo root (`JFROG_ACCESS_TOKEN=...`), then load it:
   ```bash
   cd ~/workspace
   set -a; source .env; set +a
   jf config add lab --url "$JFROG_URL" --access-token "$JFROG_ACCESS_TOKEN" --interactive=false
   jf rt ping            # expect: OK
   ```
3. Look around before automating anything:
   - Administration → **Subscription/License**: is Xray included? Curation?
   - Administration → Repositories: what exists by default?
   - Administration → Platform Security → **OIDC Integration**: empty for now.
   - Which **environments** exist (Administration → Projects → Environments)? DEV and PROD are global defaults.

---

## Part B – Terraform (about 2h)

Code: `terraform/jfrog/`

| File | What it manages |
|---|---|
| `repositories.tf` | 8 repos following `<project>-<type>-<maturity>-<locator>` |
| `access.tf` | 5 groups and 5 permissions (who may read, push, promote, administer) |
| `project.tf` | JFrog Project `lab` with its repos and group roles |
| `oidc.tf` | Trust for GitHub Actions: `main` may push, everything else is read-only |

```
             lab-docker (virtual)            lab-pypi (virtual)
              /            \                   /           \
 lab-docker-dev-local  lab-docker-remote   lab-pypi-local  lab-pypi-remote
                       (Docker Hub)                        (pypi.org)
 lab-docker-prod-local   ← only promotion writes here
 lab-generic-evidence-local   ← SBOMs, scan reports
```

```bash
cd terraform/jfrog
terraform init
terraform plan
```

Before you apply, answer from the plan:
- Why does `lab-ci` get **WRITE** on the *remote* repos? (Hint: what happens the first time
  someone pulls an image that isn't cached yet?)
- Which group can write to `lab-docker-prod-local`? Which can't? Why does that matter for an auditor?
- In `oidc.tf`, what decides whether a workflow run gets `lab-ci` or `lab-ci-readonly`?

```bash
terraform apply
```

Check in the UI: Projects → **Platform Lab** → repositories, members, roles.

---

## Part C – Use it (about 1.5h)

Set a helper variable for the registry host:
```bash
REG=${JFROG_URL#https://}
```

1. **Pull through the remote** (Docker Hub cached in JFrog):
   ```bash
   echo "$JFROG_ACCESS_TOKEN" | docker login "$REG" -u <your JFrog username> --password-stdin
   docker pull "$REG/lab-docker/library/python:3.14-slim"
   ```
   Find it in the UI under `lab-docker-remote-cache`. Pull it a second time: why is it faster,
   and why does that matter when Docker Hub rate-limits you?
2. **Push your own image** through the virtual repo (lands in dev):
   ```bash
   docker build -t "$REG/lab-docker/lab-api:manual-1" app
   docker push "$REG/lab-docker/lab-api:manual-1"
   ```
   Which physical repo did it land in? (Hint: `default_deployment_repo`.)
3. **Python packages through Artifactory**:
   ```bash
   jf pipc --repo-resolve lab-pypi --global=false
   python3 -m venv /tmp/labvenv && source /tmp/labvenv/bin/activate
   jf pip install -r app/requirements.txt
   deactivate
   ```
   Look at `lab-pypi-remote-cache`: FastAPI and its dependencies are now cached.
4. **Prove least privilege.** Make a short-lived token that only has developer rights, then try to push:
   ```bash
   DEV_TOKEN=$(jf atc --groups lab-developers --expiry 900 | jq -r .access_token)
   echo "$DEV_TOKEN" | docker login "$REG" -u <your JFrog username> --password-stdin
   docker push "$REG/lab-docker/lab-api:manual-1"     # expect: denied
   echo "$JFROG_ACCESS_TOKEN" | docker login "$REG" -u <your JFrog username> --password-stdin   # back to admin
   ```
5. **AQL**, the query language behind cleanup and audits:
   ```bash
   jf rt curl -XPOST /api/search/aql -H "Content-Type: text/plain" \
     -d 'items.find({"repo":{"$match":"lab-*"}}).include("repo","path","name","size","created")'
   ```
   Change it to find only items larger than 10 MB (`"size":{"$gt":10000000}`).
6. **Drift**: in the UI, change the description of `lab-pypi-local`. Run `terraform plan`. Apply to revert.

---

## Part D – Self-hosted operations (about 1h)

Artifactory OSS on your Mac with PostgreSQL (`jfrog-selfhosted/`). OSS has Maven, Gradle and
generic repos; Docker, npm and PyPI need a paid edition. That's fine for today: the point is operations.

```bash
cd ~/workspace/jfrog-selfhosted
./setup.sh                 # creates .env with a random DB password (once)
docker compose up -d
```

Wait about 90 seconds, then open http://localhost:8082. First login: `admin` / `password`.
Change it immediately and skip the onboarding wizard.

Explore and note the answers:
1. **Health**: `curl -s localhost:8082/router/api/v1/system/health | jq` – what are the services
   (jfrt, jfac, jfmd, …) and what does each do?
2. **Config**: `docker compose exec artifactory cat /opt/jfrog/artifactory/var/etc/system.yaml`.
   The database section is commented out, but it uses PostgreSQL. Why? (Look at `compose.yaml`.)
3. **Logs**: `docker compose exec artifactory ls /opt/jfrog/artifactory/var/log`. Which log would you
   check for (a) a failed login, (b) a slow download, (c) who deleted an artifact?
4. **Storage**: upload a file to `example-repo-local` twice under different names, then look in
   `/opt/jfrog/artifactory/var/data/artifactory/filestore`. How many copies are stored? (Checksum-based storage.)
5. **Backups**: Administration → Artifactory → Backups. What does the default system backup include?
   In production, would you rely on it or on database + filestore snapshots?
6. **Upgrade**: how would you upgrade? (Set `ARTIFACTORY_VERSION`, `docker compose up -d`, watch logs.)
   What would you do first in production?

Finish with `docker compose stop` to free about 4 GB of RAM.

---

## Interview notes

- **Local / remote / virtual:** local holds what you build, remote proxies and caches a public registry
  (speed, resilience, rate limits, a single point to scan and block), virtual gives clients one URL
  and lets you change what's behind it without touching every pipeline.
- **Naming convention** (`team-tech-maturity-locator`) makes permissions, cleanup and Xray watches
  work by pattern instead of by hand.
- **Dev → prod by promotion, not rebuild:** the exact bytes that were tested move to prod; only the
  release group can write to prod, and CI can't. That's separation of duties.
- **OIDC instead of stored tokens:** nothing long-lived to leak or rotate; the claims (repo, branch)
  decide the rights, and every token expires in 5 minutes.
- **SaaS vs self-hosted:** SaaS removes DB, filestore, HA, upgrades and backups from your plate;
  self-hosted gives control over data residency and network, which Swiss banks often require.
  Know both.

## Notes

_Your observations here._
