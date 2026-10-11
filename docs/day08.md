# Day 8 – Azure landing zone and AKS with Terraform

**Goal:** a small but production-shaped Azure setup in Switzerland North, all as code: remote
state, guardrails, logging, secrets, a locked-down AKS cluster, and an app that reads a Key Vault
secret without any secret stored in Kubernetes or GitHub. Created and destroyed the same day.

Time: 5–6h. Cost: under CHF 5 (free AKS control plane, 2 × B2ms for a few hours, a load balancer).

```
rg-platform-lab (permanent)                rg-platformlab-aks (today, terraform/azure)
├─ budget 50/month + alerts                ├─ Azure Policy: CH locations only (Deny), inherit 'project' tag (Modify),
└─ stplatformlab<id>/tfstate               │                AKS local accounts disabled (Audit)
     ├─ github.tfstate                     ├─ vnet-platformlab 10.40.0.0/16 ─ snet-aks-nodes 10.40.0.0/22
     ├─ jfrog.tfstate                      ├─ log-platformlab (30 days, 0.5 GB/day cap)
     └─ azure.tfstate                      ├─ kv-platformlab-<id> (RBAC) ─ secret lab-api-greeting
                                           ├─ aks-platformlab: Entra ID + Azure RBAC, no local accounts,
                                           │    CNI Overlay + Cilium, OIDC issuer, workload identity, KV CSI
                                           └─ id-lab-api ──federated──▶ k8s SA lab/lab-api ──▶ reads the secret
```

---

## Part A – Remote state (about 45 min)

Terraform state for GitHub and JFrog is on your laptop: lose the laptop, lose the state, and the
state contains sensitive values. Move it to Azure Storage with Entra ID auth (no account keys).

```bash
cd ~/workspace
scripts/azure-bootstrap.sh          # idempotent: RG + budget as before, plus the state account
cat terraform/backend.hcl
```

Migrate both existing stacks (Terraform copies the state for you):
```bash
cd ~/workspace/terraform/github && terraform init -backend-config=../backend.hcl -migrate-state
cd ~/workspace/terraform/jfrog  && terraform init -backend-config=../backend.hcl -migrate-state
```
Answer **yes** when asked to copy existing state. Then prove it worked:
```bash
export GITHUB_TOKEN=$(gh auth token); cd ~/workspace/terraform/github && terraform plan   # No changes
set -a; source ~/workspace/.env; set +a; cd ../jfrog && terraform plan                     # No changes
az storage blob list --account-name "$(awk -F'"' '/storage_account_name/{print $2}' ../backend.hcl)" \
  -c tfstate --auth-mode login --query "[].name" -o tsv
```
When both plans say **No changes**, delete the local copies: `rm terraform.tfstate*` in both folders.

Questions: why `--allow-shared-key-access false`? What do versioning and soft delete protect against?
Who can read this state, and what's in it? (Hint: `terraform state pull | grep -i token`.)

---

## Part B – Read, then apply the landing zone and AKS (about 1h30, mostly waiting)

Read `terraform/azure/*.tf` first:
1. `policy.tf`: why is the tag policy **Modify** (inherit from the RG) instead of **Deny**?
   (Hint: what does the AKS monitoring add-on create, and does it carry your tags?)
2. `aks.tf`: why a *user-assigned* control-plane identity with Network Contributor on the subnet?
3. `local_account_disabled = true`: how will you run `kubectl` at all?
4. `network_plugin_mode = "overlay"`: why is the node subnet only a /22?

```bash
cd ~/workspace/terraform/azure
terraform init -backend-config=../backend.hcl
terraform plan -var subscription_id=$(az account show --query id -o tsv)    # 20 to add
terraform apply -var subscription_id=$(az account show --query id -o tsv)   # ~10 minutes for AKS
```

Get credentials (Entra ID login through kubelogin; there's no admin certificate to download):
```bash
eval "$(terraform output -raw kubeconfig_command)"
kubectl get nodes -o wide
kubectl config current-context        # aks-platformlab
```

Check the guardrails:
```bash
RG=$(terraform output -raw resource_group)
az group show -n $RG --query tags
# Deny: try to create something outside Switzerland
az network public-ip create -g $RG -n pip-test -l westeurope --sku Standard 2>&1 | grep -iE "disallowed|policy" | head -2
# Modify: a resource created without tags gets 'project' anyway
az network public-ip create -g $RG -n pip-test2 -l switzerlandnorth --sku Standard --query "publicIp.tags" -o json
az network public-ip delete -g $RG -n pip-test2
```

---

## Part C – Workload identity end to end (about 1h)

The app's Kubernetes service account `lab/lab-api` is trusted by the Entra identity `id-lab-api`
(federated credential), which may read secrets in the vault (Key Vault Secrets User). The pod gets
a short-lived Entra token; the CSI driver uses it to mount the secret.

```bash
cd ~/workspace && scripts/aks-deploy.sh
```
Expected at the end:
```
== Secret read through workload identity (no secret in the cluster's config):
Hello from Azure Key Vault, delivered by workload identity
== Injected by the workload identity webhook:
AZURE_CLIENT_ID  AZURE_TENANT_ID  AZURE_FEDERATED_TOKEN_FILE  AZURE_AUTHORITY_HOST
```
Then:
1. `kubectl -n lab get secret` lists only `jfrog-pull`: the Key Vault secret isn't a Kubernetes secret.
2. Change the secret, and watch it rotate inside the pod within about 2 minutes:
   ```bash
   KV=$(terraform -chdir=terraform/azure output -raw key_vault_name)
   az keyvault secret set --vault-name $KV -n lab-api-greeting --value "rotated $(date +%H:%M)" -o none
   kubectl -n lab exec deploy/lab-api -- cat /mnt/secrets/lab-api-greeting
   ```
3. Break the trust on purpose: in `identity.tf`, change the subject to `system:serviceaccount:lab:other`,
   `terraform apply`, then `kubectl -n lab rollout restart deploy/lab-api`. The new pods can't mount the
   secret (`kubectl -n lab describe pod` shows the token exchange error). Revert and apply.
4. `kubectl -n lab port-forward svc/lab-api 8085:80` and `curl -s localhost:8085/api/info`: same
   signed image from JFrog prod, now running in Switzerland North.
5. Container Insights: Azure portal → the cluster → Monitoring → Insights (data appears after ~10 min).

---

## Part D – Destroy and check (about 20 min)

```bash
cd ~/workspace/terraform/azure
terraform destroy -var subscription_id=$(az account show --query id -o tsv)
az group exists -n rg-platformlab-aks          # false
az group exists -n rg-platformlab-aks-nodes    # false (AKS removes its node RG)
az group exists -n rg-platform-lab             # true: budget and state stay
kubectl config use-context k3d-lab             # back to the local cluster
```
Check spend tomorrow (cost data lags by up to a day): Azure portal → Cost Management → Cost analysis,
filter tag `project = platform-lab`.

---

## Interview notes

- **Remote state:** shared, locked (blob leases), versioned, Entra-authenticated; state can contain
  secrets, so access to it is access to them.
- **Landing zone thinking:** guardrails (policy) at the highest sensible scope (management groups in
  real life), network and identity first, workloads in their own resource groups, tags for cost.
- **Policy effects:** Deny for hard rules (data residency), Modify/Append for hygiene (tags),
  Audit for things you measure first, DeployIfNotExists for auto-remediation (e.g. diagnostics).
- **AKS hardening:** Entra ID + Azure RBAC, local accounts off, managed identities, workload
  identity, private cluster / API server authorized IPs (not done here), Azure CNI Overlay to save
  VNet space, automatic patch upgrades and node image updates, Container Insights.
- **Workload identity vs secrets:** no client secret to store or rotate; trust is scoped to one
  service account in one namespace on one cluster (issuer + subject); tokens are short-lived.
- **Cost discipline:** Free tier control plane for non-prod, B-series nodes, Log Analytics daily
  cap, destroy what you don't need, budgets with alerts, tags for showback.

## Notes

_Your observations here._
