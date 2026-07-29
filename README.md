The problem

CareGrid's COO had a no-show rate problem — but more precisely, a measurement problem. One dashboard said 22%. The clinical team said closer to 12%. The Patient Access Manager admitted front desks across five locations key statuses inconsistently. Rescheduled visits get marked as no-shows. Cancellations get the same treatment. Before spending a dollar on reminder texts or overbooking, the COO needed one number they could trust.

This project builds the pipeline to produce that number — and to explain exactly why the two dashboards disagreed.


What I built

DeliverableStatusAssumptions & tradeoffs log✅ CompleteData generator (Snowflake sandbox)✅ Completedbt project (staging → intermediate → marts)✅ CompleteAppointment fact model with canonical status✅ CompleteNo-show rate by month, location, specialty✅ CompletePatient engagement mart with risk signal✅ CompleteDQ work queue (dim_flagged_dq)✅ CompleteHuman review audit trail (dim_confirmed_dq)✅ CompleteReconciliation bridge (22% → 14.72%)✅ CompleteData quality framework (16 tests, 3 business-rule)✅ CompleteOrchestration DAG design (Dagster)✅ CompleteArchitecture diagram⬜ In progressPresentation deck⬜ In progress


The numbers

RateValuePolicyOps dashboard rate19.39%Raw no_show + missed + no-show / all slotsTrue no-show rate14.72%Chain-resolved misses / intended visitsWorst case rate14.77%All flagged_dq counted as no-show

Gap breakdown:


6.93 pts — misflagged reschedules (rescheduled visits keyed as no_show by front desk)
2.47 pts — misflagged cancellations (cancelled visits keyed as no_show)
0.04 pts — flagged_dq (only 30 unresolved slots)
Total gap: 4.67 percentage points


The gap is almost entirely explained by front-desk keying inconsistency across locations — not a data pipeline problem. The fix is operational.


Stack


Warehouse: Snowflake
Transformation: dbt Core 1.10
Orchestration: Dagster (design)
Language: Python, SQL
Testing: dbt tests + 3 custom business-rule tests
Source data: Seed-deterministic generator, 12k patients, 80 providers, 70,280 appointments, 48,487 billing lines



The five definitional questions I had to answer

1. What counts as a no-show?
Chain-resolved. A true no-show is a visit where the patient did not attend AND did not reschedule. If a slot has both STATUS = rescheduled and RESCHEDULED_TO_ID populated, it is classified as rescheduled — not a no-show.

2. What is the denominator?
All intended visits — slots where the terminal status is not a cancellation and the slot is not a confirmed reschedule original. Logic works backwards from terminal status, not forward from predicted intent.

3. How should rescheduled appointments be tracked?
Require both signals. A slot is a reschedule original only if STATUS = rescheduled AND RESCHEDULED_TO_ID is populated. Slots where only one signal is present go to flagged_dq for human review.

4. How do you reconcile status flags across locations?
Canonical status map: no_show + missed + no-show → no_show · cancelled split by CANCEL_REASON → cancelled_patient or cancelled_clinic · rescheduled with both signals → rescheduled · ambiguous cases → flagged_dq.

5. Can billing be trusted as an attendance signal?
Corroborate only — never auto-override. flagged_dq slots surface in a daily work queue with billing context (office_visit charge Y/N, no_show_fee Y/N) as a human review aid. Human confirmations recorded in dim_confirmed_dq with full audit trail.

Full log: ASSUMPTIONS.md


Model structure

dbt_starter/
├── models/
│   ├── staging/
│   │   ├── stg_appointments.sql
│   │   ├── stg_patients.sql
│   │   ├── stg_doctors.sql
│   │   └── stg_billing.sql
│   ├── intermediate/
│   │   ├── int_billing_signals.sql
│   │   ├── int_reschedule_chains.sql
│   │   ├── int_appointment_status.sql
│   │   └── int_appointment_facts.sql
│   └── marts/
│       ├── fct_appointments.sql
│       ├── fct_no_show_by_month.sql
│       ├── dim_patient_engagement.sql
│       ├── dim_flagged_dq.sql
│       ├── dim_confirmed_dq.sql
│       ├── reconciliation_bridge.sql
│       ├── schema.yml
│       └── staging/schema.yml
├── tests/
│   ├── assert_reschedule_origins_not_in_denominator.sql
│   ├── assert_true_no_show_has_no_reschedule_link.sql
│   └── assert_flagged_dq_count_ties_out.sql
└── dbt_project.yml


The DQ work queue pattern

This project introduced a two-table DQ pattern for ambiguous appointments:

dim_flagged_dq — daily work queue (rebuilds each run):


Slots where the reschedule status and link column don't agree
Full billing context, visit details, billing_hint label for reviewer
Clears as humans confirm resolutions


dim_confirmed_dq — permanent audit trail (append-only):


Human-confirmed resolutions with confirmed_status, confirmed_by, confirmed_at
Fact model merges these on every run — rate improves as queue is worked down
Never rebuilt — only appended to



Data quality tests

TestTypeSeverityappointment_id unique + not nullGenericErrorpatient_id unique + not nullGenericErrordoctor_id unique + not nullGenericErrorfinal_status not nullGenericErrorfinal_status accepted valuesGenericErrorappointment_id not null in dim_flagged_dqGenericErrorpatient_id not null + unique in dim_patient_engagementGenericErrorReferential integrity patient_idGenericErrorassert_reschedule_origins_not_in_denominatorBusiness ruleErrorassert_true_no_show_has_no_reschedule_linkBusiness ruleErrorassert_flagged_dq_count_ties_outBusiness ruleError



Docs


ASSUMPTIONS.md — all five definitional positions with rationale and risk
ORCHESTRATION.md — Dagster DAG design, schedule, freshness checks, failure behaviour, dim_confirmed_dq protection
