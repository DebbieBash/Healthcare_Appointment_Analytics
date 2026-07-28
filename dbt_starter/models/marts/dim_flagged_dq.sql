with appointments as (
    select * from {{ ref('int_appointment_facts') }}
),

final as (
    select
        -- Keys
        a.appointment_id,
        a.patient_id,
        a.doctor_id,

        -- Visit context
        a.location,
        a.appointment_type,
        a.scheduled_for,
        a.booked_at,
        a.raw_status,
        a.canonical_status,
        a.cancel_reason,

        -- Reschedule link context
        a.rescheduled_to_id,
        a.rescheduled_from_id,
        a.has_rescheduled_status,
        a.has_rescheduled_to_link,
        a.is_chain_validated,
        a.is_broken_chain,
        a.target_appointment_id,

        -- Billing signals for human review (assumption 5)
        a.has_office_visit_charge,
        a.has_no_show_fee,
        a.has_late_cancel_fee,
        a.total_billed,

        -- Patient context
        a.age_band,
        a.insurance_plan,
        a.home_location,

        -- Provider context
        a.provider_name,
        a.specialty,

        -- DQ classification reason
        case
            when a.raw_status = 'rescheduled'
                and a.rescheduled_to_id is null
                then 'status_rescheduled_no_link'
            when a.raw_status != 'rescheduled'
                and a.rescheduled_to_id is not null
                then 'link_present_no_rescheduled_status'
            when a.is_broken_chain = true
                then 'broken_chain'
            else 'other'
        end                                         as dq_reason,

        -- Billing hint for reviewer
        case
            when a.has_office_visit_charge = true   then 'likely_attended'
            when a.has_no_show_fee = true           then 'likely_no_show'
            when a.has_late_cancel_fee = true       then 'likely_late_cancel'
            else 'no_billing_signal'
        end                                         as billing_hint,

        -- Review status (default unreviewed)
        false                                       as is_reviewed,
        null::varchar                               as confirmed_status,
        null::varchar                               as confirmed_by,
        null::timestamp_ntz                         as confirmed_at,
        current_timestamp()                         as queue_generated_at

    from appointments a
    where a.final_status = 'flagged_dq'
)

select * from final
