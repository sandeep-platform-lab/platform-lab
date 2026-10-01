# Day 2 – GitHub org governance

**Goal:** the lab repo is governed like a bank repo. Teams own code, `main` only changes through
reviewed PRs with green CI, and the rules are written as code.

Time: about 1.5h. Part A in the GitHub UI, Part B with Terraform, Part C your first protected PR.

---

## Part A – UI (about 25 min)

Org: https://github.com/organizations/sandeep-platform-lab/settings

1. **Member privileges** (Settings → Member privileges)
   - Base permissions: **No permission**. Access comes from teams, never by default.
   - Repository creation: untick **Public** and **Private**. Repos are created by the platform team.
   - Repository forking: **off**. Forks copy code out of governance.
   - Note what each setting would mean in a bank, in the Notes section below.
2. **Authentication security**: tick **Require two-factor authentication** for all members.
   Turn on 2FA on your own account first, or GitHub refuses.
3. **Code security** (Settings → Code security → Configurations): look at
   **GitHub recommended**. Which features are free for public repos? Apply it to `platform-lab`.
4. **Create one team by hand**: Teams → New team → name `platform-team`, visibility **Visible**.
   This is the "ClickOps" that Part B adopts into Terraform.

---

## Part B – Terraform (about 35 min)

Code: `terraform/github/`

| File | What it manages |
|---|---|
| `teams.tf` | `platform-team`, `app-team`, `security-team`, your maintainer membership, each team's repo permission |
| `ruleset.tf` | `main-protection` ruleset on the default branch |
| `import.tf` | Adopts the `platform-team` you created in Part A |

```bash
cd terraform/github
export GITHUB_TOKEN=$(gh auth token)
terraform init
terraform plan
```

Read the plan before applying:
- `platform-team` should say **will be imported**, not "will be created". Why does that matter?
- How many resources will be created? Why does each team appear three times?

```bash
terraform apply
```

Then:
1. Delete `import.tf`, run `terraform plan` again: it should say **No changes**.
2. Drift test: in the UI, change `app-team`'s repo permission to **Admin**. Run `terraform plan`.
   What does Terraform want to do? Apply to put it back.
3. Look at the ruleset in the UI: repo → Settings → Rules → Rulesets → `main-protection`.
   Find the bypass list and the required check `build-test`.

---

## Part C – First protected change (about 25 min)

Everything for today sits on the local branch `day02-github-governance`.

1. Try to break the rules first:
   ```bash
   git switch main
   git commit --allow-empty -m "direct push test"
   git push
   ```
   The push is **rejected**. Read the message, then undo: `git reset --hard origin/main`.
2. Push the branch and open the PR:
   ```bash
   git switch day02-github-governance
   git push -u origin day02-github-governance
   gh pr create --fill
   ```
3. On the PR page, check:
   - **Checks**: `build-test` runs. Open the logs.
   - **Reviewers**: which teams were requested automatically, and why? (Hint: CODEOWNERS.)
   - **Merge box**: merging is blocked until there's an approval. As org admin you see
     "Merge without waiting for requirements to be met (bypass rules)". That's the bypass list in action.
4. Merge with the bypass, choosing **Squash and merge**. Then update locally:
   ```bash
   git switch main && git pull
   ```
5. Find the bypass in the audit log: Org settings → Logs → Audit log, search `action:repository_ruleset`.

---

## Interview notes

- **Branch protection vs rulesets:** rulesets can apply to many repos and branches at once (org-wide
  with Enterprise), they stack, they have an *evaluate* mode for dry runs, and they have an explicit
  bypass list. Branch protection rules are per branch and per repo.
- **Why `integration_id` on the required check?** Without it, anything with write access could post a
  commit status called `build-test` and fake a green build. Pinning it to the GitHub Actions app
  stops that.
- **Why "No permission" base permissions?** Least privilege and auditability. Access is granted
  through teams, which map to Entra ID groups once SSO and team sync exist (Enterprise day).
- **ClickOps → code:** `import` blocks adopt existing resources without recreating them. That's how
  you bring an org that grew by hand under Terraform safely.
- **Separation of duties (FINMA-style):** the author can't approve their own PR, and changes to
  CODEOWNERS need security review. Bypasses are rare, named, and visible in the audit log.

## Notes

_Your observations here._
