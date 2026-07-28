-- Business rule: confirmed reschedule originals must not appear in intended visits
-- A slot cannot be both a reschedule origin and an intended visit
SELECT
    appointment_id,
    is_confirmed_reschedule_origin,
    is_intended_visit,
    final_status
FROM {{ ref('fct_appointments') }}
WHERE is_confirmed_reschedule_origin = true
  AND is_intended_visit = true