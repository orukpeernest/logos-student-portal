const assert = require("node:assert/strict");
const fs = require("node:fs");

const worker = fs.readFileSync(
  "supabase/functions/finalize-expired-tests/index.ts",
  "utf8"
);

assert.match(worker, /Deno\.serve\(async \(request: Request\)/);
assert.match(worker, /request\.method !== "POST"/, "worker must reject non-POST requests");
assert.match(worker, /request\.headers\.get\("x-cron-secret"\)/, "worker must require the scheduler secret header");
assert.match(worker, /!cronSecret \|\| !suppliedSecret \|\| suppliedSecret !== cronSecret/, "missing or incorrect scheduler secrets must be rejected");
assert.match(worker, /Deno\.env\.get\("SUPABASE_URL"\)/, "database URL must come from server-side secrets");
assert.match(worker, /Deno\.env\.get\("SUPABASE_SERVICE_ROLE_KEY"\)/, "service-role key must come from server-side secrets");
assert.match(worker, /\/rest\/v1\/rpc\/logos_td_finalize_expired_attempts/, "worker must call the protected expiry RPC");
assert.match(worker, /Authorization: `Bearer \$\{serviceRoleKey\}`/, "service-role authorization must be server-side");
assert.match(worker, /apikey: serviceRoleKey/, "RPC request must authenticate with the server-side service key");
assert.match(worker, /if \(!response\.ok\)/, "worker must report RPC failures");
assert.match(worker, /ok: true/, "successful worker response must be explicit");
assert.doesNotMatch(worker, /SUPABASE_SERVICE_ROLE_KEY\s*=\s*["'][^"']+["']/, "no service-role secret may be hard-coded");

console.log("Expiry worker security and RPC contract checks passed.");
