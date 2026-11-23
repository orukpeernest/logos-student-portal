const assert = require("node:assert/strict");
const fs = require("node:fs");

const portal = fs.readFileSync("portal.js", "utf8");
const admin = fs.readFileSync("admin-portal.js", "utf8");
const migration = fs.readFileSync(
  "supabase/migrations/202611230001_controlled_test_attempts.sql",
  "utf8"
);

function hasRpcCall(source, name, args) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const call = new RegExp('(?:adminRpc|rpc)\\("' + escaped + '"\\s*,\\s*\\{([\\s\\S]*?)\\}\\)', "m");
  const match = source.match(call);
  assert.ok(match, "frontend must call " + name);
  for (const arg of args) {
    assert.match(match[1], new RegExp("\\b" + arg + "\\s*:"));
  }
}

hasRpcCall(portal, "logos_td_student_start_exam", ["p_exam_id"]);
hasRpcCall(portal, "logos_td_student_save_exam_answer", [
  "p_attempt_id", "p_question_id", "p_selected_answer"
]);
hasRpcCall(portal, "logos_td_student_submit_exam_attempt", ["p_attempt_id"]);
hasRpcCall(portal, "logos_td_student_attempt_detail", ["p_attempt_id"]);
hasRpcCall(admin, "logos_td_admin_configure_exam", [
  "p_exam_id", "p_academic_session", "p_starts_at", "p_ends_at", "p_max_attempts"
]);
hasRpcCall(admin, "logos_td_admin_bulk_upload_exam_questions", [
  "p_exam_id", "p_questions"
]);
hasRpcCall(admin, "logos_td_admin_set_results_released", ["p_exam_id", "p_released"]);

assert.match(portal, /UPDATE TEST QUESTIONS/, "student must have the agreed manual test refresh action");
assert.match(portal, /logos_td_student_active_attempts/, "student portal must recover active attempts");
assert.match(portal, /logos_td_student_practice_questions/, "Practice Mode must retain its separate question-bank path");
assert.match(admin, /is_practice:false/, "test uploads must be marked as non-practice questions");
assert.match(migration, /q\.is_practice = false/i, "controlled attempts must load only assessment-specific questions");
assert.doesNotMatch(portal, /rpc\("logos_td_student_exam_questions"/, "student frontend must not use the revoked legacy question-fetch RPC");
assert.doesNotMatch(portal, /rpc\("logos_td_student_submit_attempt"/, "student frontend must not use the revoked client-authoritative submission RPC");

console.log("Frontend-to-database controlled assessment contract checks passed.");
