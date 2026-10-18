# Day 12 – Golden developer image as code (Packer → Azure Compute Gallery)

**Why this instead of Dev Box:** Microsoft stopped accepting new Dev Box customers on 1 Nov 2025
(Azure product page) and is moving its capabilities into Windows 365. What stays the platform
team's job either way is the **image factory**: a versioned, tested, traceable developer image,
built as code and consumed by whatever provisions the machines (Dev Box pools, Windows 365
provisioning policies, Azure Virtual Desktop, plain VMs).

Time: about 1.5h, mostly waiting for the build. Cost: a few CHF (a B2ms Windows VM for under an
hour, plus a small image snapshot; delete versions when done).

```
images/dev-workstation/              terraform/azure-images/
  dev-workstation.pkr.hcl  ──packer build──▶  gal_platformlab / dev-workstation-ws2025
  scripts/install-dev-tools.ps1                ├─ 1.0.0   ← each build = new immutable version
                                               └─ 1.0.1      consumers pin a version or use "latest"
```

---

## Part A – Read, then create the gallery (about 15 min)

Questions from the code:
1. Why is the image **generalized** (`specialized = false`, sysprep) rather than a copy of one VM?
2. Why Windows Server 2025 here, and what changes for a Windows 11 Dev Box / Windows 365 image?
   (Licensing: Windows client in Azure needs an eligible licence.)
3. What does the manifest at `C:\ProgramData\platformlab\image-manifest.json` give an auditor?
4. Where would packages come from in a bank, and why? (Look at the comment in the install script.)

```bash
cd ~/workspace/terraform/azure-images
terraform init -backend-config=../backend.hcl
terraform apply -var subscription_id=$(az account show --query id -o tsv)
```
Expected: 3 to add (resource group, gallery, image definition with security type **TrustedLaunch**).

**Lesson from the first build (18 Oct):** the definition was first created as `TrustedLaunchSupported`.
The build ran 16 minutes and then failed at capture: *"contains TrustedLaunch … security data that
cannot be used in image with 'TrustedLaunchSupported' security type"*. A disk from a Trusted Launch
VM carries vTPM state, so the definition must be `TrustedLaunch` (`trusted_launch_enabled = true`).
Changing it replaces the definition, so a failed version must be deleted first:
`az sig image-version delete -g rg-platform-lab-images -r gal_platformlab -i dev-workstation-ws2025 -e 1.0.0`.

---

## Part B – Build version 1.0.0 (about 45 min, mostly waiting)

```bash
cd ~/workspace/images/dev-workstation
packer init .
packer build -var subscription_id=$(az account show --query id -o tsv) -var image_version=1.0.0 .
```
Watch what Packer does: temporary resource group → Trusted Launch VM → WinRM → install tools →
restart → sysprep → capture into the gallery → delete everything temporary. The install step prints
the manifest at the end.

```bash
az sig image-version list -g rg-platform-lab-images -r gal_platformlab -i dev-workstation-ws2025 \
  --query "[].{version:name, state:provisioningState, regions:publishingProfile.targetRegions[].name}" -o table
```

---

## Part C – Prove it works: a VM from the image (about 20 min)

No RDP and no public IP needed: `run-command` executes inside the VM through the Azure agent.
```bash
IMG=$(az sig image-definition show -g rg-platform-lab-images -r gal_platformlab -i dev-workstation-ws2025 --query id -o tsv)
az group create -n rg-platform-lab-imgtest -l switzerlandnorth --tags project=platform-lab -o none
az vm create -g rg-platform-lab-imgtest -n vm-devtest --image "$IMG/versions/1.0.0" \
  --size Standard_B2ms --security-type TrustedLaunch --enable-secure-boot true --enable-vtpm true \
  --admin-username labadmin --admin-password "$(openssl rand -base64 24)Aa1!" \
  --public-ip-address "" --nsg-rule NONE -o none
az vm run-command invoke -g rg-platform-lab-imgtest -n vm-devtest --command-id RunPowerShellScript \
  --scripts 'Get-Content C:\ProgramData\platformlab\image-manifest.json; git --version; terraform version; az version -o tsv' \
  --query "value[0].message" -o tsv
```
The generated admin password is never shown or stored: nobody needs it, which is the point.

Clean up the test VM straight away:
```bash
az group delete -n rg-platform-lab-imgtest --yes --no-wait
```

---

## Part D – Release 1.0.1 and roll back (about 20 min)

1. Change the image: add `'nodejs-lts'` to `$packages` in `scripts/install-dev-tools.ps1`, commit.
2. Build `-var image_version=1.0.1`. The gallery now has two versions; `versions/latest` means 1.0.1.
3. **Rollback** = consumers pin `versions/1.0.0` (or you exclude 1.0.1 from latest):
   ```bash
   az sig image-version update -g rg-platform-lab-images -r gal_platformlab -i dev-workstation-ws2025 \
     -e 1.0.1 --set publishingProfile.excludeFromLatest=true
   ```

---

## Part E – Clean up the cost (about 5 min)

Each version is a stored snapshot (a few CHF a month). Keep the gallery and definition (free), delete
versions you don't need:
```bash
for v in 1.0.0 1.0.1; do az sig image-version delete -g rg-platform-lab-images -r gal_platformlab -i dev-workstation-ws2025 -e $v; done
```

---

## Also new today: `terraform-validate` in CI

Dependabot PR #24 moved the Azure provider from **4.x to 5.9** (a major version) and was merged. The
live audit stack was fine, but the AKS stack no longer validated: 5.x removed `service_endpoints` on
subnets (now a `service_endpoint` block) and requires a `node_provisioning_profile` on AKS. Nothing
in CI ran `terraform validate`, so the break would only have shown up at the next AKS session.
`ci.yml` now validates every stack under `terraform/` on every PR, so a Dependabot bump that breaks
Terraform fails before merge. Optional: make `terraform-validate` a required check (`ruleset.tf`).

---

## Interview notes

- **Image factory:** images as code (Packer or Azure Image Builder), versioned in Azure Compute
  Gallery, rebuilt on a schedule (monthly patch cycle) and on change, scanned, tested, then rolled
  out in rings (pilot pool → everyone). Rollback = previous version.
- **Generalized vs specialized:** generalized (sysprep) images give every machine its own identity;
  specialized images are copies of one machine.
- **Trusted Launch** (secure boot, vTPM) for the build VM and every machine from the image.
- **Supply chain applies to images too:** packages from an internal, scanned mirror; versions pinned;
  a manifest per version; the image itself scanned (e.g. Defender for Cloud) before release.
- **Dependabot needs a safety net:** automated updates are only safe if CI tests what they change
  (here: `terraform validate` per stack). Major versions deserve a human read of the changelog.

## Notes

_Your observations here._
