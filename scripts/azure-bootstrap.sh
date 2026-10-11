#!/usr/bin/env bash
# Creates the lab resource group, a monthly subscription budget with email alerts, and the
# storage account that holds Terraform state for every stack (terraform/backend.hcl).
# Idempotent: safe to re-run. Requires `az login`.
set -euo pipefail

RG=rg-platform-lab
LOCATION=switzerlandnorth
BUDGET=budget-platform-lab
AMOUNT=${AMOUNT:-50}   # in the subscription's billing currency

SUB=$(az account show --query id -o tsv)
EMAIL=$(az account show --query user.name -o tsv)

az group create -n "$RG" -l "$LOCATION" --tags project=platform-lab owner="$USER" -o none

body=$(cat <<EOF
{
  "properties": {
    "category": "Cost",
    "amount": $AMOUNT,
    "timeGrain": "Monthly",
    "timePeriod": { "startDate": "2026-09-01T00:00:00Z", "endDate": "2027-09-30T00:00:00Z" },
    "notifications": {
      "actual50":    { "enabled": true, "operator": "GreaterThanOrEqualTo", "threshold": 50,  "thresholdType": "Actual",     "contactEmails": ["$EMAIL"] },
      "actual80":    { "enabled": true, "operator": "GreaterThanOrEqualTo", "threshold": 80,  "thresholdType": "Actual",     "contactEmails": ["$EMAIL"] },
      "actual100":   { "enabled": true, "operator": "GreaterThanOrEqualTo", "threshold": 100, "thresholdType": "Actual",     "contactEmails": ["$EMAIL"] },
      "forecast100": { "enabled": true, "operator": "GreaterThanOrEqualTo", "threshold": 100, "thresholdType": "Forecasted", "contactEmails": ["$EMAIL"] }
    }
  }
}
EOF
)

az rest --method put \
  --url "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Consumption/budgets/$BUDGET?api-version=2023-05-01" \
  --body "$body" -o none

echo "Resource group $RG ($LOCATION) and budget $BUDGET ($AMOUNT/month) ready."

# ---------- Terraform state ----------
# Entra ID auth only (no shared keys), TLS 1.2+, no anonymous access, versioning + soft delete so a
# bad apply or a deleted state file can be recovered.
SUFFIX=$(printf '%s' "$SUB" | shasum -a 1 | cut -c1-6)   # same suffix Terraform uses
SA="stplatformlab${SUFFIX}"
CONTAINER=tfstate
ME=$(az ad signed-in-user show --query id -o tsv)

az storage account create -n "$SA" -g "$RG" -l "$LOCATION" --sku Standard_ZRS --kind StorageV2 \
  --min-tls-version TLS1_2 --allow-blob-public-access false --allow-shared-key-access false \
  --tags project=platform-lab -o none
az storage account blob-service-properties update -n "$SA" -g "$RG" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 14 \
  --enable-container-delete-retention true --container-delete-retention-days 14 -o none
az role assignment create --assignee-object-id "$ME" --assignee-principal-type User \
  --role "Storage Blob Data Contributor" \
  --scope "$(az storage account show -n "$SA" -g "$RG" --query id -o tsv)" -o none 2>/dev/null || true
# Data-plane RBAC can take a minute to apply.
for i in $(seq 1 12); do
  az storage container create -n "$CONTAINER" --account-name "$SA" --auth-mode login -o none 2>/dev/null && break
  sleep 10
done

cat > "$(dirname "$0")/../terraform/backend.hcl" <<HCL
# Shared Terraform backend (created by scripts/azure-bootstrap.sh). Each stack sets its own key.
resource_group_name  = "$RG"
storage_account_name = "$SA"
container_name       = "$CONTAINER"
use_azuread_auth     = true
HCL
echo "Terraform state: $SA/$CONTAINER (terraform/backend.hcl written)"
