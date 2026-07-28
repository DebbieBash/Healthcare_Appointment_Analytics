-- Business rule: a true no-show must never have a forward reschedule link
-- If the patient rescheduled, they did not truly miss the visit
SELECT
    appointment_id,
    is_true_no_show,
    rescheduled_to_id,
    final_status
FROM {{ ref('fct_appointments') }}
WHERE is_true_no_show = true
  AND rescheduled_to_id is not null