-- LOGOS TUTORIALS: controlled Test Driller attempt lifecycle
-- Review and apply manually in Supabase SQL Editor only after backup and approval.
-- Additive migration: preserves existing attempts and RPCs.

BEGIN;

ALTER TABLE public.logos_td_exams
  ADD COLUMN IF NOT EXISTS academic_session text,
  ADD COLUMN IF NOT EXISTS starts_at timestamptz,
  ADD COLUMN IF NOT EXISTS ends_at timestamptz,
  ADD COLUMN IF NOT EXISTS max_attempts integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS results_released boolean NOT NULL DEFAULT true;

DO $constraints$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'logos_td_exams_valid_window_check') THEN
    ALTER TABLE public.logos_td_exams
      ADD CONSTRAINT logos_td_exams_valid_window_check
      CHECK (starts_at IS NULL OR ends_at IS NULL OR ends_at > starts_at)
      NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'logos_td_exams_max_attempts_check') THEN
    ALTER TABLE public.logos_td_exams
      ADD CONSTRAINT logos_td_exams_max_attempts_check
      CHECK (max_attempts > 0)
      NOT VALID;
  END IF;
END;
$constraints$;

ALTER TABLE public.logos_td_attempts
  ALTER COLUMN submitted_at DROP NOT NULL,
  ALTER COLUMN submitted_at DROP DEFAULT,
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'submitted',
  ADD COLUMN IF NOT EXISTS started_at timestamptz,
  ADD COLUMN IF NOT EXISTS expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS auto_submitted boolean NOT NULL DEFAULT false;

DO $constraints$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'logos_td_attempts_status_check') THEN
    ALTER TABLE public.logos_td_attempts
      ADD CONSTRAINT logos_td_attempts_status_check
      CHECK (status IN ('in_progress', 'submitted', 'auto_submitted'))
      NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'logos_td_attempts_lifecycle_check') THEN
    ALTER TABLE public.logos_td_attempts
      ADD CONSTRAINT logos_td_attempts_lifecycle_check
      CHECK (
        (status = 'in_progress' AND submitted_at IS NULL AND started_at IS NOT NULL AND expires_at IS NOT NULL)
        OR
        (status IN ('submitted', 'auto_submitted') AND submitted_at IS NOT NULL)
      )
      NOT VALID;
  END IF;
END;
$constraints$;

-- Historic rows are already submitted; explicitly label them without changing their timestamps.
UPDATE public.logos_td_attempts
SET status = 'submitted',
    auto_submitted = false
WHERE status IS DISTINCT FROM 'submitted';

CREATE INDEX IF NOT EXISTS logos_td_attempts_expiry_idx
  ON public.logos_td_attempts (expires_at)
  WHERE status = 'in_progress';

CREATE INDEX IF NOT EXISTS logos_td_attempts_exam_student_status_idx
  ON public.logos_td_attempts (exam_id, student_id, status);

CREATE TABLE IF NOT EXISTS public.logos_td_attempt_answers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  attempt_id uuid NOT NULL REFERENCES public.logos_td_attempts(id) ON DELETE CASCADE,
  question_id uuid NOT NULL REFERENCES public.logos_td_questions(id) ON DELETE RESTRICT,
  position integer NOT NULL CHECK (position > 0),
  selected_answer text,
  is_correct boolean,
  question_snapshot jsonb NOT NULL,
  answered_at timestamptz,
  UNIQUE (attempt_id, question_id),
  UNIQUE (attempt_id, position),
  CONSTRAINT logos_td_attempt_answers_selected_check
    CHECK (selected_answer IS NULL OR selected_answer IN ('A','B','C','D'))
);

ALTER TABLE public.logos_td_attempt_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.logos_td_attempt_answers FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.logos_td_attempt_answers FROM anon, authenticated;
REVOKE ALL ON public.logos_td_attempt_answers FROM PUBLIC;

-- Keep attempt tables RPC-only. The new answer table has no direct user policies.
-- This helper is callable only by trusted server-side service_role and the
-- owner-executed student RPCs below.

-- New assessments default to hidden results. Existing exams retain the
-- column default true, preserving visibility of historical results.
CREATE OR REPLACE FUNCTION public.logos_td_admin_configure_exam(
  p_exam_id text,
  p_academic_session text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_max_attempts integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_exam public.logos_td_exams%ROWTYPE;
BEGIN
  IF NOT public.is_logos_admin() THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;
  IF p_max_attempts IS NULL OR p_max_attempts < 1 THEN
    RAISE EXCEPTION 'Maximum attempts must be at least one';
  END IF;
  IF p_starts_at IS NOT NULL AND p_ends_at IS NOT NULL AND p_ends_at <= p_starts_at THEN
    RAISE EXCEPTION 'Assessment closing time must be after its start time';
  END IF;

  UPDATE public.logos_td_exams
  SET academic_session = NULLIF(btrim(COALESCE(p_academic_session,'')), ''),
      starts_at = p_starts_at,
      ends_at = p_ends_at,
      max_attempts = p_max_attempts
  WHERE id::text = p_exam_id
    AND status = 'draft'
  RETURNING * INTO v_exam;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only an existing draft assessment can be scheduled';
  END IF;
  RETURN to_jsonb(v_exam);
END;
$function$;

CREATE OR REPLACE FUNCTION public.logos_td_admin_set_results_released(
  p_exam_id text,
  p_released boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_exam public.logos_td_exams%ROWTYPE;
BEGIN
  IF NOT public.is_logos_admin() THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;
  UPDATE public.logos_td_exams
  SET results_released = p_released
  WHERE id::text = p_exam_id
    AND status IN ('released','closed')
  RETURNING * INTO v_exam;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Released or closed assessment not found';
  END IF;
  RETURN to_jsonb(v_exam);
END;
$function$;

-- Override the existing creator without changing its public signature.
-- Every newly created assessment starts with results hidden.
CREATE OR REPLACE FUNCTION public.logos_td_admin_create_exam(
  p_title text,
  p_subject text,
  p_exam_type text,
  p_duration_minutes integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_exam public.logos_td_exams%ROWTYPE;
BEGIN
  IF NOT public.is_logos_admin() THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;
  IF p_title IS NULL OR btrim(p_title) = '' THEN
    RAISE EXCEPTION 'Exam title is required';
  END IF;
  IF p_duration_minutes IS NULL OR p_duration_minutes <= 0 THEN
    RAISE EXCEPTION 'Duration must be greater than zero';
  END IF;

  INSERT INTO public.logos_td_exams (
    title, subject, exam_type, duration_minutes, status, results_released
  )
  VALUES (
    p_title, p_subject, p_exam_type, p_duration_minutes, 'draft', false
  )
  RETURNING * INTO v_exam;
  RETURN to_jsonb(v_exam);
END;
$function$;

-- Students see summary results only after the administrator releases them.
CREATE OR REPLACE FUNCTION public.logos_td_student_results()
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
  IF v_student_id IS NULL THEN
    RAISE EXCEPTION 'Student account not linked';
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      a.id,
      a.exam_id,
      e.title AS exam_title,
      e.subject,
      a.score,
      a.total_questions,
      a.correct_count,
      a.wrong_count,
      a.unanswered_count,
      a.duration_seconds,
      a.submitted_at
    FROM public.logos_td_attempts a
    JOIN public.logos_td_exams e ON e.id = a.exam_id
    WHERE a.student_id = v_student_id::text
      AND a.status IN ('submitted','auto_submitted')
      AND e.results_released = true
    ORDER BY a.submitted_at DESC
  ) r;
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.logos_td_finalize_attempt_internal(
  p_attempt_id uuid,
  p_auto boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_attempt public.logos_td_attempts%ROWTYPE;
  v_total integer;
  v_correct integer;
  v_unanswered integer;
  v_wrong integer;
  v_score numeric;
  v_submitted_at timestamptz;
BEGIN
  SELECT * INTO v_attempt
  FROM public.logos_td_attempts
  WHERE id = p_attempt_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Attempt not found'; END IF;

  IF v_attempt.status IN ('submitted','auto_submitted') THEN
    RETURN to_jsonb(v_attempt);
  END IF;

  IF v_attempt.status <> 'in_progress' THEN
    RAISE EXCEPTION 'Attempt is not active';
  END IF;

  IF p_auto AND now() < v_attempt.expires_at THEN
    RAISE EXCEPTION 'Attempt has not expired';
  END IF;

  SELECT
    count(*)::integer,
    count(*) FILTER (
      WHERE upper(COALESCE(a.selected_answer,'')) =
            upper(a.question_snapshot->>'correct_answer')
    )::integer,
    count(*) FILTER (
      WHERE NULLIF(btrim(COALESCE(a.selected_answer,'')), '') IS NULL
    )::integer
  INTO v_total, v_correct, v_unanswered
  FROM public.logos_td_attempt_answers a
  WHERE a.attempt_id = p_attempt_id;

  IF v_total = 0 THEN RAISE EXCEPTION 'Attempt contains no questions'; END IF;

  v_wrong := v_total - v_correct; -- Includes unanswered, as requested.
  v_score := round((v_correct::numeric / v_total::numeric) * 100, 2);

  UPDATE public.logos_td_attempt_answers a
  SET is_correct = (
        NULLIF(btrim(COALESCE(a.selected_answer,'')), '') IS NOT NULL
        AND upper(a.selected_answer) = upper(a.question_snapshot->>'correct_answer')
      )
  WHERE a.attempt_id = p_attempt_id;

  v_submitted_at := CASE
    WHEN p_auto THEN v_attempt.expires_at
    ELSE LEAST(now(), v_attempt.expires_at)
  END;

  UPDATE public.logos_td_attempts
  SET score = v_score,
      total_questions = v_total,
      correct_count = v_correct,
      wrong_count = v_wrong,
      unanswered_count = v_unanswered,
      duration_seconds = GREATEST(0, floor(extract(epoch FROM (v_submitted_at - started_at)))::integer),
      submitted_at = v_submitted_at,
      status = CASE WHEN p_auto THEN 'auto_submitted' ELSE 'submitted' END,
      auto_submitted = p_auto
  WHERE id = p_attempt_id
  RETURNING * INTO v_attempt;

  RETURN to_jsonb(v_attempt);
END;
$function$;

CREATE OR REPLACE FUNCTION public.logos_td_student_start_exam(p_exam_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_student_id public.students.id%TYPE;
  v_exam public.logos_td_exams%ROWTYPE;
  v_attempt public.logos_td_attempts%ROWTYPE;
  v_count integer;
  v_total integer;
  v_payload jsonb;
BEGIN
  SELECT id INTO v_student_id
  FROM public.students
  WHERE auth_user_id = auth.uid()
  LIMIT 1;
  IF v_student_id IS NULL THEN RAISE EXCEPTION 'Student account not linked'; END IF;

  SELECT * INTO v_exam
  FROM public.logos_td_exams
  WHERE id::text = p_exam_id
    AND status = 'released'
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Exam is not available'; END IF;
  IF v_exam.starts_at IS NOT NULL AND now() < v_exam.starts_at THEN
    RAISE EXCEPTION 'This assessment has not started yet';
  END IF;
  IF v_exam.ends_at IS NOT NULL AND now() > v_exam.ends_at THEN
    RAISE EXCEPTION 'The availability window for this assessment has ended';
  END IF;

  -- Resume an existing in-progress attempt rather than creating another.
  SELECT * INTO v_attempt
  FROM public.logos_td_attempts
  WHERE exam_id = v_exam.id
    AND student_id = v_student_id::text
    AND status = 'in_progress'
  ORDER BY started_at DESC
  LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    IF now() >= v_attempt.expires_at THEN
      v_payload := public.logos_td_finalize_attempt_internal(v_attempt.id, true);
      RETURN jsonb_build_object(
        'expired', true,
        'attempt', v_payload,
        'message', 'Your previous attempt expired and has been submitted'
      );
    END IF;
    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'id', question_id,
        'position', position,
        'subject', question_snapshot->>'subject',
        'topic', question_snapshot->>'topic',
        'question_text', question_snapshot->>'question_text',
        'option_a', question_snapshot->>'option_a',
        'option_b', question_snapshot->>'option_b',
        'option_c', question_snapshot->>'option_c',
        'option_d', question_snapshot->>'option_d',
        'image_url', question_snapshot->>'image_url',
        'selected_answer', selected_answer
      ) ORDER BY position
    ), '[]'::jsonb)
    INTO v_payload
    FROM public.logos_td_attempt_answers
    WHERE attempt_id = v_attempt.id;
    RETURN jsonb_build_object(
      'attempt_id', v_attempt.id,
      'started_at', v_attempt.started_at,
      'expires_at', v_attempt.expires_at,
      'status', v_attempt.status,
      'questions', v_payload
    );
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM public.logos_td_attempts
  WHERE exam_id = v_exam.id
    AND student_id = v_student_id::text
    AND status IN ('submitted','auto_submitted');

  IF v_count >= v_exam.max_attempts THEN
    RAISE EXCEPTION 'You have used all permitted attempts for this assessment';
  END IF;

  SELECT count(*)::integer INTO v_total
  FROM public.logos_td_exam_questions eq
  JOIN public.logos_td_questions q ON q.id = eq.question_id
  WHERE eq.exam_id = v_exam.id AND q.is_practice = false;
  IF v_total = 0 THEN RAISE EXCEPTION 'This exam has no official questions'; END IF;

  INSERT INTO public.logos_td_attempts (
    exam_id, student_id, client_attempt_id, score, total_questions,
    correct_count, wrong_count, unanswered_count, duration_seconds,
    status, started_at, expires_at, submitted_at
  )
  VALUES (
    v_exam.id, v_student_id::text, gen_random_uuid(), 0, v_total,
    0, 0, v_total, 0,
    'in_progress', now(), now() + make_interval(mins => v_exam.duration_minutes), NULL
  )
  RETURNING * INTO v_attempt;

  INSERT INTO public.logos_td_attempt_answers (
    attempt_id, question_id, position, selected_answer, question_snapshot
  )
  SELECT
    v_attempt.id, q.id, eq.position, NULL,
    jsonb_build_object(
      'subject', q.subject,
      'topic', q.topic,
      'question_text', q.question_text,
      'option_a', q.option_a,
      'option_b', q.option_b,
      'option_c', q.option_c,
      'option_d', q.option_d,
      'image_url', q.image_url,
      'correct_answer', q.correct_answer,
      'explanation', q.explanation
    )
  FROM public.logos_td_exam_questions eq
  JOIN public.logos_td_questions q ON q.id = eq.question_id
  WHERE eq.exam_id = v_exam.id AND q.is_practice = false
  ORDER BY eq.position;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', question_id,
      'position', position,
      'subject', question_snapshot->>'subject',
      'topic', question_snapshot->>'topic',
      'question_text', question_snapshot->>'question_text',
      'option_a', question_snapshot->>'option_a',
      'option_b', question_snapshot->>'option_b',
      'option_c', question_snapshot->>'option_c',
      'option_d', question_snapshot->>'option_d',
      'image_url', question_snapshot->>'image_url',
      'selected_answer', selected_answer
    ) ORDER BY position
  ), '[]'::jsonb)
  INTO v_payload
  FROM public.logos_td_attempt_answers
  WHERE attempt_id = v_attempt.id;

  RETURN jsonb_build_object(
    'attempt_id', v_attempt.id,
    'started_at', v_attempt.started_at,
    'expires_at', v_attempt.expires_at,
    'status', v_attempt.status,
    'questions', v_payload
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.logos_td_student_save_exam_answer(
  p_attempt_id uuid,
  p_question_id text,
  p_selected_answer text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_student_id public.students.id%TYPE;
  v_attempt public.logos_td_attempts%ROWTYPE;
  v_question_id uuid;
BEGIN
  SELECT id INTO v_student_id
  FROM public.students WHERE auth_user_id = auth.uid() LIMIT 1;
  IF v_student_id IS NULL THEN RAISE EXCEPTION 'Student account not linked'; END IF;

  IF p_selected_answer IS NOT NULL
     AND btrim(p_selected_answer) <> ''
     AND upper(p_selected_answer) NOT IN ('A','B','C','D') THEN
    RAISE EXCEPTION 'Answer must be A, B, C, D or blank';
  END IF;

  SELECT * INTO v_attempt
  FROM public.logos_td_attempts
  WHERE id = p_attempt_id AND student_id = v_student_id::text
  FOR UPDATE;
  IF NOT FOUND OR v_attempt.status <> 'in_progress' THEN
    RAISE EXCEPTION 'Active attempt not found';
  END IF;
  IF now() >= v_attempt.expires_at THEN
    PERFORM public.logos_td_finalize_attempt_internal(v_attempt.id, true);
    RAISE EXCEPTION 'Time has expired; your attempt has been submitted';
  END IF;

  BEGIN
    v_question_id := p_question_id::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'Invalid question ID';
  END;

  UPDATE public.logos_td_attempt_answers
  SET selected_answer = NULLIF(upper(btrim(COALESCE(p_selected_answer,''))), ''),
      answered_at = CASE
        WHEN NULLIF(btrim(COALESCE(p_selected_answer,'')), '') IS NULL THEN NULL
        ELSE now()
      END
  WHERE attempt_id = v_attempt.id AND question_id = v_question_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Question does not belong to this attempt'; END IF;
  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.logos_td_student_submit_exam_attempt(p_attempt_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_student_id public.students.id%TYPE;
  v_attempt public.logos_td_attempts%ROWTYPE;
BEGIN
  SELECT id INTO v_student_id
  FROM public.students WHERE auth_user_id = auth.uid() LIMIT 1;
  IF v_student_id IS NULL THEN RAISE EXCEPTION 'Student account not linked'; END IF;

  SELECT * INTO v_attempt
  FROM public.logos_td_attempts
  WHERE id = p_attempt_id AND student_id = v_student_id::text
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Attempt not found'; END IF;

  IF v_attempt.status IN ('submitted','auto_submitted') THEN
    RETURN to_jsonb(v_attempt);
  END IF;

  RETURN public.logos_td_finalize_attempt_internal(
    p_attempt_id,
    now() >= v_attempt.expires_at
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.logos_td_finalize_expired_attempts()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_id uuid;
  v_count integer := 0;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Trusted scheduler access required';
  END IF;

  FOR v_id IN
    SELECT id
    FROM public.logos_td_attempts
    WHERE status = 'in_progress'
      AND expires_at <= now()
    ORDER BY expires_at
    LIMIT 500
    FOR UPDATE SKIP LOCKED
  LOOP
    PERFORM public.logos_td_finalize_attempt_internal(v_id, true);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.logos_td_student_attempt_detail(p_attempt_id uuid)
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
  FROM public.students WHERE auth_user_id = auth.uid() LIMIT 1;
  IF v_student_id IS NULL THEN RAISE EXCEPTION 'Student account not linked'; END IF;

  SELECT jsonb_build_object(
    'attempt', to_jsonb(a),
    'answers', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'question_id', aa.question_id,
        'position', aa.position,
        'question_text', aa.question_snapshot->>'question_text',
        'option_a', aa.question_snapshot->>'option_a',
        'option_b', aa.question_snapshot->>'option_b',
        'option_c', aa.question_snapshot->>'option_c',
        'option_d', aa.question_snapshot->>'option_d',
        'selected_answer', aa.selected_answer,
        'correct_answer', CASE WHEN e.results_released THEN aa.question_snapshot->>'correct_answer' ELSE NULL END,
        'is_correct', CASE WHEN e.results_released THEN aa.is_correct ELSE NULL END,
        'explanation', CASE WHEN e.results_released THEN aa.question_snapshot->>'explanation' ELSE NULL END
      ) ORDER BY aa.position)
      FROM public.logos_td_attempt_answers aa
      WHERE aa.attempt_id = a.id
    ), '[]'::jsonb)
  )
  INTO v_result
  FROM public.logos_td_attempts a
  JOIN public.logos_td_exams e ON e.id = a.exam_id
  WHERE a.id = p_attempt_id
    AND a.student_id = v_student_id::text
    AND a.status IN ('submitted','auto_submitted')
    AND (e.results_released OR a.submitted_at IS NULL);

  IF v_result IS NULL THEN RAISE EXCEPTION 'Result details are not available'; END IF;
  RETURN v_result;
END;
$function$;

-- No browser/user execution of the privileged finalizer.
REVOKE ALL ON FUNCTION public.logos_td_finalize_attempt_internal(uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.logos_td_finalize_expired_attempts() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.logos_td_finalize_expired_attempts() TO service_role;

GRANT EXECUTE ON FUNCTION public.logos_td_admin_configure_exam(text, text, timestamptz, timestamptz, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.logos_td_admin_set_results_released(text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.logos_td_student_start_exam(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.logos_td_student_save_exam_answer(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.logos_td_student_submit_exam_attempt(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.logos_td_student_attempt_detail(uuid) TO authenticated;

COMMIT;

-- Deployment note:
-- Configure a trusted external scheduler to invoke
-- public.logos_td_finalize_expired_attempts() using service_role credentials.
-- Do not put the service_role key in browser code. This SQL migration alone
-- does not install or configure a scheduler.
