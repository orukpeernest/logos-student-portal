const assert = require("node:assert/strict");
const fs = require("node:fs");

const sql = fs.readFileSync("supabase/migrations/202611230001_controlled_test_attempts.sql", "utf8");

assert.match(sql, /^BEGIN;/m, "migration must run in a transaction");
assert.match(sql, /^COMMIT;/m, "migration must commit its transaction");
assert.match(sql, /CREATE TABLE IF NOT EXISTS public\.logos_td_attempt_answers/i);
assert.match(sql, /ALTER TABLE public\.logos_td_attempt_answers ENABLE ROW LEVEL SECURITY/i);
assert.match(sql, /REVOKE ALL ON public\.logos_td_attempt_answers FROM anon, authenticated/i);
assert.match(sql, /v_wrong := v_total - v_correct/i, "unanswered questions must be included in wrong_count");
assert.match(sql, /round\(\(v_correct::numeric \/ v_total::numeric\) \* 100, 2\)/i, "score must use all questions as denominator");
assert.match(sql, /now\(\) \+ make_interval\(mins => v_exam\.duration_minutes\)/i, "deadline must be set by the database");
assert.match(sql, /COALESCE\(auth\.role\(\), ''\) <> 'service_role'/i, "expiry worker must require service_role");
assert.match(sql, /REVOKE ALL ON FUNCTION public\.logos_td_finalize_attempt_internal\(uuid, boolean\) FROM PUBLIC, anon, authenticated/i);
assert.match(sql, /REVOKE ALL ON FUNCTION public\.logos_td_student_exam_questions\(text\) FROM PUBLIC, anon, authenticated/i);
assert.match(sql, /REVOKE ALL ON FUNCTION public\.logos_td_student_submit_attempt\(text, uuid, jsonb, integer\) FROM PUBLIC, anon, authenticated/i);
assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.logos_td_finalize_expired_attempts\(\) TO service_role/i);
assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.logos_td_student_start_exam\(text\) TO authenticated/i);
assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.logos_td_student_save_exam_answer\(uuid, text, text\) TO authenticated/i);
assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.logos_td_student_submit_exam_attempt\(uuid\) TO authenticated/i);

const startFunction = sql.slice(
  sql.indexOf("CREATE OR REPLACE FUNCTION public.logos_td_student_start_exam"),
  sql.indexOf("CREATE OR REPLACE FUNCTION public.logos_td_student_save_exam_answer")
);
assert.match(startFunction, /'correct_answer'/, "server must snapshot answer keys");
assert.doesNotMatch(startFunction, /'correct_answer'\s*,\s*question_snapshot/i, "student question payload must not expose answer keys");

const saveFunction = sql.slice(
  sql.indexOf("CREATE OR REPLACE FUNCTION public.logos_td_student_save_exam_answer"),
  sql.indexOf("CREATE OR REPLACE FUNCTION public.logos_td_student_submit_exam_attempt")
);
assert.match(saveFunction, /now\(\) >= v_attempt\.expires_at/i, "answer saves must enforce server deadline");
assert.match(saveFunction, /logos_td_finalize_attempt_internal\(v_attempt\.id, true\)/i, "late answer saves must finalize expired attempt");

console.log("Controlled assessment migration invariant checks passed.");
