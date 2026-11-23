const assert = require("node:assert/strict");
const fs = require("node:fs");

const sql = fs.readFileSync("docs/STAGING_TEST_DRILLER_FOUNDATION.sql", "utf8");

assert.match(sql, /^BEGIN;/m);
assert.match(sql, /^COMMIT;/m);
for (const table of [
  "admin_users",
  "students",
  "logos_td_exams",
  "logos_td_questions",
  "logos_td_exam_questions",
  "logos_td_attempts",
]) {
  assert.match(sql, new RegExp("CREATE TABLE IF NOT EXISTS public\\." + table + "\\b", "i"), table + " foundation table must exist");
}
assert.match(sql, /CREATE OR REPLACE FUNCTION public\.is_logos_admin\(\)/i);
assert.match(sql, /auth_user_id uuid UNIQUE REFERENCES auth\.users\(id\) ON DELETE SET NULL/i);
assert.match(sql, /student_code text NOT NULL UNIQUE/i);
assert.match(sql, /ALTER TABLE public\.logos_td_exams ENABLE ROW LEVEL SECURITY/i);
assert.match(sql, /ALTER TABLE public\.logos_td_questions ENABLE ROW LEVEL SECURITY/i);
assert.match(sql, /REVOKE ALL ON public\.logos_td_exams FROM PUBLIC, anon, authenticated/i);
assert.match(sql, /REVOKE ALL ON public\.logos_td_questions FROM PUBLIC, anon, authenticated/i);
assert.match(sql, /REVOKE ALL ON FUNCTION public\.logos_td_student_exam_questions\(text\) FROM PUBLIC, anon, authenticated/i);
assert.match(sql, /REVOKE ALL ON FUNCTION public\.logos_td_student_submit_attempt\(text, uuid, jsonb, integer\) FROM PUBLIC, anon, authenticated/i);
assert.match(sql, /STAGING-ONLY/i);
assert.match(sql, /Do NOT run against the live/i);
assert.doesNotMatch(sql, /INSERT INTO public\.(students|admin_users|payments)\b/i, "foundation must not copy personal or payment records");

console.log("Staging Test Driller foundation invariant checks passed.");
