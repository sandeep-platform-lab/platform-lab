# Day 4 – Supply-chain pipeline

**Goal:** every change to `lab-api` is scanned, built from an approved base image, pushed to JFrog
with full traceability, documented with an SBOM, and cryptographically signed, with no secrets
stored in GitHub.

Time: 5–6h. Workflow: `.github/workflows/supply-chain.yml`

```
            PR and main                                     main only
┌──────────────────────────────┐   ┌─────────────────────────────────────────────────────────┐
│ scan                         │   │ build                                                   │
│  Gitleaks  (secrets, history)│   │  OIDC → JFrog token (5 min)                             │
│  Semgrep   (code, workflows) │──▶│  build (base image via lab-docker) → Trivy image gate   │
│  Trivy fs  (deps, IaC)       │   │  ── main ──▶ jf docker push + build-info                │
│  SARIF → Security tab        │   │             Syft SBOM → lab-generic-evidence-local      │
└──────────────────────────────┘   │             cosign sign + attest SBOM → verify          │
                                   └─────────────────────────────────────────────────────────┘
```

**Gate policy:** fail on secrets, Semgrep ERROR findings, and **fixable** HIGH/CRITICAL
vulnerabilities. Unfixable base-image CVEs don't block (nothing to do yet); Xray tracks them (Day 5).

---

## Part A – Read before you run (about 45 min)

Open `supply-chain.yml` and find the answers:

1. Every `uses:` is pinned to a 40-character SHA. Why is `@v4` dangerous?
   (Look up the March 2025 `tj-actions/changed-files` incident.)
2. Which job has `id-token: write`, and why does only that job need it?
3. Why does the Docker login step pass the token via `env:` instead of writing
   `${{ steps.jfrog.outputs.oidc-token }}` directly in `run:`? (Hint: script injection.)
4. `Scan image` uses `--ignore-unfixed`. What would happen to every build if it didn't?
5. On a PR, the build job logs in to JFrog too. Which group does it get, and could it push?
   (Look at `terraform/jfrog/oidc.tf`.)

What changed in `app/Dockerfile` today and why:
- **pip removed from the runtime image.** Trivy found 4 fixable HIGH CVEs in packages *vendored
  inside pip* (`pip/_vendor`: msgpack, setuptools, urllib3). The app never runs pip, so removing it
  removed the vulnerabilities and the attack surface. Fixable findings went from 6 to 0.
- **`HEALTHCHECK` added** (Trivy misconfiguration DS-0026).
- **`BASE_IMAGE` build arg**, so CI pulls `python:3.14-slim` through Artifactory, not Docker Hub.

---

## Part B – First run (about 1h)

1. Tell the workflow where JFrog is. This is a repository *variable*, not a secret: the URL isn't
   sensitive, and there's no token to store at all.
   ```bash
   cd ~/workspace && set -a; source ~/workspace/.env; set +a
   gh variable set JFROG_URL --body "$JFROG_URL"
   ```
2. Push the branch and open the PR:
   ```bash
   git push -u origin day04-supply-chain
   gh pr create --title "Supply-chain pipeline: scan, build, SBOM, sign" --fill
   ```
3. Watch the run: `gh run watch`, or the Actions tab.
   - `scan`: all three scanners, results uploaded.
   - `build`: OIDC login, image built and scanned, **nothing published** (it's a PR).
4. In JFrog, open the OIDC setup: Administration → **General Management → Manage Integrations**
   → **OpenID Connect** tab. Open `github-actions` and its two identity mappings. Which one matched for the PR run?
   The UI doesn't log the match, so reason it out: a PR run's `ref` claim is
   `refs/pull/<n>/merge`, not `refs/heads/main`, so priority 1 (`platform-lab-main`) doesn't match
   and priority 2 (`platform-lab-other`) does. Result: a 5-minute token for `lab-ci-readonly`.
   You'll see the other side in Part D, when the `main` run is allowed to push.
5. Security tab → **Code scanning**: results from Gitleaks, Semgrep and Trivy (if any).

---

## Part C – Break it on purpose (about 1h)

Do each on a throwaway branch, watch it fail, then close the PR and delete the branch.

1. **Vulnerable dependency.** Add `urllib3==1.26.4` to `app/requirements.txt`, push, open a PR.
   Which scanner fails first: Trivy fs in `scan`, or the image scan?
2. **Leaked secret.** Add a file with a fake GitHub token, e.g.
   `TOKEN=ghp_` followed by 36 random letters and digits, and push.
   **GitHub push protection may reject the push before CI even runs** (you enabled it on Day 2).
   That's the first layer. Bypass it for the exercise ("it's a test value"), open a PR, and
   Gitleaks fails in CI: the second layer.
   Then delete the file in a *new* commit and push again: **it still fails.** Why?
   (The secret is in history. Real fix: revoke the token first, then rewrite history.)
3. **Insecure workflow.** In a workflow, add a step `run: echo "${{ github.event.pull_request.title }}"`.
   What does Semgrep say? Why is that exploitable?

```bash
gh pr close <number> --delete-branch
```

---

## Part D – Merge and verify the release (about 1.5h)

1. Merge the Day 4 PR (Squash and merge, admin bypass). The `main` run publishes.
2. JFrog UI:
   - **Artifactory → Builds → `lab-api`**: the build-info. Find the git commit, the environment,
     the image layers, and the SBOM as an artifact of the build.
   - **`lab-docker-dev-local/lab-api`**: tag `1.0.<run>`, plus `sha256-….sig` and `sha256-….att`.
     Those are the signature and the SBOM attestation, stored next to the image.
   - **`lab-generic-evidence-local/lab-api/<run>/sbom.spdx.json`**
3. Verify the signature yourself. Anyone with read access can do this; no keys are needed:
   ```bash
   set -a; source ~/workspace/.env; set +a; REG=${JFROG_URL#https://}
   echo "$JFROG_ACCESS_TOKEN" | docker login "$REG" -u "$JFROG_USER" --password-stdin
   IMG="$REG/lab-docker/lab-api:1.0.<run number>"
   cosign verify "$IMG" \
     --certificate-identity "https://github.com/sandeep-platform-lab/platform-lab/.github/workflows/supply-chain.yml@refs/heads/main" \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com | jq '.[0].optional'
   ```
   Then try it with `@refs/heads/some-branch` as the identity. It fails. That's the point: only
   `main` of this repo can produce a valid signature.
4. Read the SBOM attestation:
   ```bash
   cosign verify-attestation "$IMG" --type spdxjson \
     --certificate-identity "https://github.com/sandeep-platform-lab/platform-lab/.github/workflows/supply-chain.yml@refs/heads/main" \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com \
     | jq -r '.payload' | base64 -d | jq '.predicate.packages | length'
   ```
5. **Make the new checks required.** In `terraform/github/ruleset.tf`, add `scan` and `build` as
   `required_check` blocks (same `integration_id`), run `terraform apply`, and open a PR to see them
   listed as required.

---

## Interview notes

- **Supply-chain security in one sentence:** prove what's in the artifact (SBOM), where it came
  from (build-info, provenance), that it wasn't tampered with (signature), and that it passed policy
  (scan gates), from commit to cluster.
- **OIDC over stored credentials:** the JFrog token lives 5 minutes, its rights depend on the
  branch, and there's nothing to rotate or leak. The same pattern works for Azure (federated
  credentials) on the Azure day.
- **Keyless signing (Sigstore):** no private key to protect. The certificate binds the signature
  to the workflow identity, and the transparency log (Rekor) makes every signature publicly
  auditable. Verification policy says *who* may sign, not *which key*.
- **Shift left, but gate sensibly:** blocking on unfixable CVEs teaches people to ignore the gate.
  Block on what's actionable, track the rest, and set SLAs by severity.
- **Pin everything:** actions by SHA, scanner images by version, base images via the internal
  registry. Renovate or Dependabot keeps the pins current.
- **SBOM uses:** answering "are we affected by CVE-X?" across all images in minutes, licence
  compliance, and regulatory asks (EU Cyber Resilience Act, US EO 14028).

## Notes

_Your observations here._
