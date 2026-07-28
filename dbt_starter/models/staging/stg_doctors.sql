with src as (
    select * from {{ source('raw', 'raw_doctors') }}
),

renamed as (
    select
        doctor_id,
        provider_name,
        lower(specialty)                            as specialty,
        lower(primary_location)                     as primary_location,
        cast(hired_at as timestamp_ntz)             as hired_at,
        is_active,

        -- Flag inactive providers who still have historical visits
        case
            when is_active = false then true
            else false
        end                                         as is_inactive_with_history

    from src
)

select * from renamed