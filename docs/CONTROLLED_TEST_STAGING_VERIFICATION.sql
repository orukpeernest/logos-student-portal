-- LOGOS TUTORIALS controlled Test Driller: READ-ONLY staging verification
-- Run only AFTER applying 202611230001_controlled_test_attempts.sql in STAGING.
-- This script performs catalog/privilege checks only; it does not alter data or schema.

-- 1) Required lifecycle columns.
SELECT table_name, column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
    (table_name = 'logos_td_exams' AND column_name IN
      ('academic_session','starts_at','ends_at','max_attempts','results_released'))
    OR
    (table_name = 'logos_td_attempts' AND column_name IN
      ('status','started_at','expires_at','auto_submitted','submitted_at'))
  )
ORDER BY table_name, ordinal_position;

-- 2) Required new table and row-level security state.
SELECT c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'logos_td_attempt_answers';

-- 3) Lifecycle RPCs and their exact PostgreSQL signatures.
SELECT p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       p.prosecdef AS security_definer,
       p.proconfig AS function_settings
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'logos_td_admin_configure_exam',
    'logos_td_admin_bulk_upload_exam_questions',
    'logos_td_admin_set_results_released',
    'logos_td_student_active_attempts',
    'logos_td_student_start_exam',
    'logos_td_student_save_exam_answer',
    'logos_td_student_submit_exam_attempt',
    'logos_td_student_attempt_detail',
    'logos_td_finalize_attempt_internal',
    'logos_td_finalize_expired_attempts'
  )
ORDER BY p.proname, arguments;

-- 4) Direct table access must remain denied to browser roles.
SELECT
  has_table_privilege('anon', 'public.logos_td_attempt_answers', 'SELECT') AS anon_can_select,
  has_table_privilege('authenticated', 'public.logos_td_attempt_answers', 'SELECT') AS authenticated_can_select,
  has_table_privilege('anon', 'public.logos_td_attempt_answers', 'INSERT') AS anon_can_insert,
  has_table_privilege('authenticated', 'public.logos_td_attempt_answers', 'INSERT') AS authenticated_can_insert;

-- 5) RPC execution boundaries.
SELECT
  has_function_privilege('authenticated',
    'public.logos_td_student_start_exam(text)', 'EXECUTE') AS student_start_allowed,
  has_function_privilege('authenticated',
    'public.logos_td_student_save_exam_answer(uuid,text,text)', 'EXECUTE') AS student_save_allowed,
  has_function_privilege('authenticated',
    'public.logos_td_student_submit_exam_attempt(uuid)', 'EXECUTE') AS student_submit_allowed,
  has_function_privilege('authenticated',
    'public.logos_td_finalize_expired_attempts()', 'EXECUTE') AS browser_can_run_expiry_worker,
  has_function_privilege('service_role',
    'public.logos_td_finalize_expired_attempts()', 'EXECUTE') AS service_role_can_run_expiry_worker,
  has_function_privilege('authenticated',
    'public.logos_td_finalize_attempt_internal(uuid,boolean)', 'EXECUTE') AS browser_can_call_internal_finalizer;

-- Expected in section 4: all four values false.
-- Expected in section 5: the three student RPC values true; browser_can_run_expiry_worker
-- and browser_can_call_internal_finalizer false; service_role_can_run_expiry_worker true.
-- Function settings should include search_path="" for every SECURITY DEFINER RPC.
