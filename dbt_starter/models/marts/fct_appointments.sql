with appointment_facts as (
    select * from {{ ref('int_appointment_facts') }}
),

final as (
    select
        -- Primary key
        appointment_id,

        -- Foreign keys
        patient_id,
        doctor_id,

        -- Appointment context
        location,
        appointment_type,
        scheduled_for,
        booked_at,
        checked_in_at,
        checkout_at,
        cancel_reason,
        rescheduled_to_id,
        rescheduled_from_id,
        target_appointment_id,
        appointment_month,
        day_of_week,
        hour_of_day,

        -- Status
        raw_status,
        canonical_status,
        final_status,

        -- Flags
        is_true_no_show,
        is_intended_visit,
        is_confirmed_reschedule_origin,
        is_reschedule_target,
        is_chain_validated,
        is_broken_chain,

        -- Billing signals
        has_office_visit_charge,
        has_no_show_fee,
        has_late_cancel_fee,
        total_billed,
        billing_line_count,

        -- Patient context
        birth_year,
        sex,
        insurance_plan,
        home_location,
        age_band,

        -- Doctor context
        provider_name,
        specialty,
        primary_location,
        is_active_provider,

        -- Surrogate key
        {{ dbt_utils.generate_surrogate_key(['appointment_id']) }} as appointment_sk

    from appointment_facts
)

select * from final