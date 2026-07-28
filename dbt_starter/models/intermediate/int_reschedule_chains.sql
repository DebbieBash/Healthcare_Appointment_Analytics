with appointments as (
    select * from {{ ref('stg_appointments') }}
),

-- Identify confirmed reschedule originals (both signals present)
reschedule_originals as (
    select
        appointment_id                              as original_appointment_id,
        rescheduled_to_id                           as target_appointment_id,
        patient_id,
        scheduled_for                               as original_scheduled_for,
        canonical_status,
        has_rescheduled_status,
        has_rescheduled_to_link,
        is_confirmed_reschedule_origin
    from appointments
    where is_confirmed_reschedule_origin = true
),

-- Identify reschedule targets (slots that are the destination of a reschedule)
reschedule_targets as (
    select
        appointment_id                              as target_appointment_id,
        rescheduled_from_id                         as original_appointment_id,
        patient_id,
        scheduled_for                               as target_scheduled_for,
        canonical_status                            as target_status
    from appointments
    where is_reschedule_target = true
),

-- Join originals to targets to validate the chain
chain_validation as (
    select
        o.original_appointment_id,
        o.target_appointment_id,
        o.patient_id,
        o.original_scheduled_for,
        t.target_scheduled_for,
        t.target_status,

        -- Validate forward and backward links agree
        case
            when t.target_appointment_id is not null
            and t.original_appointment_id = o.original_appointment_id
            then true
            else false
        end                                         as is_chain_validated,

        -- Flag broken chains
        case
            when t.target_appointment_id is null
            then true
            else false
        end                                         as is_broken_chain

    from reschedule_originals o
    left join reschedule_targets t
        on o.target_appointment_id = t.target_appointment_id
        and o.patient_id = t.patient_id
),

-- Also flag status-only mismatches (status=rescheduled but no link)
status_only as (
    select
        appointment_id,
        patient_id,
        scheduled_for,
        canonical_status
    from appointments
    where has_rescheduled_status = true
      and has_rescheduled_to_link = false
),

final as (
    select
        original_appointment_id         as appointment_id,
        target_appointment_id,
        patient_id,
        original_scheduled_for,
        target_scheduled_for,
        target_status,
        is_chain_validated,
        is_broken_chain,
        'reschedule_origin'             as chain_role
    from chain_validation

    union all

    select
        appointment_id,
        null                            as target_appointment_id,
        patient_id,
        scheduled_for                   as original_scheduled_for,
        null                            as target_scheduled_for,
        null                            as target_status,
        false                           as is_chain_validated,
        true                            as is_broken_chain,
        'status_only_mismatch'          as chain_role
    from status_only
)

select * from final