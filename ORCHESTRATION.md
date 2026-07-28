# Orchestration Design — CareGrid Health Partners Appointment Pipeline

**Tool:** Dagster  
**Schedule:** Daily at 06:00 UTC  
**Failure behaviour:** Halt all downstream assets on failure  

---

## Why Dagster

The appointment pipeline has an unusual requirement: `dim_flagged_dq` must rebuild daily while `dim_confirmed_dq` must never be rebuilt — only appended to. Dagster's asset-based model handles this cleanly by treating the two tables as separate assets with different materialisation strategies. Airflow could do this too but would require more custom operator logic.

---

## Schedule

```
Daily at 06:00 UTC
```

Rationale: CareGrid operates across 5 clinics. Running at 06:00 UTC means the COO and clinical operations team have fresh no-show data before morning huddles. The scheduling system updates overnight as appointments close out — a 06:00 run captures all prior-day outcomes. Billing claims post days to weeks later, so the billing freshness check uses a wider window than the scheduling check.

---

## Asset dependency graph

```
RAW_PATIENTS        RAW_DOCTORS         RAW_APPOINTMENTS    RAW_BILLING
    │                   │                       │               │
    ▼                   ▼                       ▼               ▼
stg_patients        stg_doctors         stg_appointments    stg_billing
    │                   │                       │               │
    └───────────────────┤                       │               │
                        ▼                       ▼               │
                int_appointment_facts ◄─── int_appointment_status
                        │                       │
                        │               int_reschedule_chains
                        │                       │
                        ◄───────────────────────┘
                        │
                        │               int_billing_signals ◄── stg_billing
                        │                       │
                        ◄───────────────────────┘
                        │
            ┌───────────┼────────────┬──────────────┐
            ▼           ▼            ▼              ▼
    fct_appointments  fct_no_show  dim_patient   dim_flagged_dq
                      _by_month    _engagement        │
            │                                         ▼
            └──────────────────────────────► dim_confirmed_dq
                                                      │
                                            reconciliation_bridge
```

**Execution order:**
1. All staging models run in parallel
2. `int_billing_signals` waits for `stg_billing`
3. `int_reschedule_chains` waits for `stg_appointments`
4. `int_appointment_status` waits for `stg_appointments` and `int_reschedule_chains`
5. `int_appointment_facts` waits for `int_appointment_status`, `int_billing_signals`, `stg_patients`, `stg_doctors`
6. `fct_appointments`, `fct_no_show_by_month`, `dim_patient_engagement`, `dim_flagged_dq` wait for `int_appointment_facts`
7. `dim_confirmed_dq` waits for `dim_flagged_dq` — append-only, never rebuilt
8. `reconciliation_bridge` waits for `fct_appointments` and `dim_flagged_dq`

---

## Freshness checks

| Source table | Freshness threshold | Action if stale |
|---|---|---|
| `RAW_APPOINTMENTS` | Max `booked_at` within last 25 hours | Error + halt |
| `RAW_PATIENTS` | Max `registered_at` within last 7 days | Warn only (master data) |
| `RAW_DOCTORS` | Max `hired_at` within last 7 days | Warn only (master data) |
| `RAW_BILLING` | Max `posted_at` within last 72 hours | Warn + continue |

`RAW_APPOINTMENTS` is the most critical — a stale scheduling feed means no-show rates are calculated against incomplete appointment data. If the scheduling system feed is stale, the pipeline halts.

`RAW_BILLING` uses a 72-hour threshold because claims post days to weeks late. A missed daily billing load is a warn, not a halt — it affects the billing hint in `dim_flagged_dq` but not the core no-show rate calculation.

---

## Failure behaviour

**Policy: halt all downstream assets on failure.**

Rationale: the reconciliation bridge is what the COO reads in the board presentation. If any upstream model fails, the bridge either fails itself or publishes incorrect rates. A wrong no-show rate used to justify an overbooking or reminder-text initiative is worse than no rate.

| Failure point | Downstream impact | Action |
|---|---|---|
| Any staging model fails | All dependent intermediates and marts skip | Alert + halt |
| `int_appointment_status` fails | `int_appointment_facts` and all marts skip | Alert + halt |
| `int_appointment_facts` fails | All mart models skip | Alert + halt |
| `fct_appointments` fails | `fct_no_show_by_month`, `dim_patient_engagement`, `dim_flagged_dq`, `reconciliation_bridge` skip | Alert + halt |
| `dim_flagged_dq` fails | `dim_confirmed_dq` skips | Alert + halt |
| `reconciliation_bridge` fails | No downstream impact | Alert only |
| DQ test fails (severity: error) | Pipeline halts before publishing mart | Alert + halt |

---

## Special asset: `dim_confirmed_dq`

`dim_confirmed_dq` is append-only — it must never be rebuilt from scratch. In Dagster this is handled by materialising it as an incremental asset that only inserts new rows where `is_reviewed = true` in `dim_flagged_dq`.

If `dim_confirmed_dq` is accidentally rebuilt from scratch, all human-confirmed resolutions are lost. The pipeline would need to be re-run with a backup of the confirmed data. This is the highest-risk asset in the pipeline — treat it accordingly.

**Protection:** `dim_confirmed_dq` should have a row-count check — if the new materialisation has fewer rows than the previous run, fail the asset and alert immediately. Never allow a rebuild to reduce the confirmed resolution count.

---

## Alerting

On any failure:
- Slack alert to `#data-ops` and `#clinical-ops` channels with asset name, failure reason, and Dagster run log link
- Email to the Data Lead and COO (no-show rate is board-level)
- Dagster run marked as failed

**Special alert — work queue growth:** if `dim_flagged_dq` row count grows by more than 50 rows in a single daily run, trigger an additional Slack alert to `#data-ops`. This signals a front-desk keying problem that needs operational intervention, not just data engineering.

---

## Re-run story

The pipeline is fully idempotent for all models except `dim_confirmed_dq`.

**For all other models:**
- All staging models are views — always reflect current raw data
- Intermediate models are ephemeral — recompiled fresh on every run
- Mart tables use `CREATE OR REPLACE` — re-running overwrites previous output cleanly
- Same seed always produces identical raw data

**For `dim_confirmed_dq`:**
- Never re-run from scratch
- If a failure occurs mid-run after `dim_confirmed_dq` has been updated, restore from the pre-run backup
- Re-run all models upstream of `dim_confirmed_dq` only — do not re-materialise `dim_confirmed_dq` itself

---

## DQ test severity framework

| Test | Severity | Failure behaviour |
|---|---|---|
| `unique` on `appointment_id` in `fct_appointments` | Error | Halt pipeline |
| `unique` on `patient_id` in `stg_patients` | Error | Halt pipeline |
| `unique` on `doctor_id` in `stg_doctors` | Error | Halt pipeline |
| `not_null` on `final_status` | Error | Halt pipeline |
| `accepted_values` on `final_status` | Error | Halt pipeline |
| `not_null` on `appointment_id` in `dim_flagged_dq` | Error | Halt pipeline |
| `referential integrity` patient_id | Error | Halt pipeline |
| `assert_reschedule_origins_not_in_denominator` | Error | Halt pipeline |
| `assert_true_no_show_has_no_reschedule_link` | Error | Halt pipeline |
| `assert_flagged_dq_count_ties_out` | Error | Halt pipeline |

All business-rule tests are error severity. A reschedule origin appearing in the intended visits denominator, or a true no-show with a reschedule link, means the classification logic has broken — the no-show rate is wrong and the pipeline must halt.

---

## Stretch goal: running DAG

```python
from dagster import Definitions, ScheduleDefinition
from dagster_dbt import DbtCliResource, dbt_assets, DbtProject

dbt_project = DbtProject(project_dir="dbt_starter")

@dbt_assets(manifest=dbt_project.manifest_path)
def caregrid_dbt_assets(context, dbt: DbtCliResource):
    yield from dbt.cli(["run", "--exclude", "dim_confirmed_dq"], context=context).stream()
    yield from dbt.cli(["run", "--select", "dim_confirmed_dq", "--vars", '{"incremental_strategy": "append"}'], context=context).stream()
    yield from dbt.cli(["test"], context=context).stream()

daily_schedule = ScheduleDefinition(
    job=caregrid_dbt_assets,
    cron_schedule="0 6 * * *"
)

defs = Definitions(
    assets=[caregrid_dbt_assets],
    schedules=[daily_schedule],
    resources={"dbt": DbtCliResource(project_dir="dbt_starter")}
)
```

The key design point: `dim_confirmed_dq` is excluded from the main run and handled separately with an append-only strategy. In production this would use dbt incremental materialisation with `unique_key = appointment_id` and `incremental_strategy = append`.
