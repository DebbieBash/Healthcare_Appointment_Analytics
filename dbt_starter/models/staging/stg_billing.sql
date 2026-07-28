with src as (
    select * from {{ source('raw', 'raw_billing') }}
),

renamed as (
    select
        billing_id,
        appointment_id,
        patient_id,
        lower(line_type)                            as line_type,
        billed_amount,
        insurance_covered,
        patient_responsibility,
        cast(service_at as timestamp_ntz)           as service_at,
        cast(posted_at as timestamp_ntz)            as posted_at,

        -- Billing signal flags (assumption 5)
        case
            when lower(line_type) = 'office_visit' then true
            else false
        end                                         as is_office_visit,

        case
            when lower(line_type) = 'no_show_fee' then true
            else false
        end                                         as is_no_show_fee,

        case
            when lower(line_type) = 'late_cancel_fee' then true
            else false
        end                                         as is_late_cancel_fee,

        -- Flag cross-month posting (claim posted in different month to service)
        case
            when date_trunc('month', cast(posted_at as timestamp_ntz))
               != date_trunc('month', cast(service_at as timestamp_ntz))
            then true
            else false
        end                                         as is_cross_month_posting

    from src
)

select * from renamed