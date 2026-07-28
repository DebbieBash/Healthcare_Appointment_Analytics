with appointments as (
    select * from {{ ref('fct_appointments') }}
),

aggregated as (
    select
        appointment_month,
        location,
        specialty,
        appointment_type,

        -- Volume
        count(*)                                        as total_appointments,
        count_if(is_intended_visit = true)              as intended_visits,
        count_if(final_status = 'attended')             as attended_count,
        count_if(is_true_no_show = true)                as true_no_show_count,
        count_if(final_status = 'rescheduled')          as rescheduled_count,
        count_if(final_status = 'cancelled_patient')    as cancelled_patient_count,
        count_if(final_status = 'cancelled_clinic')     as cancelled_clinic_count,
        count_if(final_status = 'flagged_dq')           as flagged_dq_count,

        -- Rates (denominator = intended visits)
        round(count_if(is_true_no_show = true)
            / nullif(count_if(is_intended_visit = true), 0) * 100, 2)  as true_no_show_rate_pct,

        round(count_if(final_status = 'attended')
            / nullif(count_if(is_intended_visit = true), 0) * 100, 2)  as attended_rate_pct,

        round(count_if(final_status = 'rescheduled')
            / nullif(count(*), 0) * 100, 2)                            as reschedule_rate_pct,

        round((count_if(final_status = 'cancelled_patient')
            + count_if(final_status = 'cancelled_clinic'))
            / nullif(count(*), 0) * 100, 2)                            as cancellation_rate_pct

    from appointments
    group by
        appointment_month,
        location,
        specialty,
        appointment_type
)

select * from aggregated
order by appointment_month, location