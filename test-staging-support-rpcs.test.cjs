const fs = require("node:fs");
const assert = require("node:assert/strict");

const sql = fs.readFileSync("docs/STAGING_RESTORE_ORIGINAL_SUPPORT_RPCS.sql", "utf8");
const lower = sql.toLowerCase();

assert.match(sql, /-- run only after:[\s\S]*STAGING_TEST_DRILLER_FOUNDATION[\s\S]*202611230001_controlled_test_attempts/i);
assert.match(sql, /\bBEGIN\s*;/i);
assert.match(sql, /\bCOMMIT\s*;/i);

const required = [
  "is_logos_admin",
  "logos_td_admin_attach_question",
  "logos_td_admin_delete_question",
  "logos_td_admin_save_question",
  "logos_td_admin_set_exam_status",
  "logos_td_student_available_exams",
  "logos_td_student_practice_questions"
];
for (const name of required) {
  assert.ok(lower.includes("create or replace function public." + name), `Missing restored RPC: ${name}`);
  assert.ok(lower.includes("revoke all on function public." + name), `Missing explicit revoke: ${name}`);
  assert.ok(lower.includes("grant execute on function public." + name), `Missing authenticated grant: ${name}`);
}

assert.match(sql, /security definer[\s\S]*set search_path to ''/i);
assert.match(sql, /where auth_user_id = auth\.uid\(\)/i);
assert.match(sql, /where is_practice = true/i);
assert.match(sql, /limit least\(greatest\(coalesce\(p_limit, 50\), 1\), 100\)/i);

// The controlled migration owns these implementations and browser permissions.
// This restoration must never re-enable the old client-authoritative path.
assert.match(sql, /revoke all on function public\.logos_td_student_exam_questions\(text\) from public, anon, authenticated/i);
assert.match(sql, /revoke all on function public\.logos_td_student_submit_attempt\(text, uuid, jsonb, integer\) from public, anon, authenticated/i);
assert.doesNotMatch(sql, /grant execute on function public\.logos_td_student_(exam_questions|submit_attempt)/i);
assert.doesNotMatch(sql, /create or replace function public\.logos_td_student_(exam_questions|submit_attempt)/i);

// The newer controlled implementations must not be overwritten by this support script.
assert.doesNotMatch(sql, /create or replace function public\.logos_td_admin_create_exam/i);
assert.doesNotMatch(sql, /create or replace function public\.logos_td_student_results/i);

console.log("Staging support RPC restoration invariants passed.");
