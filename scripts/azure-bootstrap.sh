#!/usr/bin/env bash
# Creates the lab resource group and a monthly subscription budget with email alerts.
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
