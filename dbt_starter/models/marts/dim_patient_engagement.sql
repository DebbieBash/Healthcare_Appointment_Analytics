with appointments as (
    select * from {{ ref('fct_appointments') }}
),

patient_metrics as (
    select
        patient_id,
        home_location,
        insurance_plan,
        age_band,
        sex,

        -- Volume
        count(*)                                        as total_appointments,
        count_if(is_intended_visit = true)              as intended_visits,
        count_if(final_status = 'attended')             as attended_count,
        count_if(is_true_no_show = true)                as true_no_show_count,
        count_if(final_status = 'rescheduled')          as rescheduled_count,
        count_if(final_status = 'cancelled_patient')    as cancelled_patient_count,
        count_if(final_status = 'cancelled_clinic')     as cancelled_clinic_count,
        count_if(final_status = 'flagged_dq')           as flagged_dq_count,

        -- Rates
        round(count_if(is_true_no_show = true)
            / nullif(count_if(is_intended_visit = true), 0) * 100, 2)  as no_show_rate_pct,

        round(count_if(final_status = 'attended')
            / nullif(count_if(is_intended_visit = true), 0) * 100, 2)  as attended_rate_pct,

        round(count_if(final_status = 'rescheduled')
            / nullif(count(*), 0) * 100, 2)                            as reschedule_rate_pct,

        -- Most recent appointment
        max(scheduled_for)                              as last_appointment_date,
        min(scheduled_for)                              as first_appointment_date,

        -- Engagement risk signal for COO initiative
        case
            when count_if(is_true_no_show = true)
                / nullif(count_if(is_intended_visit = true), 0) >= 0.3
                then 'high_risk'
            when count_if(is_true_no_show = true)
                / nullif(count_if(is_intended_visit = true), 0) >= 0.15
                then 'medium_risk'
            when count_if(is_true_no_show = true)
                / nullif(count_if(is_intended_visit = true), 0) > 0
                then 'low_risk'
            else 'no_history'
        end                                             as engagement_risk

    from appointments
    group by
        patient_id,
        home_location,
        insurance_plan,
        age_band,
        sex
)

select * from patient_metrics