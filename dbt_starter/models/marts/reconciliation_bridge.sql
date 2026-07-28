with appointments as (
    select * from {{ ref('int_appointment_facts') }}
),

-- Total population
totals as (
    select
        count(*)                                        as total_slots,
        count_if(is_intended_visit = true)              as intended_visits,
        count_if(final_status = 'attended')             as attended_count,
        count_if(final_status = 'no_show')              as raw_no_show_count,
        count_if(is_true_no_show = true)                as true_no_show_count,
        count_if(final_status = 'rescheduled')          as rescheduled_count,
        count_if(final_status = 'cancelled_patient')    as cancelled_patient_count,
        count_if(final_status = 'cancelled_clinic')     as cancelled_clinic_count,
        count_if(final_status = 'cancelled_unknown')    as cancelled_unknown_count,
        count_if(final_status = 'flagged_dq')           as flagged_dq_count,

        -- Misflagged reschedules (keyed as no_show but have reschedule link)
        count_if(
            final_status = 'no_show'
            and rescheduled_to_id is not null
        )                                               as misflagged_reschedule_count,

        -- Misflagged cancellations (keyed as no_show but have cancel reason)
        count_if(
            final_status = 'no_show'
            and cancel_reason is not null
        )                                               as misflagged_cancel_count

    from appointments
),

bridge as (
    select
        total_slots,
        intended_visits,
        attended_count,
        raw_no_show_count,
        true_no_show_count,
        rescheduled_count,
        cancelled_patient_count,
        cancelled_clinic_count,
        cancelled_unknown_count,
        flagged_dq_count,
        misflagged_reschedule_count,
        misflagged_cancel_count,

        -- Ops dashboard rate (raw no_show / all slots)
        round(raw_no_show_count
            / nullif(total_slots, 0) * 100, 2)          as ops_dashboard_rate_pct,

        -- True no-show rate (true no_show / intended visits)
        round(true_no_show_count
            / nullif(intended_visits, 0) * 100, 2)      as true_no_show_rate_pct,

        -- Gap
        round(raw_no_show_count
            / nullif(total_slots, 0) * 100, 2)
        - round(true_no_show_count
            / nullif(intended_visits, 0) * 100, 2)      as gap_pct,

        -- Gap components
        round(misflagged_reschedule_count
            / nullif(total_slots, 0) * 100, 2)          as gap_misflagged_reschedules_pct,

        round(misflagged_cancel_count
            / nullif(total_slots, 0) * 100, 2)          as gap_misflagged_cancels_pct,

        round(flagged_dq_count
            / nullif(total_slots, 0) * 100, 2)          as gap_flagged_dq_pct,

        -- Worst case rate (all flagged_dq counted as no_show)
        round((true_no_show_count + flagged_dq_count)
            / nullif(intended_visits + flagged_dq_count, 0) * 100, 2) as worst_case_rate_pct,

        'no_show = missed with no reschedule · denominator = intended visits' as policy_applied

    from totals
)

select * from bridge