with billing as (
    select * from {{ ref('stg_billing') }}
),

aggregated as (
    select
        appointment_id,

        -- Billing signal flags (assumption 5)
        max(is_office_visit)                        as has_office_visit_charge,
        max(is_no_show_fee)                         as has_no_show_fee,
        max(is_late_cancel_fee)                     as has_late_cancel_fee,

        -- Amounts
        sum(billed_amount)                          as total_billed,
        sum(insurance_covered)                      as total_insurance_covered,
        sum(patient_responsibility)                 as total_patient_responsibility,

        -- Cross-month posting flag
        max(is_cross_month_posting)                 as has_cross_month_posting,

        -- Count of billing lines
        count(*)                                    as billing_line_count

    from billing
    group by appointment_id
)

select * from aggregated