# Day 11 – Copilot administration and GitHub Advanced Security

**Goal:** run Copilot like a platform team would (who gets a seat, what it may do, what it must
never see, what it costs, whether it's used) and close the remaining Advanced Security gaps.
Also: the JFrog trial ends today, and the pipeline must keep working without it.

Time: about 1.5h.

---

## Part A – Life after the JFrog trial (about 10 min)

`supply-chain.yml` now treats JFrog as optional. With the repository variable `JFROG_URL` set, it
works as before. Without it, the `build` job builds and scans the image from Docker Hub and skips
push, Xray, SBOM upload and signing (a notice in the run says so). When the trial has ended:
```bash
gh variable delete JFROG_URL -R sandeep-platform-lab/platform-lab
```
Also expected after the trial: `promote.yml` and `terraform/jfrog` stop working, and pods on k3d that
need a new pull from JFrog can't start (Kyverno can't fetch signatures either). Stop the local cluster
when you don't need it: `k3d cluster stop lab`.

---

## Part B – Copilot administration (about 50 min)

> **Trial limitation (found 14 Oct):** turning on Copilot Business in the enterprise fails with
> *"GitHub Copilot Business requires a paid enterprise account"*. The Enterprise Cloud trial doesn't
> include Copilot. Options were: upgrade the enterprise (expensive), buy one Business seat in a
> separate org outside the enterprise (about USD 19), or **use Copilot Free on a personal account for
> the developer side and learn the admin side from the API and docs. Chosen: the free route.**
> Steps 2, 3, 5 and 6 below need Copilot Business; read them as "what I would do", and run
> `scripts/copilot-admin.sh status` and `metrics` to see the real API responses on this account.
> With a paid org: `ORG=<org> scripts/copilot-admin.sh …` works unchanged.

**Developer side (Copilot Free):** github.com → your avatar → **Copilot settings**. In VS Code with
the GitHub Copilot extension: try completions and chat on `app/src/main.py`, and notice what an
admin would want to control (which models, public-code matching, what gets sent).


```bash
cd ~/workspace && scripts/copilot-admin.sh status
```
Today: plan **business**, seat management **unconfigured**, no seats.

1. **Enterprise policies.** Enterprise → **AI controls** → **Copilot** (the name GitHub's docs use; it
   may also appear as **Policies → Copilot**). For each policy, decide what a bank would choose and why:
   - **Suggestions matching public code:** Block (licence and IP risk) or Allow with references.
   - **Copilot usage metrics:** set to **Enabled everywhere**. Without it, the metrics API refuses:
     "The 'Copilot usage metrics' policy must be enabled to use this API".
   - Copilot in the CLI, the coding agent, MCP servers, which models are allowed, preview features.
2. **Seat management.** Organization **Settings → Copilot → Access**: choose **Selected members**.
   Assign by **team**, so joiners and leavers are handled by team membership (and, with SSO and team
   sync, by Entra ID groups):
   ```bash
   scripts/copilot-admin.sh assign-team platform-team
   scripts/copilot-admin.sh seats
   ```
   **Cost:** Copilot Business is about **USD 19 per seat per month**. Before assigning, check the
   enterprise's **Billing** page for whether the trial covers Copilot. A removed seat stays as
   "pending cancellation" until the end of the billing cycle, so expect to pay for up to one month.
3. **Use it once** (VS Code with the GitHub Copilot extension, signed in with your GitHub account) so
   your seat shows activity. Then `scripts/copilot-admin.sh seats` shows *last active* and the editor.
4. **Content exclusion.** Organization **Settings → Copilot → Content exclusion**, paste:
   ```yaml
   platform-lab:
     - "**/.env"
     - "*.tfstate"
     - "*.tfstate.*"
     - "/PLAN.local.md"
     - "/jfrog-selfhosted/**"
   ```
   In VS Code, open `.env`: no suggestions. (Changes can take up to 30 minutes to reach an open IDE;
   **Developer: Reload Window** applies them sooner.) Important limitation from GitHub's docs: the
   **Copilot CLI and agent mode in IDE chat don't honour content exclusion**. Exclusion is a hygiene
   control, not a security boundary: secrets still belong in a vault, not in files.
5. **Cost hygiene:**
   ```bash
   scripts/copilot-admin.sh inactive 30
   scripts/copilot-admin.sh metrics
   ```
6. **Clean up** if you don't want to keep paying: `scripts/copilot-admin.sh remove-team platform-team`.

---

## Part C – Advanced Security: close the gaps (about 30 min)

Already on: secret scanning with push protection and validity checks, CodeQL default setup (the
`Analyze (actions)` and `Analyze (python)` checks on every PR), Dependabot alerts, and your own
Trivy, Semgrep and Gitleaks results in the Security tab.

1. **Dependabot security updates** (PRs that fix vulnerable dependencies automatically):
   ```bash
   gh api -X PUT repos/sandeep-platform-lab/platform-lab/automated-security-fixes
   gh api repos/sandeep-platform-lab/platform-lab --jq '.security_and_analysis.dependabot_security_updates.status'
   ```
2. **Dependabot version updates** (`.github/dependabot.yml`, added today): weekly PRs that keep the
   action SHAs, Python packages and Terraform providers current. They go through the same checks and
   ruleset as any other PR. That's the answer to "who keeps all those pins up to date?".
3. **Dependency review** (new `dependency-review` job in `supply-chain.yml`, PRs only): blocks PRs
   that *add* dependencies with HIGH/CRITICAL vulnerabilities or a GPL/AGPL licence. Test it:
   ```bash
   git switch main && git pull && git switch -c test-dependency-review
   echo "urllib3==1.26.4" >> app/requirements.txt
   git commit -am "test: vulnerable dependency" && git push -u origin test-dependency-review
   gh pr create --base main --title "test: dependency review" --body "Day 11 exercise"
   ```
   Which fails first, `dependency-review` or `scan`? Read the job summary: vulnerabilities, licence,
   and the OpenSSF Scorecard of the new package. Then:
   `gh pr close test-dependency-review --delete-branch; git switch main; git branch -D test-dependency-review`.
4. **Security overview:** organization → **Security** tab. One view across repositories and tools.
5. Optional: make `dependency-review` a required check (`terraform/github/ruleset.tf`, same pattern as Day 4).

---

## Interview notes

- **Copilot governance:** seats by team (ideally IdP groups), cost reviewed monthly with
  last-activity data, inactive seats reclaimed; policies set at the enterprise (public code filter,
  CLI, agent, MCP, models); usage metrics for adoption and ROI; Copilot events in the audit log.
- **Content exclusion is not a security boundary:** some surfaces (CLI, agent mode) ignore it.
  Keep secrets out of repos and files in the first place.
- **Copilot Business/Enterprise data handling:** prompts and code aren't used to train models;
  know where to point legal and security teams (GitHub's Copilot Trust Center).
- **Advanced Security products:** *Secret Protection* (secret scanning, push protection, validity
  checks) and *Code Security* (CodeQL, dependency review, security overview). Free on public repos,
  licensed per active committer on private ones.
- **Three Dependabots:** alerts (you're affected), security updates (PR that fixes it), version
  updates (stay current). Plus **dependency review** to stop new problems entering in a PR.
- **One pane of glass:** SARIF from third-party scanners (Trivy, Semgrep, Gitleaks) lands next to
  CodeQL in the Security tab and the security overview.

## Notes

_Your observations here._
