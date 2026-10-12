# Day 10 – Enterprise audit log to Azure, and Entra ID single sign-on

**Goal:** every security-relevant action in the GitHub enterprise is kept outside GitHub, tamper-
proof, in Switzerland; and access to the enterprise goes through the company identity provider.

Time: about 1.5h. Enterprise slug: `sandeep-platform-lab-ent`.

```
GitHub Enterprise ──(audit log stream, SAS: create+write only)──▶ stlabaudit<id>/github-audit
  (events)                                                          WORM 30 days, cool 30d, delete 180d
                                                                    ▲ read with Entra ID: scripts/audit-log-report.sh
Entra ID ──(SAML)──▶ GitHub Enterprise: owners and members sign in through Entra first
```

---

## Part A – Audit storage (about 10 min)

`terraform/azure-audit/` is permanent and separate from `terraform/azure`: audit evidence must
outlive the environments it describes. Read `main.tf` first: why WORM (immutability)? Why is a
Trivy finding (AZU-0012) accepted there, and where is that decision recorded?

```bash
cd ~/workspace/terraform/azure-audit
terraform init -backend-config=../backend.hcl
terraform apply -var subscription_id=$(az account show --query id -o tsv)    # 6 to add
```

---

## Part B – Stream the audit log (about 15 min)

1. A SAS for GitHub: create + write only, this container only, 30 days, and **revocable** through a
   stored access policy. The permissions and expiry go **in the SAS URL** (`sp=cw`, `se=…`); the policy
   is only there for revocation (`si=github-stream`). If the policy holds them instead, the URL has no
   `sp`/`se`, and GitHub's **Check endpoint** fails (that's what happened the first time).
   ```bash
   export AZURE_CORE_ONLY_SHOW_ERRORS=true
   SA=$(terraform output -raw storage_account); C=$(terraform output -raw container)
   EXP=$(date -u -v+30d +%Y-%m-%dT%H:%MZ)
   az storage container policy delete --account-name "$SA" -c "$C" -n github-stream --auth-mode key -o none
   az storage container policy create --account-name "$SA" -c "$C" -n github-stream --auth-mode key -o none
   SAS=$(az storage container generate-sas --account-name "$SA" -n "$C" --policy-name github-stream --permissions cw --expiry "$EXP" --https-only --auth-mode key -o tsv)
   echo "$SAS" | tr '&' '\n' | cut -d= -f1 | tr '\n' ' '; echo
   echo "https://$SA.blob.core.windows.net/$C?$SAS"
   ```
   The parameter list must include `sp` and `se`. (`AZURE_CORE_ONLY_SHOW_ERRORS` hides the CLI's
   "querying the account key" warnings. Commands here have no inline `#` comments: zsh doesn't
   accept them in pasted commands unless `setopt interactivecomments` is set.)
   The printed URL is a credential: paste it into GitHub in the next step, don't save it anywhere.
2. In GitHub: your enterprise → **Settings** → **Audit log** → **Log streaming** →
   **Configure stream** → **Azure Blob Storage**. Paste the URL, **Check endpoint**, **Save**.
   (GitHub's guide: https://docs.github.com/en/enterprise-cloud@latest/admin/monitoring-activity-in-your-enterprise/reviewing-audit-logs-for-your-enterprise/streaming-the-audit-log-for-your-enterprise)
3. Verify from the CLI, then clear the variable:
   ```bash
   gh api enterprises/sandeep-platform-lab-ent/audit-log/streams --jq '.[] | {stream_type, enabled, created_at}'
   unset SAS
   ```
4. To revoke GitHub's access later: `az storage container policy delete --account-name "$SA" -c "$C" -n github-stream --auth-mode key`.

---

## Part C – Read the logs from Azure (about 10 min)

Make something happen (e.g. change a team's description in the org), wait about 5 minutes, then:
```bash
cd ~/workspace && scripts/audit-log-report.sh
```
Try to delete a streamed blob (you have Reader only; even an Owner would be refused for 30 days):
```bash
B=$(az storage blob list --account-name "$SA" -c "$C" --auth-mode login --query "[0].name" -o tsv)
az storage blob delete --account-name "$SA" -c "$C" -n "$B" --auth-mode key
```
Expected: refused because of the immutability policy. That's the evidence an auditor wants.

---

## Part D – Entra ID SAML single sign-on (about 40 min)

Microsoft's step-by-step guide (values verified for this enterprise below):
https://learn.microsoft.com/en-us/entra/identity/saas-apps/github-enterprise-cloud-enterprise-account-tutorial

**Before you start:**
- In Entra, create a **cloud-only test user** (Entra ID → Users → New user), e.g. `githubadmin@<your-tenant>.onmicrosoft.com`.
  Your personal Microsoft account may not work as a SAML identity; a cloud user always does.
  You type its password yourself; don't share it.
- GitHub shows **SSO recovery codes** when you enable SAML. **Download them before saving.**
  They're how you get back in if the SAML configuration is wrong.

**Entra side** (Entra admin center → Enterprise apps → New application → gallery app
**"GitHub Enterprise Cloud - Enterprise Account"** → Single sign-on → SAML):

| Field | Value |
|---|---|
| Identifier (Entity ID) | `https://github.com/enterprises/sandeep-platform-lab-ent` |
| Reply URL | `https://github.com/enterprises/sandeep-platform-lab-ent/saml/consume` |
| Sign on URL | `https://github.com/enterprises/sandeep-platform-lab-ent/sso` |

Download **Certificate (Base64)**, copy **Login URL** and **Microsoft Entra Identifier**, and assign
the test user to the app (Users and groups).

**GitHub side** (enterprise → Settings → **Authentication security** → SAML single sign-on):
Sign on URL = Login URL, Issuer = Microsoft Entra Identifier, Public certificate = the certificate
file's contents. **Test SAML configuration**, sign in as the test user, then **Save**.

**What changes:**
- Opening the enterprise or the org now goes through Entra first. Your GitHub account gets a
  *linked external identity* (enterprise → People → your account → SAML identity).
- **The CLI token needs SSO authorization too.** If `gh api` or Terraform returns "Resource
  protected by … SAML enforcement", open `https://github.com/enterprises/sandeep-platform-lab-ent/sso`
  in the browser, then re-run `gh auth refresh -s admin:enterprise,read:audit_log`.
- GitHub Actions' own `GITHUB_TOKEN` isn't affected.

To undo: Authentication security → untick SAML → Save (recovery codes if you're locked out).

---

## Part E – Find it in the audit trail (about 5 min)

```bash
cd ~/workspace && scripts/audit-log-report.sh 100 | sed -n '/Policy, security/,$p'
```
Look for the SAML and streaming changes you made today: who, what, when, kept outside GitHub.

---

## Interview notes

- **Why stream the audit log:** GitHub keeps it for a limited time; regulators and security teams
  need it longer, in their own systems, correlated with other logs (SIEM: Microsoft Sentinel,
  Splunk). Blob Storage is cheap long-term retention; Event Hubs feeds a SIEM in near real time.
- **Tamper evidence:** immutable (WORM) storage with a locked retention policy, data in Switzerland,
  read access via Entra ID only. The writer (GitHub) can add but not change.
- **Least privilege for the writer:** a SAS with create+write only, on one container, with expiry,
  revocable through a stored access policy. Shared keys enabled only on this account, and why.
- **SAML vs EMU:** enterprise SAML with personal accounts links people's own GitHub accounts to the
  company identity; **Enterprise Managed Users** gives the company the accounts themselves (created
  and removed via SCIM, no public contributions). Many banks choose EMU with OIDC to get Entra
  Conditional Access as well.
- **Provisioning:** the enterprise-account SAML app doesn't support SCIM; for automatic joiner/
  leaver handling, use org-level SAML with SCIM, team sync with Entra groups, or EMU.
- **Break-glass:** recovery codes stored safely, more than one enterprise owner.

## Notes

_Your observations here._
