with appointment_status as (
    select * from {{ ref('int_appointment_status') }}
),

patients as (
    select
        patient_id,
        birth_year,
        sex,
        insurance_plan,
        home_location,
        age_band,
        registered_at
    from {{ ref('stg_patients') }}
),

doctors as (
    select
        doctor_id,
        provider_name,
        specialty,
        primary_location,
        is_active
    from {{ ref('stg_doctors') }}
),

final as (
    select
        -- Keys
        a.appointment_id,
        a.patient_id,
        a.doctor_id,

        -- Appointment context
        a.location,
        a.appointment_type,
        a.scheduled_for,
        a.booked_at,
        a.checked_in_at,
        a.checkout_at,
        a.cancel_reason,
        a.rescheduled_to_id,
        a.rescheduled_from_id,

        -- Status
        a.raw_status,
        a.canonical_status,
        a.final_status,
        a.is_true_no_show,
        a.is_intended_visit,
        a.is_confirmed_reschedule_origin,
        a.is_reschedule_target,
        a.has_rescheduled_status,
        a.has_rescheduled_to_link,
        a.is_chain_validated,
        a.is_broken_chain,
        a.chain_role,
        a.target_appointment_id,

        -- Billing signals
        a.has_office_visit_charge,
        a.has_no_show_fee,
        a.has_late_cancel_fee,
        a.total_billed,
        a.billing_line_count,
        a.has_cross_month_posting,

        -- Patient context
        p.birth_year,
        p.sex,
        p.insurance_plan,
        p.home_location,
        p.age_band,

        -- Doctor context
        d.provider_name,
        d.specialty,
        d.primary_location,
        d.is_active                                 as is_active_provider,

        -- Time dimensions
        date_trunc('month', a.scheduled_for)        as appointment_month,
        dayofweek(a.scheduled_for)                  as day_of_week,
        hour(a.scheduled_for)                       as hour_of_day

    from appointment_status a
    left join patients p    on a.patient_id = p.patient_id
    left join doctors d     on a.doctor_id = d.doctor_id
)

select * from final