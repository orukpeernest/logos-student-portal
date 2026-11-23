const fs = require("node:fs");
const assert = require("node:assert/strict");
const sql = fs.readFileSync("supabase/migrations/202611240001_student_profile_import_fields.sql", "utf8");

for (const column of [
  "app_student_id text",
  "gender text",
  "department text",
  "exam_type text",
  "fee_amount numeric(12,2)",
  "app_created_on date",
  "enrollment_month text",
  "photo_storage_path text",
  "legacy_metadata jsonb"
]) assert.ok(sql.includes(column), "missing additive field: " + column);

assert.match(sql, /create unique index if not exists students_app_student_id_uidx[\s\S]*?where app_student_id is not null/i);
assert.match(sql, /distinct from academic_session/i.test(sql) ? /./ : /enrollment_month[\s\S]*?YYYY-MM/);
assert.match(sql, /Do not use for balances until currency and meaning are confirmed/i);
assert.doesNotMatch(sql, /disable row level security|drop policy|alter table public\.students disable row level security/i);
assert.doesNotMatch(sql, /service_role|sb_secret_/i);
console.log("Student profile import migration safety checks passed.");
