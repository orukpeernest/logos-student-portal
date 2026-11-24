const fs = require("node:fs");
const assert = require("node:assert/strict");

const sql = fs.readFileSync(
  "supabase/migrations/202611240002_admin_student_profile_import_rpc.sql",
  "utf8"
);

assert.match(sql, /create or replace function public\.logos_admin_import_student_profiles\s*\(\s*p_students jsonb,\s*p_academic_session text/i);
assert.match(sql, /security definer[\s\S]*?set search_path = ''/i);
assert.match(sql, /auth\.uid\(\) is null or not coalesce\(public\.is_logos_admin\(\), false\)/i);
assert.match(sql, /jsonb_array_length\(p_students\) > 100/i);
assert.match(sql, /pg_column_size\(p_students\) > 1048576/i);
assert.match(sql, /on conflict \(app_student_id\) where app_student_id is not null/i);
assert.match(sql, /s\.student_code = x\.value->>'reg'[\s\S]*?s\.app_student_id is distinct from x\.value->>'id'/i);
assert.match(sql, /grant execute on function public\.logos_admin_import_student_profiles\(jsonb, text\) to authenticated/i);
assert.match(sql, /revoke all on function public\.logos_admin_import_student_profiles\(jsonb, text\) from anon/i);
assert.match(sql, /auth_accounts_created', 0/i);
assert.match(sql, /payments_imported', 0/i);
assert.match(sql, /attendance_imported', 0/i);
assert.match(sql, /photos_deferred/i);
for (const key of ["cycle", "dbase", "dstart", "expiry", "next"]) assert.ok(sql.includes("'" + key + "'"), "missing preserved legacy metadata key: " + key);
assert.doesNotMatch(sql, /disable row level security|drop policy|grant .* on table public\.students/i);
assert.doesNotMatch(sql, /service_role|sb_secret_|p_password|password_hash/i);

console.log("Admin student import RPC safety checks passed.");
