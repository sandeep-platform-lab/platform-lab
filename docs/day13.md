# Day 13 – Developer workplace: Dev Box → Windows 365 (concepts and interview practice)

No hands-on today: Dev Box doesn't accept new customers (since 1 Nov 2025), and Windows 365 needs a
separate Microsoft 365 tenant with Intune and per-user licences. Instead: learn the model well
enough to discuss it, map it to what you built on Day 12, and rehearse answers.

Time: about 1.5h. Read Microsoft's docs, then answer the questions below in your own words.
- Dev Box: https://learn.microsoft.com/azure/dev-box/
- Windows 365: https://learn.microsoft.com/windows-365/
- Dev Box product page (availability note): https://azure.microsoft.com/products/dev-box

Where the docs and this page differ, the docs win: the services are changing.

---

## Part A – The Dev Box model (about 30 min)

Find in the docs and write one sentence each:

| Concept | Question to answer |
|---|---|
| **Dev center** | What does it hold, and who manages it (platform team or project team)? |
| **Project** | How does it separate teams, budgets and permissions? |
| **Network connection** | Microsoft-hosted network vs your own VNet (Azure network connection). When do you need your own? (Hint: on-prem access, hybrid join.) |
| **Dev box definition** | Image + compute size + storage. Where does the image come from? (Marketplace or *Azure Compute Gallery*, which is Day 12.) |
| **Dev box pool** | Definition + network + region + schedule. Why several pools per project? |
| **Schedules / hibernation** | How do auto-stop and hibernation control cost? |
| **Roles** | DevCenter Project Admin vs Dev Box User: who can create pools, who can create boxes? |
| **Customizations** | Team/user customizations from a catalog (YAML tasks). How does that compare to baking tools into the image? |
| **Management** | Intune: compliance, configuration, patching of the boxes. |

---

## Part B – Where it's going: Windows 365 (about 20 min)

From Microsoft's announcements (check the docs for the current state):
- Dev Box's developer capabilities move into **Windows 365**; licensing sources mention
  **Windows 365 Frontline** for the developer scenarios.
- Look up: Windows 365 **Enterprise vs Frontline** (dedicated vs shared/shift licensing),
  **provisioning policies** (image + network + join type + region), **custom images**
  (requirements: Windows 11 Enterprise, generalized, Gen2; how they're imported), and how
  Intune assigns policies to Cloud PCs.
- Question: what of your Day 12 pipeline carries over unchanged, and what changes?
  (Expected: the image factory carries over; the OS must be Windows 11 Enterprise with eligible
  licences; provisioning moves from dev box pools to provisioning policies.)

---

## Part C – Rehearse (about 40 min)

Answer out loud, 1–2 minutes each, then write the short version in Notes:

1. "We want developers productive on day one, on locked-down bank laptops. How would you do it?"
   (Cloud dev workstations, golden images with the toolchain, network to internal resources,
   self-service within guardrails, cost controls.)
2. "How do you keep 300 developer machines patched and consistent?"
   (Image factory with monthly rebuilds, version rollout in rings, Intune for config and compliance,
   rollback by pinning the previous version.)
3. "Dev Box is being retired. What would you recommend to a company that's on it?"
   (Inventory pools/definitions/images, map to Windows 365 provisioning policies, keep the image
   pipeline, pilot with one team, plan before the retirement date, licence review.)
4. "Where do developer tools come from on those machines?"
   (Internal mirror such as Artifactory with Xray, pinned versions, a manifest per image version.)
5. "How do you control cost?"
   (Auto-stop and hibernation schedules, right-sized definitions, per-project budgets, tags,
   reclaiming unused machines, the same thinking as Copilot seats on Day 11.)

---

## Interview notes

- Know the **status**: Dev Box closed to new customers on 1 Nov 2025; capabilities moving to
  Windows 365. Saying this confidently (and that you checked) is a strong signal.
- The durable skills are the same either way: **image factory**, **network design to internal
  resources**, **identity and Intune**, **self-service with guardrails**, **cost control**.

## Notes

_Your observations here._
