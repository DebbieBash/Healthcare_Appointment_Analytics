with src as (
    select * from {{ source('raw', 'raw_appointments') }}
),

renamed as (
    select
        appointment_id,
        patient_id,
        doctor_id,
        location,
        lower(appointment_type)                     as appointment_type,
        cast(scheduled_for as timestamp_ntz)        as scheduled_for,
        cast(booked_at as timestamp_ntz)            as booked_at,
        cast(checked_in_at as timestamp_ntz)        as checked_in_at,
        cast(checkout_at as timestamp_ntz)          as checkout_at,
        cancel_reason,
        rescheduled_to_id,
        rescheduled_from_id,

        -- Normalise raw status to lowercase and trim whitespace
        lower(trim(status))                         as raw_status,

        -- Canonical status map (assumption 4)
        case
            when lower(trim(status)) = 'attended'
                then 'attended'
            when lower(trim(status)) in ('no_show', 'missed', 'no-show')
                then 'no_show'
            when lower(trim(status)) = 'cancelled'
                and lower(trim(cancel_reason)) in ('patient_request')
                then 'cancelled_patient'
            when lower(trim(status)) = 'cancelled'
                and lower(trim(cancel_reason)) in ('clinic_cancelled', 'provider_unavailable', 'weather')
                then 'cancelled_clinic'
            when lower(trim(status)) = 'cancelled'
                and cancel_reason is null
                then 'cancelled_unknown'
            when lower(trim(status)) = 'rescheduled'
                and rescheduled_to_id is not null
                then 'rescheduled'
            when lower(trim(status)) = 'rescheduled'
                and rescheduled_to_id is null
                then 'flagged_dq'
            else 'flagged_dq'
        end                                         as canonical_status,

        -- Reschedule signal flags (assumption 3)
        case
            when lower(trim(status)) = 'rescheduled' then true
            else false
        end                                         as has_rescheduled_status,

        case
            when rescheduled_to_id is not null then true
            else false
        end                                         as has_rescheduled_to_link,

        case
            when rescheduled_from_id is not null then true
            else false
        end                                         as is_reschedule_target,

        -- Both signals present (assumption 3)
        case
            when lower(trim(status)) = 'rescheduled'
            and rescheduled_to_id is not null
            then true
            else false
        end                                         as is_confirmed_reschedule_origin

    from src
)

select * from renamed