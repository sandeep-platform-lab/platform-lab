# Day 18 – Mock interview, whiteboard and logistics

**Goal:** perform under interview conditions: think aloud, draw clearly, stay calm when you don't know.

Time: about 2.5h, then stop. The evening before an interview is for rest, not new topics.

---

## Part A – Timed break-fix, out loud (about 45 min)

Three random scenarios, 15 minutes each. Record yourself on your phone, then listen back once.
```bash
scripts/breakfix.sh reset all
scripts/breakfix.sh random
```
Narrate every step: "Impact first: … The pod is Pending, so this is a scheduling decision; I'll read the
scheduler's reason … My hypothesis is … I'll validate it by … I'm changing one thing: … To prevent this: …"

Score yourself: did you state impact before touching anything? Did you change one thing at a time? Did you
name a prevention?

---

## Part B – Whiteboard (about 1h)

Face-to-face means a real whiteboard. Practise with pen and paper, standing up, 10 minutes each. Pick four
from the field guide's *Whiteboard exercises*; every drawing must show the items listed:

| Exercise | Must show |
|---|---|
| HA enterprise platform | zones, system/user pools, ingress, private API, identity (Entra/OAuth), GitOps, policy, monitoring, backup/DR, what happens when one zone dies |
| No-downtime node-pool upgrade | surge nodes, cordon/drain, PDB, readiness, replicas spread, stop criteria |
| Broken client → pod | every hop with the status code or test you'd use at that hop (from Day 15) |
| Multi-cluster policy governance | Git → Argo CD → Kyverno/VAP per cluster; Azure Policy assignment → AKS add-on → compliance; exceptions; audit → enforce waves |
| Operator loop | CR → API server → watch/informer cache → Reconcile → owned objects → status; requeue/backoff; finalizer |
| Team onboarding three ways | Ansible/AAP vs GitOps ApplicationSet vs Operator, with the trade-offs |

Tips: draw the boxes first and label later; say what you're drawing; leave space on the right for "what
can fail here"; ask "do you want me to go deeper on any part?" at the end.

---

## Part C – Mock interview (about 45 min)

Ask Claude for a mock interview in a new session, for example:
> "Interview me for a Kubernetes platform engineer role (OpenShift + AKS, AAP, Argo CD, GitLab, Prometheus).
> Two interviewers: a hands-on cloud engineer and the engineering head. 45 minutes, one question at a time,
> follow-ups on my answers, and feedback at the end."

Or rehearse alone from the field guide: 10 random questions, 2 minutes each, timer on.

---

## Part D – Logistics (15 min)

- Route and travel time to the office address on the invitation; plan to arrive 10–15 minutes early.
- Bring: ID, a printed copy of your CV, a pen, a notebook with your questions for them.
- Your 90-second introduction, said out loud twice.
- Stop studying by early evening. Sleep.

---

## Notes
