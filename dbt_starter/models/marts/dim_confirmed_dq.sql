with flagged as (
    select * from {{ ref('dim_flagged_dq') }}
),

-- This model represents the confirmed/cleaned version of flagged_dq slots.
-- In production this would be populated by human reviewers via a separate
-- data entry process. Here we create the structure with the correct schema
-- so the fact model can join against it.
-- The table is append-only — confirmed resolutions persist across daily runs.

confirmed as (
    select
        appointment_id,
        patient_id,
        doctor_id,
        location,
        appointment_type,
        scheduled_for,
        raw_status,
        dq_reason,
        billing_hint,

        -- Human-confirmed fields (populated by reviewer)
        confirmed_status,
        confirmed_by,
        confirmed_at,

        -- Was billing used to make the determination?
        case
            when billing_hint != 'no_billing_signal'
            and confirmed_status is not null
            then true
            else false
        end                                         as billing_signal_used,

        queue_generated_at

    from flagged
    where is_reviewed = true
)

select * from confirmed