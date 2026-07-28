with appointments as (
    select * from {{ ref('stg_appointments') }}
),

billing as (
    select * from {{ ref('int_billing_signals') }}
),

chains as (
    select
        appointment_id,
        target_appointment_id,
        is_chain_validated,
        is_broken_chain,
        chain_role
    from {{ ref('int_reschedule_chains') }}
),

joined as (
    select
        a.appointment_id,
        a.patient_id,
        a.doctor_id,
        a.location,
        a.appointment_type,
        a.scheduled_for,
        a.booked_at,
        a.checked_in_at,
        a.checkout_at,
        a.cancel_reason,
        a.rescheduled_to_id,
        a.rescheduled_from_id,
        a.raw_status,
        a.canonical_status,
        a.has_rescheduled_status,
        a.has_rescheduled_to_link,
        a.is_reschedule_target,
        a.is_confirmed_reschedule_origin,

        -- Billing signals
        coalesce(b.has_office_visit_charge, false)  as has_office_visit_charge,
        coalesce(b.has_no_show_fee, false)          as has_no_show_fee,
        coalesce(b.has_late_cancel_fee, false)      as has_late_cancel_fee,
        coalesce(b.total_billed, 0)                 as total_billed,
        coalesce(b.billing_line_count, 0)           as billing_line_count,
        coalesce(b.has_cross_month_posting, false)  as has_cross_month_posting,

        -- Chain context
        c.is_chain_validated,
        c.is_broken_chain,
        c.chain_role,
        c.target_appointment_id,

        -- Final classification (assumption 1, 3, 4)
        case
            when a.canonical_status = 'attended'            then 'attended'
            when a.canonical_status = 'rescheduled'
                and c.is_chain_validated = true             then 'rescheduled'
            when a.canonical_status = 'rescheduled'
                and (c.is_chain_validated = false
                or c.is_chain_validated is null)            then 'flagged_dq'
            when a.canonical_status = 'no_show'             then 'no_show'
            when a.canonical_status like 'cancelled%'       then a.canonical_status
            when a.canonical_status = 'flagged_dq'          then 'flagged_dq'
            else 'flagged_dq'
        end                                         as final_status,

        -- Is this a true no-show (assumption 1)
        case
            when a.canonical_status = 'no_show'
            and a.rescheduled_to_id is null         then true
            else false
        end                                         as is_true_no_show,

        -- Is this in the intended visits denominator (assumption 2)
        case
            when a.canonical_status like 'cancelled%'       then false
            when a.is_confirmed_reschedule_origin = true    then false
            else true
        end                                         as is_intended_visit

    from appointments a
    left join billing b     on a.appointment_id = b.appointment_id
    left join chains c      on a.appointment_id = c.appointment_id
)

select * from joined