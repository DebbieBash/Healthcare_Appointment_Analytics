-- Business rule: flagged_dq count in reconciliation bridge must equal
-- the number of rows in dim_flagged_dq
SELECT
    b.flagged_dq_count                          as bridge_count,
    COUNT(f.appointment_id)                     as actual_count,
    ABS(b.flagged_dq_count - COUNT(f.appointment_id)) as discrepancy
FROM {{ ref('reconciliation_bridge') }} b
CROSS JOIN {{ ref('dim_flagged_dq') }} f
GROUP BY b.flagged_dq_count
HAVING ABS(b.flagged_dq_count - COUNT(f.appointment_id)) > 0