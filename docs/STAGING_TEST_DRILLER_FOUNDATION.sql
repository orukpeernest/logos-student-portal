-- LOGOS TUTORIALS — STAGING-ONLY Test Driller foundation
-- Run ONLY in the separate staging Supabase project.
-- Do NOT run against the live logos-student-platform project.
-- Creates schema only; it does not copy student, payment, or admin records.
-- After this script, run supabase/migrations/202611230001_controlled_test_attempts.sql.
-- This foundation intentionally does not recreate the wider fees/attendance portal schema.

BEGIN;

CREATE TABLE IF NOT EXISTS public.admin_users (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.students (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_code text NOT NULL UNIQUE,
  surname text NOT NULL,
  first_name text NOT NULL,
  other_names text,
  phone text,
  guardian_phone text,
  academic_session text NOT NULL,
  account_status text NOT NULL DEFAULT 'pending',
  auth_user_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_students_student_code
  ON public.students(student_code);

CREATE OR REPLACE FUNCTION public.is_logos_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_users au
    WHERE au.user_id = auth.uid()
  );
$function$;

REVOKE ALL ON FUNCTION public.is_logos_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_logos_admin() TO authenticated;

ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin manages students" ON public.students;
CREATE POLICY "Admin manages students"
  ON public.students FOR ALL TO authenticated
  USING (public.is_logos_admin())
  WITH CHECK (public.is_logos_admin());

DROP POLICY IF EXISTS "Students view own record" ON public.students;
CREATE POLICY "Students view own record"
  ON public.students FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.students TO authenticated;

CREATE TABLE IF NOT EXISTS public.logos_td_exams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  subject text NOT NULL CHECK (subject IN (
    'English','Mathematics','Physics','Chemistry','Biology',
    'Government','CRS','Literature','Economics','Commerce'
  )),
  exam_type text NOT NULL DEFAULT 'Practice',
  duration_minutes integer NOT NULL CHECK (duration_minutes > 0),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','released','closed')),
  released_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS logos_td_exams_status_released_idx
  ON public.logos_td_exams(status, released_at);

CREATE TABLE IF NOT EXISTS public.logos_td_questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject text NOT NULL CHECK (subject IN (
    'English','Mathematics','Physics','Chemistry','Biology',
    'Government','CRS','Literature','Economics','Commerce'
  )),
  topic text NOT NULL DEFAULT '',
  exam_type text NOT NULL DEFAULT 'Practice',
  exam_year integer,
  question_text text NOT NULL,
  option_a text NOT NULL,
  option_b text NOT NULL,
  option_c text NOT NULL,
  option_d text NOT NULL,
  correct_answer char NOT NULL CHECK (correct_answer IN ('A','B','C','D')),
  explanation text,
  image_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_practice boolean NOT NULL DEFAULT true
);

CREATE INDEX IF NOT EXISTS logos_td_questions_practice_subject_idx
  ON public.logos_td_questions(is_practice, subject);
CREATE INDEX IF NOT EXISTS logos_td_questions_subject_topic_idx
  ON public.logos_td_questions(subject, topic);

CREATE TABLE IF NOT EXISTS public.logos_td_exam_questions (
  exam_id uuid NOT NULL REFERENCES public.logos_td_exams(id) ON DELETE CASCADE,
  question_id uuid NOT NULL REFERENCES public.logos_td_questions(id) ON DELETE RESTRICT,
  position integer NOT NULL,
  PRIMARY KEY (exam_id, question_id),
  UNIQUE (exam_id, position)
);

CREATE INDEX IF NOT EXISTS logos_td_exam_questions_exam_position_idx
  ON public.logos_td_exam_questions(exam_id, position);

CREATE TABLE IF NOT EXISTS public.logos_td_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  exam_id uuid NOT NULL REFERENCES public.logos_td_exams(id) ON DELETE RESTRICT,
  student_id text NOT NULL,
  client_attempt_id uuid NOT NULL,
  score numeric NOT NULL CHECK (score >= 0),
  total_questions integer NOT NULL CHECK (total_questions > 0),
  correct_count integer NOT NULL DEFAULT 0,
  wrong_count integer NOT NULL DEFAULT 0,
  unanswered_count integer NOT NULL DEFAULT 0,
  duration_seconds integer NOT NULL DEFAULT 0,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT logos_td_attempts_student_client_attempt_key
    UNIQUE (student_id, client_attempt_id)
);

CREATE INDEX IF NOT EXISTS logos_td_attempts_exam_student_idx
  ON public.logos_td_attempts(exam_id, student_id);

ALTER TABLE public.logos_td_exams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.logos_td_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.logos_td_exam_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.logos_td_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

-- Test Driller data is RPC-only: no direct browser table access or policies.
REVOKE ALL ON public.logos_td_exams FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.logos_td_questions FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.logos_td_exam_questions FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.logos_td_attempts FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.admin_users FROM PUBLIC, anon, authenticated;

-- Compatibility signatures required by the following controlled-assessment
-- migration's explicit revocations. They intentionally fail closed and are
-- not granted to browser roles. The new lifecycle replaces these code paths.
CREATE OR REPLACE FUNCTION public.logos_td_student_exam_questions(p_exam_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  RAISE EXCEPTION 'Legacy exam question access is disabled in staging';
END;
$function$;

CREATE OR REPLACE FUNCTION public.logos_td_student_submit_attempt(
  p_exam_id text,
  p_client_attempt_id uuid,
  p_answers jsonb,
  p_duration_seconds integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  RAISE EXCEPTION 'Legacy client-submitted attempts are disabled in staging';
END;
$function$;

REVOKE ALL ON FUNCTION public.logos_td_student_exam_questions(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.logos_td_student_submit_attempt(text, uuid, jsonb, integer) FROM PUBLIC, anon, authenticated;

COMMIT;
