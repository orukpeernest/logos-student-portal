-- LOGOS TUTORIALS: read-only extraction of the original Test Driller RPC definitions
-- Run this in the EXISTING Supabase SQL Editor only to inspect function source.
-- This script performs no writes and returns function definitions, signatures and security metadata.
-- Do not paste secrets or student records. Function source is safe to share for code review.

SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS identity_arguments,
  pg_get_function_result(p.oid) AS return_type,
  p.prosecdef AS security_definer,
  p.provolatile AS volatility,
  p.proconfig AS function_settings,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute,
  pg_get_functiondef(p.oid) AS function_definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND p.proname = ANY (ARRAY[
    'is_logos_admin',
    'logos_td_admin_attach_question',
    'logos_td_admin_create_exam',
    'logos_td_admin_delete_question',
    'logos_td_admin_save_question',
    'logos_td_admin_set_exam_status',
    'logos_td_student_available_exams',
    'logos_td_student_exam_questions',
    'logos_td_student_practice_questions',
    'logos_td_student_results',
    'logos_td_student_submit_attempt'
  ])
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);

-- Expected: one row per installed overload. If a function is absent, it will not appear.
-- Copy the complete result (especially function_definition) back for exact staging restoration.
-- Do not execute any CREATE/ALTER statements based on this output in production.
