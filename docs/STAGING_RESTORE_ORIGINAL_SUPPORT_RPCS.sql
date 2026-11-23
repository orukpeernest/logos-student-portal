-- LOGOS TUTORIALS: Restore original support RPCs for an isolated STAGING database.
-- Run only AFTER:
--   1) docs/STAGING_TEST_DRILLER_FOUNDATION.sql
--   2) supabase/migrations/202611230001_controlled_test_attempts.sql
-- Never run this on the live/production project.
-- This restores only support functions still used by the current portal.
-- The controlled-assessment migration's newer create_exam and student_results
-- implementations are intentionally preserved.
-- The legacy student_exam_questions and student_submit_attempt RPCs remain revoked.

BEGIN;

CREATE OR REPLACE FUNCTION public.is_logos_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_users
    WHERE user_id = (SELECT auth.uid())
  );
$function$;

CREATE OR REPLACE FUNCTION public.logos_td_admin_delete_question(p_question_id text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NOT public.is_logos_admin() THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;
  DELETE FROM public.logos_td_questions WHERE id::text = p_question_id;
  RETURN FOUND;
END;
$function$;

CREATE OR REPLACE FUNCTION public.logos_td_admin_save_question(p_question jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_question public.logos_td_questions%ROWTYPE;
  v_id text;
BEGIN
  IF NOT public.is_logos_admin() THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;
  IF p_question IS NULL OR jsonb_typeof(p_question) <> 'object' THEN
    RAISE EXCEPTION 'Invalid question data';
  END IF;

  IF p_question->>'id' IS NOT NULL THEN
    v_id := p_question->>'id';
    IF EXISTS (
      SELECT 1
      FROM public.logos_td_exam_questions eq
      JOIN public.logos_td_exams e ON e.id = eq.exam_id
      JOIN public.logos_td_questions q ON q.id = eq.question_id
      WHERE q.id::text = v_id AND e.status <> 'draft'
    ) THEN
      RAISE EXCEPTION 'Questions in released or closed exams cannot be edited';
    END IF;

    UPDATE public.logos_td_questions
    SET subject = p_question->>'subject',
        topic = p_question->>'topic',
        exam_type = p_question->>'exam_type',
        exam_year = NULLIF(p_question->>'exam_year', '')::integer,
        question_text = p_question->>'question_text',
        option_a = p_question->>'option_a',
        option_b = p_question->>'option_b',
        option_c = p_question->>'option_c',
        option_d = p_question->>'option_d',
        correct_answer = upper(p_question->>'correct_answer'),
        explanation = p_question->>'explanation',
        image_url = p_question->>'image_url',
        is_practice = COALESCE((p_question->>'is_practice')::boolean, true),
        updated_at = now()
    WHERE id::text = v_id
    RETURNING * INTO v_question;

    IF NOT FOUND THEN RAISE EXCEPTION 'Question not found'; END IF;
  ELSE
    INSERT INTO public.logos_td_questions (
      subject, topic, exam_type, exam_year, question_text,
      option_a, option_b, option_c, option_d, correct_answer,
      explanation, image_url, is_practice
    )
    VALUES (
      p_question->>'subject', p_question->>'topic',
      p_question->>'exam_type',
      NULLIF(p_question->>'exam_year', '')::integer,
      p_question->>'question_text', p_question->>'option_a',
      p_question->>'option_b', p_question->>'option_c',
      p_question->>'option_d', upper(p_question->>'correct_answer'),
      p_question->>'explanation', p_question->>'image_url',
      COALESCE((p_question->>'is_practice')::boolean, true)
    )
    RETURNING * INTO v_question;
  END IF;
  RETURN to_jsonb(v_question);
END;
$function$;

CREATE OR REPLACE FUNCTION public.logos_td_admin_set_exam_status(p_exam_id text, p_status text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_exam public.logos_td_exams%ROWTYPE;
  v_total integer;
  v_official integer;
BEGIN
  IF NOT public.is_logos_admin() THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;
  IF p_status NOT IN ('draft', 'released', 'closed') THEN
    RAISE EXCEPTION 'Invalid exam status';
  END IF;
  IF p_status = 'released' THEN
    SELECT count(*)::integer,
           count(*) FILTER (WHERE q.is_practice = false)::integer
    INTO v_total, v_official
    FROM public.logos_td_exam_questions eq
    JOIN public.logos_td_questions q ON q.id = eq.question_id
    WHERE eq.exam_id::text = p_exam_id;
    IF v_total = 0 OR v_official <> v_total THEN
      RAISE EXCEPTION 'An exam must contain official questions before release';
    END IF;
  END IF;
  UPDATE public.logos_td_exams
  SET status = p_status,
      released_at = CASE WHEN p_status = 'released'
        THEN COALESCE(released_at, now()) ELSE released_at END
  WHERE id::text = p_exam_id
  RETURNING * INTO v_exam;
  IF NOT FOUND THEN RAISE EXCEPTION 'Exam not found'; END IF;
  RETURN to_jsonb(v_exam);
END;
$function$;

CREATE OR REPLACE FUNCTION public.logos_td_student_available_exams()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_student_id public.students.id%TYPE;
  v_result jsonb;
BEGIN
  SELECT id INTO v_student_id
  FROM public.students
  WHERE auth_user_id = auth.uid()
  LIMIT 1;
  IF v_student_id IS NULL THEN RAISE EXCEPTION 'Student account not linked'; END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT id, title, subject, exam_type, duration_minutes, released_at
    FROM public.logos_td_exams
    WHERE status = 'released'
    ORDER BY released_at DESC
  ) e;
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.logos_td_student_practice_questions(
  p_subject text DEFAULT NULL::text,
  p_limit integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_student_id public.students.id%TYPE;
  v_result jsonb;
BEGIN
  SELECT id INTO v_student_id
  FROM public.students
  WHERE auth_user_id = auth.uid()
  LIMIT 1;
  IF v_student_id IS NULL THEN RAISE EXCEPTION 'Student account not linked'; END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(q)), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT id, subject, topic, exam_type, exam_year,
           question_text, option_a, option_b, option_c, option_d,
           correct_answer, explanation, image_url
    FROM public.logos_td_questions
    WHERE is_practice = true
      AND (p_subject IS NULL OR subject = p_subject)
    ORDER BY created_at DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100)
  ) q;
  RETURN v_result;
END;
$function$;

-- Explicit browser-role boundaries: authenticated users only; never anon/PUBLIC.
REVOKE ALL ON FUNCTION public.is_logos_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_logos_admin() TO authenticated;

-- The legacy question-attachment RPC is intentionally not restored.
-- Controlled assessments must use the atomic test-specific bulk-upload RPC.
REVOKE ALL ON FUNCTION public.logos_td_admin_attach_question(text, text, integer) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.logos_td_admin_delete_question(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.logos_td_admin_delete_question(text) TO authenticated;

REVOKE ALL ON FUNCTION public.logos_td_admin_save_question(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.logos_td_admin_save_question(jsonb) TO authenticated;

REVOKE ALL ON FUNCTION public.logos_td_admin_set_exam_status(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.logos_td_admin_set_exam_status(text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.logos_td_student_available_exams() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.logos_td_student_available_exams() TO authenticated;

REVOKE ALL ON FUNCTION public.logos_td_student_practice_questions(text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.logos_td_student_practice_questions(text, integer) TO authenticated;

-- Preserve controlled-test safeguards from the controlled-assessment migration.
REVOKE ALL ON FUNCTION public.logos_td_student_exam_questions(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.logos_td_student_submit_attempt(text, uuid, jsonb, integer) FROM PUBLIC, anon, authenticated;

COMMIT;
