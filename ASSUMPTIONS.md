# Assumptions & tradeoffs log
**Project 05 — Healthcare Appointment Analytics | CareGrid Health Partners**

All positions were taken before touching the data. Each assumption is logged with the rationale and the risk of being wrong. These are the decisions I would defend in front of the VP of Clinical Operations and the Director of Revenue Cycle.

---

## Assumption 1 — What counts as a no-show?

**Position:** Chain-resolved. A true no-show is a visit where the patient did not attend AND did not reschedule. If a slot has both `STATUS = rescheduled` and `RESCHEDULED_TO_ID` populated, it is classified as rescheduled — not a no-show. Rescheduled visits are tracked separately with their own count.

**Rationale:** Separates genuinely missed visits from moved ones. Directly addresses the VP of Clinical Operations' complaint that rescheduled visits inflate the no-show rate. A patient who moved their appointment has not missed it — the chair gets filled later.

**Risk if wrong:** If `RESCHEDULED_TO_ID` links are unreliable (the Data Lead flagged this), some rescheduled visits may be misclassified as true no-shows. A DQ test validates the link integrity and mismatch rate. If the mismatch rate is high, the COO needs to understand the true no-show rate carries that uncertainty.

**Date logged:** Project start

---

## Assumption 2 — What is the denominator?

**Position:** All intended visits — slots where the terminal status is not a cancellation AND the slot is not a confirmed reschedule original. Logic works backwards from terminal status: include attended, no_show, and reschedule chain targets. Exclude cancelled slots and confirmed reschedule originals.

**Rationale:** If a slot wasn't cancelled and wasn't the confirmed origin of a reschedule chain, the patient intended to attend it. This is the only defensible denominator given the data available — there is no forward-looking intent signal, only terminal status.

**Risk if wrong:** If `CANCEL_REASON` is keyed inconsistently across locations, some clinic-initiated cancellations may enter the denominator incorrectly. A DQ test monitors `CANCEL_REASON` null rate. The `cancelled_unknown` category surfaces slots where the reason is missing.

**Date logged:** Project start

---

## Assumption 3 — How should rescheduled appointments be tracked?

**Position:** Require both signals. A slot is classified as a reschedule original only if `STATUS = rescheduled` AND `RESCHEDULED_TO_ID` is populated. The chain target owns the attendance outcome. Slots where only one signal is present are classified as `flagged_dq` and surfaced in the human review work queue.

**Rationale:** Most conservative classification. Only collapses the reschedule chain when both the status field and the link column agree. Mismatches surface data quality problems at the front desk rather than silently resolving them incorrectly.

**Risk if wrong:** If the Data Lead is right that link columns are unreliable, a meaningful share of rescheduled visits may fail the both-signals test and enter `flagged_dq`. The reconciliation bridge reports the mismatch count so the COO understands the scale of the problem.

**Date logged:** Project start

---

## Assumption 4 — How do you reconcile status flags across locations?

**Position:** Canonical status map applied in staging:

| Raw status | Canonical status |
|---|---|
| `attended` | `attended` |
| `no_show`, `missed`, `no-show` | `no_show` |
| `cancelled` + `CANCEL_REASON = patient_request` | `cancelled_patient` |
| `cancelled` + `CANCEL_REASON` in (`clinic_cancelled`, `provider_unavailable`, `weather`) | `cancelled_clinic` |
| `cancelled` + null `CANCEL_REASON` | `cancelled_unknown` |
| `rescheduled` + `RESCHEDULED_TO_ID` populated | `rescheduled` |
| `rescheduled` + null `RESCHEDULED_TO_ID` | `flagged_dq` |
| Any other combination | `flagged_dq` |

`flagged_dq` slots are excluded from all rate calculations and surfaced in the human review work queue (`dim_flagged_dq`). The work queue rebuilds daily.

**Rationale:** Normalises formatting inconsistencies across locations (`no_show` vs `missed` vs `no-show`). Splits cancellations by reason so clinic-initiated cancellations don't inflate the patient no-show rate. Parks ambiguous reschedule slots in a visible DQ category rather than silently resolving them.

**Risk if wrong:** If `CANCEL_REASON` is frequently null, the patient/clinic cancellation split will be unreliable — `cancelled_unknown` will be large. If `flagged_dq` volume grows, the reconciliation bridge must show what the no-show rate would be under worst-case assumption (all flagged = no-show).

**Date logged:** Project start

---

## Assumption 5 — Can billing be trusted as an attendance signal?

**Position:** Corroborate only — billing never auto-overrides scheduling status. `flagged_dq` slots surface in `dim_flagged_dq` (the daily work queue) with full billing context: `has_office_visit_charge` Y/N, `has_no_show_fee` Y/N, `has_late_cancel_fee` Y/N, and a `billing_hint` label. Human-confirmed resolutions are recorded in `dim_confirmed_dq` with `confirmed_status`, `confirmed_by`, `confirmed_at`, and `billing_signal_used`. The fact model merges confirmed statuses on every daily run. `dim_flagged_dq` rebuilds daily showing the current unresolved backlog. `dim_confirmed_dq` is append-only — confirmations persist across runs. The no-show rate improves incrementally as the queue is worked down.

**Rationale:** Billing claims post days to weeks after service — sometimes in a different month. Automated overrides based on billing would introduce timing errors. Healthcare data accuracy has compliance implications. Human review with a full audit trail is the defensible approach. The `billing_hint` gives reviewers a signal without forcing an automated decision.

**Risk if wrong:** If `flagged_dq` volume is high and the review queue is not worked, appointments remain excluded from rate calculations indefinitely. This is an operational commitment, not just a data engineering deliverable. The COO must understand that the no-show rate will only be fully accurate when the queue reaches zero.

**Date logged:** Project start

---

## Reconciliation summary

The five assumptions above produce the following no-show rates from the same underlying data:

| Rate | Value | Denominator | Policy |
|---|---|---|---|
| Ops dashboard (raw) | 19.39% | All slots | `no_show` + `missed` + `no-show` / total |
| True no-show rate | 14.72% | Intended visits | Chain-resolved misses / intended visits |
| Worst case | 14.77% | Intended + flagged | All flagged_dq counted as no-show |

**Gap breakdown:**
- 6.93 percentage points — misflagged reschedules (rescheduled visits keyed as no_show)
- 2.47 percentage points — misflagged cancellations (cancelled visits keyed as no_show)
- 0.04 percentage points — flagged_dq slots (minimal — only 30 unresolved)
- **Total gap: 4.67 percentage points**

The gap is almost entirely explained by front-desk keying inconsistency — not data quality defects in the pipeline. The fix is operational (standardise front-desk training across locations), not technical.

---

## DQ work queue design

**`dim_flagged_dq`** — daily work queue (rebuilds each run):
- All slots that failed the both-signals test
- Full billing context, visit details, reschedule link context
- `billing_hint` label for reviewer guidance
- `dq_reason` classifying why the slot was flagged

**`dim_confirmed_dq`** — permanent audit trail (append-only):
- Human-confirmed resolutions only
- `confirmed_status`, `confirmed_by`, `confirmed_at`, `billing_signal_used`
- Fact model joins this on every run — confirmed statuses replace `flagged_dq` classification
