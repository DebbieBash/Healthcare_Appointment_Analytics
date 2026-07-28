with src as (
    select * from {{ source('raw', 'raw_patients') }}
),

renamed as (
    select
        patient_id,
        birth_year,
        upper(sex)                                  as sex,
        lower(insurance_plan)                       as insurance_plan,
        lower(home_location)                        as home_location,
        cast(registered_at as timestamp_ntz)        as registered_at,

        -- Derived age band
        case
            when (2024 - birth_year) < 18   then 'under_18'
            when (2024 - birth_year) < 35   then '18_34'
            when (2024 - birth_year) < 50   then '35_49'
            when (2024 - birth_year) < 65   then '50_64'
            else '65_plus'
        end                                         as age_band

    from src
)

select * from renamed